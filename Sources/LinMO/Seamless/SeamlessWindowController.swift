import AppKit
import UniformTypeIdentifiers

@MainActor
final class SeamlessWindowController: NSObject, NSWindowDelegate {
    let id: UInt32
    let window: NSWindow
    private let view: SeamlessView
    private weak var session: SeamlessSession?
    private var info: SeamlessSession.WindowInfo
    private var pendingResize: DispatchWorkItem?

    private static var cascadePoint = NSPoint.zero

    var isPopup: Bool { info.isPopup }

    private var scale: CGFloat { session?.scale ?? 1 }

    init(info: SeamlessSession.WindowInfo, session: SeamlessSession) {
        self.id = info.id
        self.info = info
        self.session = session
        let contentView = SeamlessView(windowID: info.id, session: session)
        self.view = contentView

        let scale = session.scale
        let size = NSSize(width: CGFloat(info.w) / scale, height: CGFloat(info.h) / scale)
        let newWindow: NSWindow
        if info.isPopup {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.level = .popUpMenu
            panel.hasShadow = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            newWindow = panel
        } else {
            newWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            newWindow.subtitle = session.machineName
            newWindow.tabbingMode = .disallowed
            let screen = session.guestScreen(for: info.id)
            newWindow.contentMaxSize = NSSize(width: screen.width / scale, height: screen.height / scale)
            newWindow.contentMinSize = Self.minimumSize(for: info, scale: scale)
        }
        newWindow.isReleasedWhenClosed = false
        newWindow.acceptsMouseMovedEvents = true
        newWindow.backgroundColor = .black
        newWindow.contentView = contentView
        self.window = newWindow
        super.init()

        window.delegate = self
        applyTitle()
    }


    func showInitially() {
        if info.isPopup || info.parent != 0, let frame = session?.anchoredFrame(for: info) {
            window.setFrame(frame, display: false)
        } else if !info.isPopup {
            if Self.cascadePoint == .zero {
                window.center()
                Self.cascadePoint = window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY))
            } else {
                Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint)
            }
        }

        if info.isPopup {
            window.orderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func update(_ newInfo: SeamlessSession.WindowInfo) {
        let sizeChanged = newInfo.w != info.w || newInfo.h != info.h
        let moved = newInfo.x != info.x || newInfo.y != info.y
        info = newInfo
        applyTitle()

        if info.isPopup {
            if (sizeChanged || moved), let frame = session?.anchoredFrame(for: info) {
                window.setFrame(frame, display: true)
            }
        } else {
            let minimum = Self.minimumSize(for: info, scale: scale)
            if window.contentMinSize != minimum { window.contentMinSize = minimum }
        }
        if !info.isPopup && sizeChanged && !window.inLiveResize {
            let content = NSSize(width: CGFloat(info.w) / scale, height: CGFloat(info.h) / scale)
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true)
        }
    }

    private static func minimumSize(for info: SeamlessSession.WindowInfo, scale: CGFloat) -> NSSize {
        NSSize(width: max(80, CGFloat(info.minW ?? 0) / scale), height: max(40, CGFloat(info.minH ?? 0) / scale))
    }

    func show(_ image: CGImage) {
        view.show(image, scale: scale)
    }

    func setIcon(_ image: CGImage) {
        window.miniwindowImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func close() {
        pendingResize?.cancel()
        window.delegate = nil
        view.releaseAllKeys()
        window.orderOut(nil)
        window.close()
    }

    private func applyTitle() {
        guard !info.isPopup else { return }
        window.title = info.title.isEmpty ? (info.app.isEmpty ? "Linux" : info.app) : info.title
    }


    func windowShouldClose(_ sender: NSWindow) -> Bool {
        session?.send(.close, ["id": id])
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        session?.didFocus(id)
    }

    func windowDidResignKey(_ notification: Notification) {
        view.releaseAllKeys()
    }

    func windowDidResize(_ notification: Notification) {
        guard !info.isPopup else { return }
        let size = window.contentLayoutRect.size
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width != info.w || height != info.h else { return }

        pendingResize?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.session?.send(.resize, ["id": self.id, "w": width, "h": height])
        }
        pendingResize = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
}

