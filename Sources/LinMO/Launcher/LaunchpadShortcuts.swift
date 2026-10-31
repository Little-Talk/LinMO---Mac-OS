import AppKit
import CoreServices
import UniformTypeIdentifiers

enum LaunchpadShortcuts {
    static var isAvailable: Bool { !AppEnvironment.isSandboxed }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("แอพ Linux (LinMO)", isDirectory: true)
    }

    private static let markerKey = "LinMOLaunchURL"

    static func sync(_ apps: [LinuxApp]) {
        let fm = FileManager.default
        let machineCount = Set(apps.map(\.machineID)).count
        var wanted: [String: LinuxApp] = [:]
        for app in apps {
            var name = machineCount > 1 ? "\(app.name) (\(app.machineName))" : app.name
            name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            if wanted[name] != nil { name += " — \(app.appID)" }
            wanted[name + ".app"] = app
        }

        let existing = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in existing where url.pathExtension == "app" {
            let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            guard let launch = info?[markerKey] as? String else { continue }
            if wanted[url.lastPathComponent]?.launchURL.absoluteString != launch {
                try? fm.removeItem(at: url)
            }
        }

        if wanted.isEmpty {
            if (try? fm.contentsOfDirectory(atPath: folder.path))?.filter({ !$0.hasPrefix(".") }).isEmpty == true {
                try? fm.removeItem(at: folder)
            }
            return
        }

        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSLog("LinMO: cannot create \(folder.path): \(error)")
            return
        }
        for (fileName, app) in wanted {
            let url = folder.appendingPathComponent(fileName, isDirectory: true)
            let iconURL = url.appendingPathComponent("Contents/Resources/AppIcon.icns")
            if fm.fileExists(atPath: url.path), (try? Data(contentsOf: url.appendingPathComponent("Contents/Resources/icon.png"))) == app.iconPNG {
                continue
            }
            do {
                try? fm.removeItem(at: url)
                try create(app, at: url, iconURL: iconURL)
                _ = LSRegisterURL(url as CFURL, true)
            } catch {
                NSLog("LinMO: cannot create shortcut \(url.path): \(error)")
            }
        }
    }

    private static func create(_ app: LinuxApp, at url: URL, iconURL: URL) throws {
        let fm = FileManager.default
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let hostBundleID = Bundle.main.bundleIdentifier ?? "io.github.jeerapatsepu.LinMO"
        let safeID = (app.machineID.uuidString.prefix(8) + "." + app.appID)
            .map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? String($0) : "-" }
            .joined()
        let info: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleIdentifier": "\(hostBundleID).shortcut.\(safeID)",
            "CFBundleName": app.name,
            "CFBundleDisplayName": app.name,
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
            markerKey: app.launchURL.absoluteString,
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let script = """
        #!/bin/sh
        exec /usr/bin/open -b '\(hostBundleID)' '\(app.launchURL.absoluteString)'

        """
        let executable = macOS.appendingPathComponent("launch")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        if let png = app.iconPNG {
            try png.write(to: resources.appendingPathComponent("icon.png"))
        }
        writeICNS(for: app, to: iconURL)
    }

    private static func writeICNS(for app: LinuxApp, to url: URL) {
        let image = app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
        let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.icns.identifier as CFString, sizes.count, nil) else {
            return
        }
        for size in sizes {
            if let cgImage = IconRaster.render(image, size: size, inset: 0.1) {
                CGImageDestinationAddImage(destination, cgImage, nil)
            }
        }
        CGImageDestinationFinalize(destination)
    }
}

@MainActor
enum LinuxAppLauncher {
    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard url.scheme == LinuxApp.scheme, url.host == "launch",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let machineID = items.first(where: { $0.name == "machine" })?.value.flatMap(UUID.init(uuidString:)),
              let appID = items.first(where: { $0.name == "app" })?.value, !appID.isEmpty else { return false }
        guard let machine = MachineLibrary.shared.machines.first(where: { $0.id == machineID }) else {
            MachineLibrary.shared.errorMessage = "ไม่พบเครื่อง Linux ของแอพนี้ (อาจถูกลบไปแล้ว)"
            return false
        }
        NSApp.activate(ignoringOtherApps: true)
        machine.launchLinuxApp(appID)
        return true
    }

    static func open(_ app: LinuxApp) {
        open(app.launchURL)
    }
}
