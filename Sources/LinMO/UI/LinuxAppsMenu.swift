import AppKit
import SwiftUI

struct LinuxAppsMenu: View {
    @ObservedObject private var catalog = LinuxAppCatalog.shared
    @EnvironmentObject private var library: MachineLibrary
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let machines = library.machines.filter { !catalog.apps(for: $0.id).isEmpty }
        if machines.isEmpty {
            Text("ยังไม่มีรายการแอพ")
            Text("เปิดเครื่อง Linux ที่ติดตั้ง LinMO Agent แล้วหนึ่งครั้ง")
        } else {
            ForEach(machines) { machine in
                MachineAppsSection(machine: machine, apps: catalog.apps(for: machine.id))
            }
        }
        Divider()
        Button("เปิด LinMO") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink {
            Text("ตั้งค่า…")
        }
    }
}

private struct MachineAppsSection: View {
    @ObservedObject var machine: MachineController
    let apps: [LinuxApp]

    var body: some View {
        Section(machine.config.name + (machine.isRunning ? "" : " (ปิดอยู่)")) {
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

struct LinuxAppsSettingsSection: View {
    @AppStorage(LinuxAppCatalog.Keys.menuBar) private var menuBar = true
    @AppStorage(LinuxAppCatalog.Keys.spotlight) private var spotlight = true
    @AppStorage(LinuxAppCatalog.Keys.launchpad) private var launchpad = false
    @ObservedObject private var catalog = LinuxAppCatalog.shared

    var body: some View {
        Section {
            Toggle("แสดงเมนู \"แอพ Linux\" บนแถบเมนู", isOn: $menuBar)
            Toggle("ค้นหาแอพ Linux ใน Spotlight", isOn: $spotlight)
                .onChange(of: spotlight) { catalog.refreshSpotlight() }
            if LaunchpadShortcuts.isAvailable {
                Toggle("ใส่แอพ Linux ใน Launchpad", isOn: $launchpad)
                    .onChange(of: launchpad) { catalog.refreshLaunchpad() }
                if launchpad {
                    Button("แสดงทางลัดใน Finder") {
                        NSWorkspace.shared.open(LaunchpadShortcuts.folder)
                    }
                }
            }
        } header: {
            Text("แอพ Linux บน Mac")
        } footer: {
            Text(LaunchpadShortcuts.isAvailable
                 ? "รู้จักแอพ \(catalog.apps.count) ตัว (อัปเดตทุกครั้งที่เปิดเครื่อง) — ทางลัดใน Launchpad อยู่ที่ ~/Applications/แอพ Linux (LinMO) เลือกแอพแล้ว LinMO จะเปิดเครื่องให้เองถ้ายังปิดอยู่"
                 : "รู้จักแอพ \(catalog.apps.count) ตัว (อัปเดตทุกครั้งที่เปิดเครื่อง) — เลือกแอพแล้ว LinMO จะเปิดเครื่องให้เองถ้ายังปิดอยู่")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