final class SeamlessView: NSView, NSTextInputClient, NSDraggingSource {
    let windowID: UInt32
    weak var session: SeamlessSession?
    private var pressedKeys = Set<UInt8>()
    private var scrollRemainder = CGPoint.zero
    private var trackingArea: NSTrackingArea?

    private enum DragOut {
        case idle
        case waiting
        case ready([SeamlessSession.DraggedFile])
        case started
        case declined
    }
    private var leftButtonDown = false
    private var dragOut = DragOut.idle
    private let promiseWriter = FilePromiseWriter()

    private var markedText = ""
    private lazy var markedPanel = MarkedTextPanel()

    private static let nonTextKeys: Set<UInt16> = [
        0x24, 0x4C, 0x30, 0x33, 0x35, 0x75, 0x72, 0x73, 0x77, 0x74, 0x79, 0x7B, 0x7C, 0x7D, 0x7E,
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A,
        0x40, 0x4F, 0x50, 0x5A, 0x47, 0x4A, 0x49, 0x48,
    ]

    @MainActor
    init(windowID: UInt32, session: SeamlessSession) {
        self.windowID = windowID
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .topLeft
        layer?.magnificationFilter = .nearest
        if session.supports("drop", window: windowID) {
            registerForDraggedTypes([.fileURL])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func show(_ image: CGImage, scale: CGFloat) {
        if let layer {
            let gravity: CALayerContentsGravity = layer.contentsAreFlipped() ? .bottomLeft : .topLeft
            if layer.contentsGravity != gravity { layer.contentsGravity = gravity }
        }
        layer?.contentsScale = scale
        layer?.contents = image
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }


    @MainActor
    private func send(_ type: SeamlessMessage, _ object: [String: Any]) {
        session?.send(type, object)
    }

    @MainActor
    private var scale: CGFloat { session?.scale ?? 1 }

    @MainActor
    private func guestPoint(_ locationInWindow: NSPoint) -> (Int, Int) {
        let point = convert(locationInWindow, from: nil)
        return (Int((point.x * scale).rounded(.down)), Int((point.y * scale).rounded(.down)))
    }

    @MainActor
    private func pointer(_ event: NSEvent) {
        let (x, y) = guestPoint(event.locationInWindow)
        send(.pointer, ["id": windowID, "x": x, "y": y])
    }

    @MainActor
    private func button(_ event: NSEvent, _ number: Int, _ pressed: Bool) {
        let (x, y) = guestPoint(event.locationInWindow)
        send(.button, ["id": windowID, "x": x, "y": y, "button": number, "pressed": pressed])
    }


    override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { pointer(event) } }

    override func mouseDragged(with event: NSEvent) {
        MainActor.assumeIsolated {
            let point = convert(event.locationInWindow, from: nil)
            guard leftButtonDown, !bounds.contains(point), session?.supports("dragout", window: windowID) == true else {
                pointer(event)
                return
            }
            switch dragOut {
            case .idle:
                dragOut = .waiting
                session?.requestDragOut(from: windowID) { [weak self] files in
                    guard let self, case .waiting = self.dragOut else { return }
                    self.dragOut = files.isEmpty ? .declined : .ready(files)
                }
            case .waiting, .started:
                break
            case .ready(let files):
                dragOut = .started
                beginFileDrag(files, event: event)
            case .declined:
                pointer(event)
            }
        }
    }
    override func rightMouseDragged(with event: NSEvent) { MainActor.assumeIsolated { pointer(event) } }
    override func otherMouseDragged(with event: NSEvent) { MainActor.assumeIsolated { pointer(event) } }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let number = event.modifierFlags.contains(.control) ? 3 : 1
        leftButtonDown = number == 1
        dragOut = .idle
        MainActor.assumeIsolated { button(event, number, true) }
    }

