import Darwin
import Foundation
import Virtualization

struct ForwardedPort: Hashable, Identifiable {
    let guest: UInt16
    let mac: UInt16
    var id: UInt16 { guest }
}

@MainActor
final class PortForwarder: ObservableObject {
    static let guestPort: UInt32 = 5300

    @Published private(set) var forwarded: [ForwardedPort] = []
    @Published private(set) var guestUser: String?
    @Published private(set) var isAvailable = false

    private(set) var sshPort: UInt16 = 2222
    private weak var device: VZVirtioSocketDevice?
    private var timer: Timer?
    private var listeners: [UInt16: Listener] = [:]
    private var polling = false

    init() {
        signal(SIGPIPE, SIG_IGN)
    }

    var sshForward: ForwardedPort? {
        forwarded.first { $0.guest == 22 }
    }

    var sshCommand: String? {
        guard let ssh = sshForward else { return nil }
        let user = guestUser.map { "\($0)@" } ?? ""
        return "ssh -p \(ssh.mac) \(user)localhost"
    }

    func attach(to machine: VZVirtualMachine, sshPort: UInt16) {
        detach()
        guard let socket = machine.socketDevices.first as? VZVirtioSocketDevice else { return }
        device = socket
        self.sshPort = sshPort
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func detach() {
        timer?.invalidate()
        timer = nil
        listeners.values.forEach { $0.close() }
        listeners.removeAll()
        forwarded = []
        guestUser = nil
        isAvailable = false
        polling = false
        device = nil
    }

    private func poll() {
        guard !polling, let device else { return }
        polling = true
        device.connect(toPort: Self.guestPort) { [weak self] result in
            switch result {
            case .failure:
                Task { @MainActor in
                    guard let self else { return }
                    self.polling = false
                    if self.isAvailable {
                        self.apply(nil)
                    }
                }
            case .success(let connection):
                DispatchQueue.global(qos: .utility).async {
                    let data = Self.request(list: connection)
                    Task { @MainActor in
                        guard let self else { return }
                        self.polling = false
                        self.apply(data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
                    }
                }
            }
        }
    }

    private nonisolated static func request(list connection: VZVirtioSocketConnection) -> Data? {
        defer { connection.close() }
        let fd = connection.fileDescriptor
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var op = UInt8(ascii: "L")
        guard write(fd, &op, 1) == 1 else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func apply(_ object: [String: Any]?) {
        guard let object else {
            isAvailable = false
            listeners.values.forEach { $0.close() }
            listeners.removeAll()
            forwarded = []
            return
        }
        isAvailable = true
        guestUser = object["user"] as? String
        let wanted = Set((object["ports"] as? [Int] ?? []).compactMap { UInt16(exactly: $0) })

        for (guest, listener) in listeners where !wanted.contains(guest) {
            listener.close()
            listeners[guest] = nil
        }
        for guest in wanted where listeners[guest] == nil {
            let mac = guest == 22 ? sshPort : guest
            if let listener = Listener(macPort: mac, guestPort: guest, connect: { [weak self] completion in
                self?.openGuest(completion)
            }) {
                listeners[guest] = listener
            }
        }
        forwarded = listeners.values
            .map { ForwardedPort(guest: $0.guestPort, mac: $0.macPort) }
            .sorted { $0.guest < $1.guest }
    }

    private func openGuest(_ completion: @escaping (VZVirtioSocketConnection?) -> Void) {
        guard let device else {
            completion(nil)
            return
        }
        device.connect(toPort: Self.guestPort) { result in
            completion(try? result.get())
        }
    }

    private final class Listener {
        let macPort: UInt16
        let guestPort: UInt16
        private var sources: [DispatchSourceRead] = []

        init?(macPort: UInt16, guestPort: UInt16,
              connect: @escaping @MainActor (@escaping (VZVirtioSocketConnection?) -> Void) -> Void) {
            self.macPort = macPort
            self.guestPort = guestPort
            guard let v4 = Self.bind(port: macPort, ipv6: false) else { return nil }
            var fds = [v4]
            if let v6 = Self.bind(port: macPort, ipv6: true) {
                fds.append(v6)
            }
            let target = guestPort
            for fd in fds {
                let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
                source.setEventHandler {
                    let client = accept(fd, nil, nil)
                    guard client >= 0 else { return }
                    var on: Int32 = 1
                    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                    Task { @MainActor in
                        connect { connection in
                            guard let connection else {
                                Darwin.close(client)
                                return
                            }
                            Self.splice(client: client, connection: connection, port: target)
                        }
                    }
                }
                source.setCancelHandler { Darwin.close(fd) }
                source.resume()
                sources.append(source)
            }
        }

        func close() {
            sources.forEach { $0.cancel() }
            sources.removeAll()
        }

        private static func bind(port: UInt16, ipv6: Bool) -> Int32? {
            let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }
            var on: Int32 = 1
            if ipv6 {
                setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &on, socklen_t(MemoryLayout<Int32>.size))
            }
            let bound: Int32
            if ipv6 {
                var address = sockaddr_in6()
                address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                address.sin6_family = sa_family_t(AF_INET6)
                address.sin6_port = port.bigEndian
                address.sin6_addr = in6addr_loopback
                bound = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                    }
                }
            } else {
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = port.bigEndian
                address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
                bound = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard bound == 0, listen(fd, 64) == 0 else {
                Darwin.close(fd)
                return nil
            }
            let flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            return fd
        }

        private static func splice(client: Int32, connection: VZVirtioSocketConnection, port: UInt16) {
            let guest = connection.fileDescriptor
            var on: Int32 = 1
            setsockopt(guest, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var header: [UInt8] = [UInt8(ascii: "C"), UInt8(port >> 8), UInt8(port & 0xff)]
            guard write(guest, &header, header.count) == header.count else {
                Darwin.close(client)
                connection.close()
                return
            }
            let group = DispatchGroup()
            for (from, to) in [(client, guest), (guest, client)] {
                group.enter()
                Thread.detachNewThread {
                    Self.copy(from: from, to: to)
                    shutdown(to, SHUT_WR)
                    group.leave()
                }
            }
            group.notify(queue: .global()) {
                Darwin.close(client)
                connection.close()
            }
        }

        private static func copy(from: Int32, to: Int32) {
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = read(from, &buffer, buffer.count)
                if count <= 0 { return }
                var offset = 0
                while offset < count {
                    let written = buffer.withUnsafeBytes { write(to, $0.baseAddress! + offset, count - offset) }
                    if written <= 0 { return }
                    offset += written
                }
            }
        }
    }
}
