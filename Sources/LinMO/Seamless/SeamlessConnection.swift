import CoreGraphics
import Foundation
import Virtualization

enum SeamlessMessage: UInt16 {
    case hello = 0x01
    case window = 0x02
    case windowClosed = 0x03
    case frame = 0x04
    case apps = 0x05
    case focused = 0x06
    case frameRect = 0x07
    case icon = 0x08
    case dragData = 0x09
    case dragNone = 0x0A
    case clipboard = 0x0B
    case textInput = 0x0C
    case pointer = 0x10
    case button = 0x11
    case key = 0x12
    case scroll = 0x13
    case resize = 0x14
    case focus = 0x15
    case close = 0x16
    case launch = 0x17
    case stream = 0x18
    case text = 0x19
    case drop = 0x1A
    case config = 0x1B
    case dragOut = 0x1C
    case setClipboard = 0x1D
    case preedit = 0x1E
    case folderChanged = 0x20
}

enum SeamlessPorts {
    static let agent: UInt32 = 5200
    static let wayland: UInt32 = 5202
}

struct SeamlessFrame {
    let windowID: UInt32
    let image: CGImage
}

final class SeamlessConnection {
    private let connection: VZVirtioSocketConnection
    private let handle: FileHandle
    private let writeQueue = DispatchQueue(label: "linmo.seamless.write")
    private var buffer = Data()
    private var closed = false

    private var surfaces: [UInt32: Surface] = [:]
    private let surfacesLock = NSLock()

    var onMessage: ((SeamlessMessage, Data) -> Void)?
    var onFrame: ((SeamlessFrame) -> Void)?
    var onIcon: ((SeamlessFrame) -> Void)?
    var onClose: (() -> Void)?

    init(connection: VZVirtioSocketConnection) {
        self.connection = connection
        self.handle = FileHandle(fileDescriptor: connection.fileDescriptor, closeOnDealloc: false)
    }

    func start() {
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                self.finish()
                return
            }
            self.buffer.append(data)
            self.drain()
        }
    }

    private func drain() {
        while buffer.count >= 6 {
            let start = buffer.startIndex
            let length = Int(buffer.leUInt32(at: start))
            let rawType = buffer.leUInt16(at: start + 4)
            guard buffer.count >= 6 + length else { return }
            let payload = buffer.subdata(in: (start + 6)..<(start + 6 + length))
            buffer.removeSubrange(start..<(start + 6 + length))

            guard let type = SeamlessMessage(rawValue: rawType) else { continue }
            switch type {
            case .frame, .frameRect:
                if let frame = applyFrame(payload, partial: type == .frameRect) { onFrame?(frame) }
            case .icon:
                if let icon = Self.decodeIcon(payload) { onIcon?(icon) }
            default:
                onMessage?(type, payload)
            }
        }
        if buffer.isEmpty { buffer = Data() }
    }

    func forgetSurface(_ id: UInt32) {
        surfacesLock.lock()
        surfaces[id] = nil
        surfacesLock.unlock()
    }


    private func applyFrame(_ payload: Data, partial: Bool) -> SeamlessFrame? {
        let headerSize = partial ? 32 : 16
        guard payload.count >= headerSize else { return nil }
        let base = payload.startIndex
        func field(_ index: Int) -> Int { Int(payload.leUInt32(at: base + index * 4)) }

        let id = UInt32(field(0))
        let fullWidth = field(1), fullHeight = field(2)
        let x = partial ? field(3) : 0
        let y = partial ? field(4) : 0
        let width = partial ? field(5) : fullWidth
        let height = partial ? field(6) : fullHeight
        let stride = partial ? field(7) : field(3)
        guard fullWidth > 0, fullHeight > 0, width > 0, height > 0, stride >= width * 4,
              x + width <= fullWidth, y + height <= fullHeight,
              payload.count >= headerSize + stride * height else { return nil }

        surfacesLock.lock()
        defer { surfacesLock.unlock() }

        var surface = surfaces[id]
        if surface == nil || surface!.width != fullWidth || surface!.height != fullHeight {
            guard !partial, let created = Surface(width: fullWidth, height: fullHeight) else { return nil }
            surface = created
            surfaces[id] = created
        }
        guard let surface else { return nil }

        payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            surface.write(source: raw.baseAddress! + headerSize, sourceStride: stride,
                          x: x, y: y, width: width, height: height)
        }
        guard let image = surface.makeImage() else { return nil }
        return SeamlessFrame(windowID: id, image: image)
    }

    private static func decodeIcon(_ payload: Data) -> SeamlessFrame? {
        guard payload.count >= 12 else { return nil }
        let base = payload.startIndex
        let id = payload.leUInt32(at: base)
        let width = Int(payload.leUInt32(at: base + 4))
        let height = Int(payload.leUInt32(at: base + 8))
        guard width > 0, height > 0, width <= 512, height <= 512, payload.count >= 12 + width * height * 4 else { return nil }
        let pixels = payload.subdata(in: (base + 12)..<(base + 12 + width * height * 4))
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        return SeamlessFrame(windowID: id, image: image)
    }


    func send(_ type: SeamlessMessage, _ object: [String: Any]) {
        guard let payload = try? JSONSerialization.data(withJSONObject: object) else { return }
        send(type, raw: payload)
    }

    func send(_ type: SeamlessMessage, raw payload: Data) {
        var message = Data(capacity: payload.count + 6)
        var length = UInt32(payload.count).littleEndian
        var rawType = type.rawValue.littleEndian
        withUnsafeBytes(of: &length) { message.append(contentsOf: $0) }
        withUnsafeBytes(of: &rawType) { message.append(contentsOf: $0) }
        message.append(payload)
        writeQueue.async { [weak self] in
            guard let self, !self.closed else { return }
            do {
                try self.handle.write(contentsOf: message)
            } catch {
                self.finish()
            }
        }
    }

    func close() {
        handle.readabilityHandler = nil
        writeQueue.sync { closed = true }
        connection.close()
    }

    private func finish() {
        handle.readabilityHandler = nil
        let callback = onClose
        onClose = nil
        callback?()
    }
}

private final class Surface {
    let width: Int
    let height: Int
    private let context: CGContext

    init?(width: Int, height: Int) {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        self.width = width
        self.height = height
        self.context = context
    }

    func write(source: UnsafeRawPointer, sourceStride: Int, x: Int, y: Int, width: Int, height: Int) {
        guard let destination = context.data else { return }
        let destinationStride = context.bytesPerRow
        for row in 0..<height {
            memcpy(destination + (y + row) * destinationStride + x * 4,
                   source + row * sourceStride,
                   width * 4)
        }
    }

    func makeImage() -> CGImage? {
        context.makeImage()
    }
}

private extension Data {
    func leUInt32(at index: Index) -> UInt32 {
        self[index..<(index + 4)].enumerated().reduce(0) { $0 | (UInt32($1.element) << (8 * UInt32($1.offset))) }
    }

    func leUInt16(at index: Index) -> UInt16 {
        UInt16(self[index]) | (UInt16(self[index + 1]) << 8)
    }
}