    override func mouseUp(with event: NSEvent) {
        leftButtonDown = false
        dragOut = .idle
        let number = event.modifierFlags.contains(.control) ? 3 : 1
        MainActor.assumeIsolated { button(event, number, false) }
    }

    override func rightMouseDown(with event: NSEvent) { MainActor.assumeIsolated { button(event, 3, true) } }
    override func rightMouseUp(with event: NSEvent) { MainActor.assumeIsolated { button(event, 3, false) } }
    override func otherMouseDown(with event: NSEvent) { MainActor.assumeIsolated { button(event, 2, true) } }
    override func otherMouseUp(with event: NSEvent) { MainActor.assumeIsolated { button(event, 2, false) } }

    override func scrollWheel(with event: NSEvent) {
        let divisor: CGFloat = event.hasPreciseScrollingDeltas ? 12 : 1
        scrollRemainder.x += event.scrollingDeltaX / divisor
        scrollRemainder.y += event.scrollingDeltaY / divisor
        let stepsX = Int(scrollRemainder.x.rounded(.towardZero))
        let stepsY = Int(scrollRemainder.y.rounded(.towardZero))
        guard stepsX != 0 || stepsY != 0 else { return }
        scrollRemainder.x -= CGFloat(stepsX)
        scrollRemainder.y -= CGFloat(stepsY)
        MainActor.assumeIsolated {
            let (x, y) = guestPoint(event.locationInWindow)
            send(.scroll, ["id": windowID, "x": x, "y": y, "dx": -stepsX, "dy": -stepsY])
        }
    }


    @MainActor
    private func key(_ code: UInt8, _ pressed: Bool) {
        if pressed { pressedKeys.insert(code) } else { pressedKeys.remove(code) }
        send(.key, ["id": windowID, "keycode": Int(code), "pressed": pressed])
    }

    @MainActor
    private var usesMacTextInput: Bool { session?.usesMacTextInput ?? false }

    override func keyDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            let shortcut = !event.modifierFlags.intersection([.command, .control]).isEmpty
            if usesMacTextInput && !markedText.isEmpty && !event.modifierFlags.contains(.command) {
                interpretKeyEvents([event])
                return
            }
            if usesMacTextInput && !shortcut && !Self.nonTextKeys.contains(event.keyCode) {
                interpretKeyEvents([event])
                return
            }
            guard !event.isARepeat, let code = KeyMap.x11Keycode(forMacKeyCode: event.keyCode) else { return }
            key(code, true)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let code = KeyMap.x11Keycode(forMacKeyCode: event.keyCode) else { return }
        MainActor.assumeIsolated {
            if pressedKeys.contains(code) { key(code, false) }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard let code = KeyMap.x11Keycode(forMacKeyCode: event.keyCode),
              let flag = KeyMap.modifierFlag(forMacKeyCode: event.keyCode) else { return }
        MainActor.assumeIsolated {
            let flags = event.modifierFlags
            let pressed: Bool
            switch flag {
            case .shift: pressed = flags.contains(.shift)
            case .control: pressed = flags.contains(.control)
            case .command: pressed = flags.contains(.command)
            case .option:
                if usesMacTextInput { return }
                pressed = flags.contains(.option)
            case .capsLock:
                if usesMacTextInput { return }
                key(code, true)
                key(code, false)
                return
            }
            if pressed == pressedKeys.contains(code) { return }
            key(code, pressed)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command),
              window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let reserved: Set<UInt16> = [0x0C, 0x04, 0x32, 0x2B]
        guard !reserved.contains(event.keyCode), let code = KeyMap.x11Keycode(forMacKeyCode: event.keyCode) else {
            return super.performKeyEquivalent(with: event)
        }
        MainActor.assumeIsolated {
            key(code, true)
            key(code, false)
        }
        return true
    }

