import AppKit
import CoreSpotlight
import SwiftUI

@main
struct LinMOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = MachineLibrary.shared
    @AppStorage(LinuxAppCatalog.Keys.menuBar) private var showsLinuxAppsMenu = true

    var body: some Scene {
        Window("LinMO", id: "main") {
            ContentView()
                .environmentObject(library)
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra("แอพ Linux", systemImage: "square.grid.2x2", isInserted: $showsLinuxAppsMenu) {
            LinuxAppsMenu()
                .environmentObject(library)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            LinuxAppCatalog.shared.refreshSpotlight()
            LinuxAppCatalog.shared.refreshLaunchpad()
        }
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { LinuxAppLauncher.open($0) }
    }

    @MainActor
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let url = URL(string: identifier) else { return false }
        return LinuxAppLauncher.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MachineLibrary.shared.hasRunningMachines else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "ยังมีเครื่อง Linux ทำงานอยู่"
        alert.informativeText = "ถ้าปิดแอพตอนนี้ เครื่องจะถูกตัดไฟทันที ข้อมูลที่ยังไม่บันทึกอาจหาย ควรปิดเครื่องใน Linux ก่อน"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "ยกเลิก")
        alert.addButton(withTitle: "ปิดแอพเลย")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
