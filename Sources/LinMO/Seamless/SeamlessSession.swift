import AppKit
import Foundation
import Virtualization

@MainActor
final class SeamlessSession: ObservableObject {
    struct App: Identifiable, Decodable, Hashable {
        let id: String
        let name: String
        let generic: String?
        let categories: [String]?
        let icon: String?
        let iconFormat: String?
    }

    struct WindowInfo: Decodable, Equatable {
        let id: UInt32
        let kind: String
        let title: String
        let app: String
        let x: Int
        let y: Int
        let w: Int
        let h: Int
        let parent: UInt32

        var isPopup: Bool { kind == "popup" }
    }

    private struct Hello: Decodable {
        let version: Int
        let features: [String]?
        let screen: [Int]
        let session: String?
    }

    private final class Link {
        let port: UInt32
        let connection: SeamlessConnection
        var features: Set<String> = []
        var version = 0
        var screen = CGSize(width: 1920, height: 1200)
        var apps: [App] = []
        var session = "x11"

        init(port: UInt32, connection: SeamlessConnection) {
            self.port = port
            self.connection = connection
        }

        var isWayland: Bool { port == SeamlessPorts.wayland }
    }

    static let currentAgentVersion = 6

    @Published private(set) var isConnected = false
    @Published private(set) var hasX11Agent = false
    @Published private(set) var hasWayland = false
    @Published private(set) var isEnabled = false
    @Published private(set) var apps: [App] = []
    @Published private(set) var agentNeedsUpdate = false

    var machineName: String
    var prefersHiDPI = false {
        didSet { if oldValue != prefersHiDPI { links.values.forEach(sendConfig) } }
    }
    var prefersMacTextInput = true
    var prefersWayland = false {
        didSet { refreshApps() }
    }
    var onAppsChanged: (@MainActor ([App]) -> Void)?
    private var pendingLaunches: [String] = []

    struct DraggedFile {
        let name: String
        let data: Data
    }

    private var links: [UInt32: Link] = [:]
    private let listener = AgentListener()
    private var infos: [UInt32: WindowInfo] = [:]
    private var controllers: [UInt32: SeamlessWindowController] = [:]
    private var icons: [UInt32: CGImage] = [:]
    private(set) var lastFocusedNormal: UInt32?
    private var eventMonitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var dragOutHandlers: [UInt32: ([DraggedFile]) -> Void] = [:]
    private var dragOutWindow: UInt32?
    private var textInputCursors: [UInt32: CGRect] = [:]
    private var syncedPasteboardChange = -1
    private var activeObserver: NSObjectProtocol?

