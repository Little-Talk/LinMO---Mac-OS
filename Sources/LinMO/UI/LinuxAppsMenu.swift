import AppKit
import SwiftUI

struct LinuxAppsMenu: View {
    @ObservedObject private var catalog = LinuxAppCatalog.shared
    @EnvironmentObject private var library: MachineLibrary
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue

    var body: some View {
        let machines = library.machines.filter { !catalog.apps(for: $0.id).isEmpty }
        if machines.isEmpty {
            Text(tr("ยังไม่มีรายการแอพ", "No apps yet"))
            Text(tr("เปิดเครื่อง Linux ที่ติดตั้ง LinMO Agent แล้วหนึ่งครั้ง", "Start a Linux machine with LinMO Agent installed once"))
        } else {
            ForEach(machines) { machine in
                MachineAppsSection(machine: machine, apps: catalog.apps(for: machine.id))
            }
        }
        Divider()
        Button(tr("เปิด LinMO", "Open LinMO")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink {
            Text(tr("ตั้งค่า…", "Settings…"))
        }
    }
}

private struct MachineAppsSection: View {
    @ObservedObject var machine: MachineController
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
    let apps: [LinuxApp]

    var body: some View {
        Section(machine.config.name + (machine.isRunning ? "" : tr(" (ปิดอยู่)", " (stopped)"))) {
            let groups = Dictionary(grouping: apps, by: \.mainCategory)
            ForEach(groups.keys.sorted { LinuxApp.categoryTitle($0) < LinuxApp.categoryTitle($1) }, id: \.self) { category in
                Menu(LinuxApp.categoryTitle(category)) {
                    ForEach(groups[category]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { app in
                        Button {
                            LinuxAppLauncher.open(app)
                        } label: {
                            if let icon = app.icon {
                                Label { Text(app.name) } icon: { Image(nsImage: Self.menuIcon(icon)) }
                            } else {
                                Text(app.name)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func menuIcon(_ image: NSImage) -> NSImage {
        let resized = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        return resized
    }
}

@MainActor
final class MenuBarSetting: ObservableObject {
    static let shared = MenuBarSetting()

    @Published private(set) var isInserted: Bool

    private init() {
        UserDefaults.standard.register(defaults: [LinuxAppCatalog.Keys.menuBar: true])
        isInserted = UserDefaults.standard.bool(forKey: LinuxAppCatalog.Keys.menuBar)
    }

    func set(_ value: Bool) {
        guard value != isInserted else { return }
        isInserted = value
        UserDefaults.standard.set(value, forKey: LinuxAppCatalog.Keys.menuBar)
    }

    var binding: Binding<Bool> {
        Binding(get: { self.isInserted }, set: { self.set($0) })
    }
}

struct LinuxAppsSettingsSection: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
    @ObservedObject private var menuBar = MenuBarSetting.shared
    @AppStorage(LinuxAppCatalog.Keys.spotlight) private var spotlight = true
    @AppStorage(LinuxAppCatalog.Keys.launchpad) private var launchpad = false
    @ObservedObject private var catalog = LinuxAppCatalog.shared

    var body: some View {
        Section {
            Toggle(tr("แสดงเมนู \"แอพ Linux\" บนแถบเมนู", "Show the \"Linux Apps\" menu in the menu bar"), isOn: menuBar.binding)
            Toggle(tr("ค้นหาแอพ Linux ใน Spotlight", "Find Linux apps in Spotlight"), isOn: $spotlight)
                .onChange(of: spotlight) { catalog.refreshSpotlight() }
            if LaunchpadShortcuts.isAvailable {
                Toggle(tr("ใส่แอพ Linux ใน Launchpad", "Add Linux apps to Launchpad"), isOn: $launchpad)
                    .onChange(of: launchpad) { catalog.refreshLaunchpad() }
                if launchpad {
                    Button(tr("แสดงทางลัดใน Finder", "Show Shortcuts in Finder")) {
                        NSWorkspace.shared.open(LaunchpadShortcuts.folder)
                    }
                }
            }
        } header: {
            Text(tr("แอพ Linux บน Mac", "Linux apps on your Mac"))
        } footer: {
            Text(LaunchpadShortcuts.isAvailable
                 ? tr("รู้จักแอพ \(catalog.apps.count) ตัว (อัปเดตทุกครั้งที่เปิดเครื่อง) — ทางลัดใน Launchpad อยู่ที่ ~/Applications/แอพ Linux (LinMO) เลือกแอพแล้ว LinMO จะเปิดเครื่องให้เองถ้ายังปิดอยู่", "\(catalog.apps.count) apps found (updated every time a machine starts). Launchpad shortcuts are in ~/Applications/แอพ Linux (LinMO). Pick an app and LinMO starts its machine if it is off.")
                 : tr("รู้จักแอพ \(catalog.apps.count) ตัว (อัปเดตทุกครั้งที่เปิดเครื่อง) — เลือกแอพแล้ว LinMO จะเปิดเครื่องให้เองถ้ายังปิดอยู่", "\(catalog.apps.count) apps found (updated every time a machine starts). Pick an app and LinMO starts its machine if it is off."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
