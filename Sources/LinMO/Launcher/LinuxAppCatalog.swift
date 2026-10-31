import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

struct LinuxApp: Codable, Identifiable, Hashable {
    let machineID: UUID
    var machineName: String
    let appID: String
    var name: String
    var generic: String?
    var categories: [String]
    var iconPNG: Data?

    var id: String { "\(machineID.uuidString)/\(appID)" }

    static let scheme = "linmo"

    var launchURL: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "launch"
        components.queryItems = [
            URLQueryItem(name: "machine", value: machineID.uuidString),
            URLQueryItem(name: "app", value: appID),
        ]
        return components.url!
    }

    var mainCategory: String {
        let order = ["Development", "Network", "Office", "Graphics", "AudioVideo", "Education", "Game",
                     "Science", "Utility", "Settings", "System"]
        return order.first { categories.contains($0) } ?? "Other"
    }

    static func categoryTitle(_ category: String) -> String {
        switch category {
        case "Development": return "พัฒนาโปรแกรม"
        case "Network": return "อินเทอร์เน็ต"
        case "Office": return "งานเอกสาร"
        case "Graphics": return "กราฟิก"
        case "AudioVideo": return "เสียงและวิดีโอ"
        case "Education": return "การศึกษา"
        case "Game": return "เกม"
        case "Science": return "วิทยาศาสตร์"
        case "Utility": return "เครื่องมือ"
        case "Settings": return "ตั้งค่า"
        case "System": return "ระบบ"
        default: return "อื่นๆ"
        }
    }

    var icon: NSImage? { iconPNG.flatMap(NSImage.init(data:)) }
}

@MainActor
final class LinuxAppCatalog: ObservableObject {
    static let shared = LinuxAppCatalog()

    enum Keys {
        static let menuBar = "linuxApps.menuBar"
        static let spotlight = "linuxApps.spotlight"
        static let launchpad = "linuxApps.launchpad"
    }

    @Published private(set) var apps: [LinuxApp] = []

    nonisolated private static let spotlightDomain = "io.github.jeerapatsepu.LinMO.linux-apps"

    private var fileURL: URL {
        MachineBundle.appSupportDirectory.appendingPathComponent("LinuxApps.json")
    }

    private init() {
        UserDefaults.standard.register(defaults: [Keys.menuBar: true, Keys.spotlight: true, Keys.launchpad: false])
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([LinuxApp].self, from: data) {
            apps = saved
        }
    }

    var spotlightEnabled: Bool { UserDefaults.standard.bool(forKey: Keys.spotlight) }
    var launchpadEnabled: Bool { UserDefaults.standard.bool(forKey: Keys.launchpad) && LaunchpadShortcuts.isAvailable }

    func apps(for machine: UUID) -> [LinuxApp] {
        apps.filter { $0.machineID == machine }
    }


    func update(machine: UUID, machineName: String, apps sessionApps: [SeamlessSession.App]) {
        guard !sessionApps.isEmpty else { return }
        let fresh = sessionApps.map { app in
            LinuxApp(machineID: machine, machineName: machineName, appID: app.id, name: app.name,
                     generic: app.generic, categories: app.categories ?? [],
                     iconPNG: IconRaster.png(base64: app.icon, format: app.iconFormat))
        }
        guard fresh != apps(for: machine) else { return }
        apps = apps.filter { $0.machineID != machine } + fresh
        didChange()
    }

    func renameMachine(_ machine: UUID, to name: String) {
        guard apps.contains(where: { $0.machineID == machine }) else { return }
        apps = apps.map { app in
            guard app.machineID == machine else { return app }
            var copy = app
            copy.machineName = name
            return copy
        }
        didChange()
    }

    func removeMachine(_ machine: UUID) {
        guard apps.contains(where: { $0.machineID == machine }) else { return }
        apps.removeAll { $0.machineID == machine }
        didChange()
    }

    private func didChange() {
        save()
        refreshSpotlight()
        refreshLaunchpad()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: MachineBundle.appSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(apps).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("LinMO: cannot save Linux app list: \(error)")
        }
    }


    func refreshSpotlight() {
        let index = CSSearchableIndex.default()
        let items: [CSSearchableItem] = spotlightEnabled ? apps.map(Self.searchableItem) : []
        index.deleteSearchableItems(withDomainIdentifiers: [Self.spotlightDomain]) { error in
            if let error { NSLog("LinMO: Spotlight delete failed: \(error)") }
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { error in
                if let error { NSLog("LinMO: Spotlight index failed: \(error)") }
            }
        }
    }

    nonisolated private static func searchableItem(_ app: LinuxApp) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .application)
        attributes.title = app.name
        attributes.displayName = app.name
        var description = "แอพ Linux บนเครื่อง \(app.machineName)"
        if let generic = app.generic, !generic.isEmpty { description = "\(generic) — \(description)" }
        attributes.contentDescription = description
        attributes.thumbnailData = app.iconPNG
        attributes.keywords = [app.name, app.appID, app.machineName, "Linux", "LinMO"] + app.categories
        return CSSearchableItem(uniqueIdentifier: app.launchURL.absoluteString, domainIdentifier: spotlightDomain, attributeSet: attributes)
    }


    func refreshLaunchpad() {
        guard LaunchpadShortcuts.isAvailable else { return }
        let apps = launchpadEnabled ? self.apps : []
        Task.detached(priority: .utility) {
            LaunchpadShortcuts.sync(apps)
        }
    }
}

enum IconRaster {
    static func png(base64: String?, format: String?, size: CGFloat = 256) -> Data? {
        guard let base64, let data = Data(base64Encoded: base64) else { return nil }
        if format != "svg", NSBitmapImageRep(data: data) != nil { return data }
        guard let image = NSImage(data: data), image.isValid else { return nil }
        return render(image, size: size).flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    static func render(_ image: NSImage, size: CGFloat, inset: CGFloat = 0) -> CGImage? {
        let pixels = Int(size)
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let box = size * (1 - inset * 2)
        let aspect = image.size.width / max(image.size.height, 1)
        let drawSize = aspect >= 1 ? CGSize(width: box, height: box / aspect) : CGSize(width: box * aspect, height: box)
        let rect = CGRect(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2,
                          width: drawSize.width, height: drawSize.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