    init(machineName: String) {
        self.machineName = machineName
        listener.onConnection = { [weak self] connection, port in
            Task { @MainActor in self?.adopt(connection, port: port) }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncClipboardToLinux() }
        }
    }



    private static func isWaylandWindow(_ id: UInt32) -> Bool { id & 0x8000_0000 != 0 }

    private func link(for id: UInt32) -> Link? {
        links[Self.isWaylandWindow(id) ? SeamlessPorts.wayland : SeamlessPorts.agent]
    }

    var scale: CGFloat {
        prefersHiDPI && links.values.contains { $0.features.contains("scale") } ? 2 : 1
    }

    var usesMacTextInput: Bool {
        prefersMacTextInput && links.values.contains { $0.features.contains("text") }
    }

    func supports(_ feature: String, window id: UInt32) -> Bool {
        link(for: id)?.features.contains(feature) ?? false
    }

    func guestScreen(for id: UInt32) -> CGSize {
        link(for: id)?.screen ?? CGSize(width: 1920, height: 1200)
    }

    private var launchLink: Link? {
        let x11 = links[SeamlessPorts.agent], wayland = links[SeamlessPorts.wayland]
        if let wayland, prefersWayland || x11 == nil || x11?.session == "wayland" { return wayland }
        return x11 ?? wayland
    }


    func attach(to machine: VZVirtualMachine) {
        guard let device = machine.socketDevices.first as? VZVirtioSocketDevice else { return }
        device.setSocketListener(listener.vzListener, forPort: SeamlessPorts.agent)
        device.setSocketListener(listener.vzListener, forPort: SeamlessPorts.wayland)
    }

    func detach(from machine: VZVirtualMachine?) {
        if let device = machine?.socketDevices.first as? VZVirtioSocketDevice {
            device.removeSocketListener(forPort: SeamlessPorts.agent)
            device.removeSocketListener(forPort: SeamlessPorts.wayland)
        }
        for port in Array(links.keys) { dropLink(port: port) }
        isEnabled = false
        pendingLaunches.removeAll()
    }

    private func adopt(_ connection: SeamlessConnection, port: UInt32) {
        dropLink(port: port)
        let link = Link(port: port, connection: connection)
        links[port] = link
        connection.onMessage = { [weak self] type, payload in
            Task { @MainActor in self?.handle(type, payload, from: port) }
        }
        connection.onFrame = { [weak self] frame in
            Task { @MainActor in self?.controllers[frame.windowID]?.show(frame.image) }
        }
        connection.onIcon = { [weak self] icon in
            Task { @MainActor in
                self?.icons[icon.windowID] = icon.image
                self?.controllers[icon.windowID]?.setIcon(icon.image)
            }
        }
        connection.onClose = { [weak self, weak connection] in
            Task { @MainActor in
                guard let self, let connection, self.links[port]?.connection === connection else { return }
                self.dropLink(port: port)
            }
        }
        connection.start()
        updateConnectionState()
    }

    private func dropLink(port: UInt32) {
        guard let link = links.removeValue(forKey: port) else { return }
        if let id = dragOutWindow, Self.isWaylandWindow(id) == link.isWayland {
            finishDragOut([])
        }
        link.connection.close()
        for id in Array(infos.keys) where Self.isWaylandWindow(id) == link.isWayland {
            infos[id] = nil
            icons[id] = nil
            textInputCursors[id] = nil
            controllers.removeValue(forKey: id)?.close()
        }
        updatePopupMonitors()
        updateConnectionState()
        refreshApps()
    }

    private func updateConnectionState() {
        hasX11Agent = links[SeamlessPorts.agent] != nil
        hasWayland = links[SeamlessPorts.wayland] != nil
        isConnected = !links.isEmpty
        agentNeedsUpdate = links[SeamlessPorts.agent].map { $0.version < Self.currentAgentVersion } ?? false
    }

    private func refreshApps() {
        let current = launchLink?.apps ?? []
        guard current != apps else { return }
        apps = current
        if !current.isEmpty { onAppsChanged?(current) }
    }


    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            infos.values.forEach(present)
        } else {
            closeAllWindows()
        }
        for link in links.values {
            link.connection.send(.stream, ["enabled": enabled])
        }
    }

    func notifyFolderChanges(_ paths: [String]) {
        guard let link = links[SeamlessPorts.agent], link.features.contains("folders") else { return }
        link.connection.send(.folderChanged, ["paths": paths])
    }

    func launch(_ app: App) {
        launchLink?.connection.send(.launch, ["app": app.id])
    }

    func launchWhenReady(_ appID: String) {
        setEnabled(true)
        if let link = launchLink, link.version > 0 {
            link.connection.send(.launch, ["app": appID])
        } else if !pendingLaunches.contains(appID) {
            pendingLaunches.append(appID)
        }
    }

    private func flushPendingLaunches() {
        guard !pendingLaunches.isEmpty, let link = launchLink, link.version > 0 else { return }
        for appID in pendingLaunches {
            link.connection.send(.launch, ["app": appID])
        }
        pendingLaunches.removeAll()
    }

    private func sendConfig(_ link: Link) {
        guard link.features.contains("scale") else { return }
        link.connection.send(.config, ["scale": prefersHiDPI ? 2 : 1])
    }


    private func handle(_ type: SeamlessMessage, _ payload: Data, from port: UInt32) {
        guard let link = links[port] else { return }
        let decoder = JSONDecoder()
        switch type {
        case .hello:
            guard let hello = try? decoder.decode(Hello.self, from: payload) else { return }
            if hello.screen.count == 2 {
                link.screen = CGSize(width: hello.screen[0], height: hello.screen[1])
            }
            link.features = Set(hello.features ?? [])
            link.version = hello.version
            link.session = hello.session ?? "x11"
            updateConnectionState()
            refreshApps()
            sendConfig(link)
            if link.features.contains("clipboard") {
                sendClipboard(to: [link])
            }
            if isEnabled {
                link.connection.send(.stream, ["enabled": true])
            }
            flushPendingLaunches()
        case .apps:
            struct AppList: Decodable { let apps: [App] }
            if let list = try? decoder.decode(AppList.self, from: payload) {
                link.apps = list.apps
                refreshApps()
            }
        case .window:
            guard let info = try? decoder.decode(WindowInfo.self, from: payload) else { return }
            infos[info.id] = info
            if isEnabled { present(info) }
        case .windowClosed:
            struct Closed: Decodable { let id: UInt32 }
            guard let closed = try? decoder.decode(Closed.self, from: payload) else { return }
            infos[closed.id] = nil
            icons[closed.id] = nil
            textInputCursors[closed.id] = nil
            link.connection.forgetSurface(closed.id)
            controllers.removeValue(forKey: closed.id)?.close()
            if lastFocusedNormal == closed.id { lastFocusedNormal = nil }
            updatePopupMonitors()
        case .textInput:
            struct TextInput: Decodable { let id: UInt32; let enabled: Bool; let x, y, w, h: Int }
            guard let input = try? decoder.decode(TextInput.self, from: payload) else { return }
            textInputCursors[input.id] = input.enabled ? CGRect(x: input.x, y: input.y, width: input.w, height: input.h) : nil
        case .clipboard:
            struct Clipboard: Decodable { let text: String?; let image: String? }
            guard let clipboard = try? decoder.decode(Clipboard.self, from: payload) else { return }
            receiveClipboard(text: clipboard.text, png: clipboard.image.flatMap { Data(base64Encoded: $0) })
        case .dragData:
            finishDragOut(Self.unpackFiles(payload))
        case .dragNone:
            finishDragOut([])
        case .focused:
            struct Focused: Decodable { let id: UInt32 }
            guard let focused = try? decoder.decode(Focused.self, from: payload) else { return }
            lastFocusedNormal = focused.id
            if NSApp.isActive, let controller = controllers[focused.id], !controller.window.isKeyWindow {
                controller.window.makeKeyAndOrderFront(nil)
            }
        default:
            break
        }
    }

    private func present(_ info: WindowInfo) {
        if let controller = controllers[info.id] {
            controller.update(info)
        } else {
            let controller = SeamlessWindowController(info: info, session: self)
            controllers[info.id] = controller
            if let icon = icons[info.id] { controller.setIcon(icon) }
            controller.showInitially()
            updatePopupMonitors()
        }
    }

    private func closeAllWindows() {
        controllers.values.forEach { $0.close() }
        controllers.removeAll()
        updatePopupMonitors()
    }


    private func updatePopupMonitors() {
        let hasPopups = controllers.values.contains { $0.isPopup }
        if hasPopups && eventMonitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                Task { @MainActor in self?.dismissPopups() }
            }) {
                eventMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                let clicked = (event.window?.contentView as? SeamlessView)?.windowID
                Task { @MainActor in self?.dismissPopups(exceptLinkOf: clicked) }
                return event
            }) {
                eventMonitors.append(local)
            }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.dismissPopups() }
            }
        } else if !hasPopups && !eventMonitors.isEmpty {
            eventMonitors.forEach(NSEvent.removeMonitor)
            eventMonitors.removeAll()
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
            }
            resignObserver = nil
        }
    }

    private func dismissPopups(exceptLinkOf clicked: UInt32? = nil) {
        let escape = 9
        var sentEscape = false
        for popup in controllers.values where popup.isPopup {
            if let clicked, Self.isWaylandWindow(clicked) == Self.isWaylandWindow(popup.id) { continue }
            if supports("popupclose", window: popup.id) {
                send(.close, ["id": popup.id])
            } else if !sentEscape {
                send(.key, ["id": popup.id, "keycode": escape, "pressed": true])
                send(.key, ["id": popup.id, "keycode": escape, "pressed": false])
                sentEscape = true
            }
        }
    }


    private func syncClipboardToLinux() {
        guard NSPasteboard.general.changeCount != syncedPasteboardChange else { return }
        sendClipboard(to: links.values.filter { $0.features.contains("clipboard") })
    }

    private func sendClipboard(to targets: [Link]) {
        guard !targets.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        syncedPasteboardChange = pasteboard.changeCount
        let text = pasteboard.string(forType: .string).flatMap { !$0.isEmpty && $0.utf8.count <= 16 << 20 ? $0 : nil }
        var image: String?
        if pasteboard.types?.contains(.fileURL) != true, let png = Self.pasteboardPNG(pasteboard), png.count <= 32 << 20 {
            image = png.base64EncodedString()
        }
        for link in targets {
            var message: [String: Any] = [:]
            if let text { message["text"] = text }
            if let image, link.features.contains("clipboard-image") { message["image"] = image }
            if !message.isEmpty {
                link.connection.send(.setClipboard, message)
            }
        }
    }

    private static func pasteboardPNG(_ pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func receiveClipboard(text: String?, png: Data?) {
        let item = NSPasteboardItem()
        if let text, !text.isEmpty {
            item.setString(text, forType: .string)
        }
        if let png, let bitmap = NSBitmapImageRep(data: png) {
            item.setData(png, forType: .png)
            if let tiff = bitmap.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        }
        guard !item.types.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        syncedPasteboardChange = pasteboard.changeCount
    }


    func requestDragOut(from id: UInt32, completion: @escaping ([DraggedFile]) -> Void) {
        guard supports("dragout", window: id), dragOutWindow == nil else { return }
        dragOutWindow = id
        dragOutHandlers[id] = completion
        send(.dragOut, ["id": id])
    }

    private func finishDragOut(_ files: [DraggedFile]) {
        guard let id = dragOutWindow else { return }
        dragOutWindow = nil
        dragOutHandlers.removeValue(forKey: id)?(files)
    }

    private static func unpackFiles(_ payload: Data) -> [DraggedFile] {
        guard payload.count >= 4 else { return [] }
        let base = payload.startIndex
        let jsonLength = Int(payload[base]) | Int(payload[base + 1]) << 8 | Int(payload[base + 2]) << 16 | Int(payload[base + 3]) << 24
        guard payload.count >= 4 + jsonLength else { return [] }
        struct Meta: Decodable {
            struct File: Decodable { let name: String; let size: Int }
            let files: [File]
        }
        guard let meta = try? JSONDecoder().decode(Meta.self, from: payload.subdata(in: (base + 4)..<(base + 4 + jsonLength))) else {
            return []
        }
        var offset = base + 4 + jsonLength
        var files: [DraggedFile] = []
        for file in meta.files {
            guard file.size >= 0, offset + file.size <= payload.endIndex else { break }
            let name = (file.name as NSString).lastPathComponent
            files.append(DraggedFile(name: name.isEmpty ? "file" : name, data: payload.subdata(in: offset..<(offset + file.size))))
            offset += file.size
        }
        return files
    }


    func info(for id: UInt32) -> WindowInfo? { infos[id] }

    func textInputCursor(for id: UInt32) -> CGRect? {
        guard supports("preedit", window: id) else { return nil }
        return textInputCursors[id]
    }

    func send(_ type: SeamlessMessage, _ object: [String: Any]) {
        if let id = object["id"] as? UInt32 {
            link(for: id)?.connection.send(type, object)
        } else {
            links.values.forEach { $0.connection.send(type, object) }
        }
    }

    func didFocus(_ id: UInt32) {
        if infos[id]?.isPopup == false {
            lastFocusedNormal = id
        }
        syncClipboardToLinux()
        send(.focus, ["id": id])
    }

    func drop(files: [URL], on id: UInt32, at point: CGPoint) {
        guard let connection = link(for: id)?.connection else { return }
        let limit = 1 << 30
        Task.detached(priority: .userInitiated) {
            var entries: [[String: Any]] = []
            var contents = Data()
            for url in files {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      contents.count + (values.fileSize ?? 0) <= limit,
                      let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
                entries.append(["name": url.lastPathComponent, "size": data.count])
                contents.append(data)
            }
            guard !entries.isEmpty else { return }
            let meta: [String: Any] = ["id": id, "x": Int(point.x), "y": Int(point.y), "files": entries]
            guard let json = try? JSONSerialization.data(withJSONObject: meta) else { return }
            var payload = Data()
            var length = UInt32(json.count).littleEndian
            withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
            payload.append(json)
            payload.append(contents)
            connection.send(.drop, raw: payload)
        }
    }

    func anchoredFrame(for info: WindowInfo) -> NSRect? {
        let anchorID = info.parent != 0 && controllers[info.parent] != nil ? info.parent : lastFocusedNormal
        guard let anchorID, anchorID != info.id,
              Self.isWaylandWindow(anchorID) == Self.isWaylandWindow(info.id),
              let anchor = controllers[anchorID], let anchorInfo = infos[anchorID] else { return nil }
        let content = anchor.window.convertToScreen(anchor.window.contentLayoutRect)
        let s = scale
        let dx = CGFloat(info.x - anchorInfo.x) / s
        let dy = CGFloat(info.y - anchorInfo.y) / s
        let size = CGSize(width: CGFloat(info.w) / s, height: CGFloat(info.h) / s)
        return NSRect(x: content.minX + dx, y: content.maxY - dy - size.height, width: size.width, height: size.height)
    }
}

private final class AgentListener: NSObject, VZVirtioSocketListenerDelegate {
    let vzListener = VZVirtioSocketListener()
    var onConnection: ((SeamlessConnection, UInt32) -> Void)?

    override init() {
        super.init()
        vzListener.delegate = self
    }

    func listener(_ listener: VZVirtioSocketListener,
                  shouldAcceptNewConnection connection: VZVirtioSocketConnection,
                  from socketDevice: VZVirtioSocketDevice) -> Bool {
        onConnection?(SeamlessConnection(connection: connection), connection.destinationPort)
        return true
    }
}
