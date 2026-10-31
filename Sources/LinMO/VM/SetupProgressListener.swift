import Foundation
import Virtualization

struct SetupStatus: Equatable {
    var line: String
    var progress: Double?
    var finished: Bool
    var errors: Int
}

final class SetupProgressListener: NSObject, VZVirtioSocketListenerDelegate {
    private let onStatus: @MainActor (SetupStatus) -> Void
    private var connections: [Reader] = []
    let listener = VZVirtioSocketListener()

    init(onStatus: @escaping @MainActor (SetupStatus) -> Void) {
        self.onStatus = onStatus
        super.init()
        listener.delegate = self
    }

    func attach(to machine: VZVirtualMachine) {
        guard let device = machine.socketDevices.first as? VZVirtioSocketDevice else { return }
        device.setSocketListener(listener, forPort: SetupReporter.port)
    }

    func detach(from machine: VZVirtualMachine?) {
        if let device = machine?.socketDevices.first as? VZVirtioSocketDevice {
            device.removeSocketListener(forPort: SetupReporter.port)
        }
        connections.forEach { $0.close() }
        connections.removeAll()
    }

    func listener(_ listener: VZVirtioSocketListener,
                  shouldAcceptNewConnection connection: VZVirtioSocketConnection,
                  from socketDevice: VZVirtioSocketDevice) -> Bool {
        let reader = Reader(connection: connection) { [onStatus] status in
            Task { @MainActor in onStatus(status) }
        }
        connections.append(reader)
        return true
    }

    private final class Reader {
        private let connection: VZVirtioSocketConnection
        private let handle: FileHandle
        private var buffer = Data()

        init(connection: VZVirtioSocketConnection, onStatus: @escaping (SetupStatus) -> Void) {
            self.connection = connection
            self.handle = FileHandle(fileDescriptor: connection.fileDescriptor, closeOnDealloc: false)
            handle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                self.buffer.append(data)
                while let newline = self.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = self.buffer[self.buffer.startIndex..<newline]
                    self.buffer.removeSubrange(self.buffer.startIndex...newline)
                    if let status = Self.parse(line) {
                        onStatus(status)
                    }
                }
            }
        }

        func close() {
            handle.readabilityHandler = nil
            connection.close()
        }

        private static func parse(_ data: Data) -> SetupStatus? {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return SetupStatus(
                line: object["line"] as? String ?? "",
                progress: object["progress"] as? Double,
                finished: (object["state"] as? String) == "done",
                errors: object["errors"] as? Int ?? 0
            )
        }
    }
}