    func releaseAllKeys() {
        MainActor.assumeIsolated {
            for code in pressedKeys {
                send(.key, ["id": windowID, "keycode": Int(code), "pressed": false])
            }
            pressedKeys.removeAll()
        }
    }


    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        MainActor.assumeIsolated {
            clearMarkedText()
            guard !text.isEmpty else { return }
            send(.text, ["id": windowID, "text": text])
        }
    }

    override func doCommand(by selector: Selector) {}

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        MainActor.assumeIsolated {
            markedText = text
            if text.isEmpty {
                clearMarkedText()
            } else if session?.textInputCursor(for: windowID) != nil {
                markedPanel.hide()
                send(.preedit, ["id": windowID, "text": text, "cursor": selectedRange.location])
            } else if let window {
                markedPanel.show(text, selectedRange: selectedRange, at: firstRect(forCharacterRange: NSRange(), actualRange: nil), parent: window)
            }
        }
    }

    func unmarkText() {
        MainActor.assumeIsolated { clearMarkedText() }
    }

    @MainActor
    private func clearMarkedText() {
        if !markedText.isEmpty, session?.textInputCursor(for: windowID) != nil {
            send(.preedit, ["id": windowID, "text": "", "cursor": -1])
        }
        markedText = ""
        markedPanel.hide()
    }

    func selectedRange() -> NSRange {
        NSRange(location: (markedText as NSString).length, length: 0)
    }

    func markedRange() -> NSRange {
        markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: (markedText as NSString).length)
    }

    func hasMarkedText() -> Bool { !markedText.isEmpty }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let cursor = MainActor.assumeIsolated { session?.textInputCursor(for: windowID) }
        if let cursor {
            let s = MainActor.assumeIsolated { scale }
            let rect = NSRect(x: cursor.minX / s, y: cursor.minY / s, width: max(cursor.width / s, 1), height: max(cursor.height / s, 1))
            return window.convertToScreen(convert(rect, to: nil))
        }
        return window.convertToScreen(convert(NSRect(x: 0, y: bounds.height - 20, width: 1, height: 20), to: nil))
    }


    @MainActor
    private func beginFileDrag(_ files: [SeamlessSession.DraggedFile], event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let items: [NSDraggingItem] = files.enumerated().map { index, file in
            let type = UTType(filenameExtension: (file.name as NSString).pathExtension) ?? .data
            let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: promiseWriter)
            provider.userInfo = file
            let item = NSDraggingItem(pasteboardWriter: provider)
            let offset = CGFloat(index) * 6
            item.setDraggingFrame(NSRect(x: point.x - 24 + offset, y: point.y - 24 + offset, width: 48, height: 48),
                                  contents: NSWorkspace.shared.icon(for: type))
            return item
        }
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }


    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        return MainActor.assumeIsolated {
            let point = convert(sender.draggingLocation, from: nil)
            session?.drop(files: urls, on: windowID, at: CGPoint(x: point.x * scale, y: point.y * scale))
            return true
        }
    }
}

final class FilePromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? SeamlessSession.DraggedFile)?.name ?? "Linux file"
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let file = filePromiseProvider.userInfo as? SeamlessSession.DraggedFile else {
            completionHandler(LinMOError.message("ไม่พบข้อมูลไฟล์"))
            return
        }
        do {
            try file.data.write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }
}

@MainActor
final class MarkedTextPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        label.font = .systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
    }

    func show(_ text: String, selectedRange: NSRange, at rect: NSRect, parent: NSWindow) {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 15),
        ])
        let length = (text as NSString).length
        if selectedRange.location != NSNotFound, selectedRange.length > 0, NSMaxRange(selectedRange) <= length {
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: selectedRange)
        }
        label.attributedStringValue = attributed
        let size = NSSize(width: max(40, label.intrinsicContentSize.width + 16), height: 28)
        panel.setFrame(NSRect(x: rect.minX, y: rect.minY, width: size.width, height: size.height), display: true)
        if panel.parent == nil {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}
