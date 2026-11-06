import AppKit
import CoreSpotlight
import SwiftUI

@main
struct LinMOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = MachineLibrary.shared
    @StateObject private var menuBarSetting = MenuBarSetting.shared

    var body: some Scene {
        Window("LinMO", id: "main") {
            ContentView()
                .environmentObject(library)
        }
        .commands {
            UserGuideCommands()
        }

        Window(tr("คู่มือ LinMO", "LinMO Guide"), id: "guide") {
            UserGuideView()
        }
        .defaultSize(width: 920, height: 640)

        Settings {
            SettingsView()
        }

        MenuBarExtra(tr("แอพ Linux", "Linux Apps"), systemImage: "square.grid.2x2", isInserted: menuBarSetting.binding) {
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
        let library = MachineLibrary.shared
        guard library.hasRunningMachines else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = tr("ยังมีเครื่อง Linux ทำงานอยู่", "A Linux machine is still running")
        if library.canSuspendAllRunning {
            alert.informativeText = tr("พักเครื่องไว้ก่อนได้ เปิดครั้งหน้าจะกลับมาที่เดิมทันที ทั้งแอพและไฟล์ที่เปิดค้างไว้", "You can suspend it first. Next time it picks up right where you left off, with the same apps and files open.")
            alert.addButton(withTitle: tr("พักเครื่องแล้วปิดแอพ", "Suspend and Quit"))
            alert.addButton(withTitle: tr("ยกเลิก", "Cancel"))
            alert.addButton(withTitle: tr("ปิดแอพเลย", "Quit Anyway"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                library.suspendAll {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
                return .terminateLater
            case .alertThirdButtonReturn:
                return .terminateNow
            default:
                return .terminateCancel
            }
        }
        alert.informativeText = tr("ถ้าปิดแอพตอนนี้ เครื่องจะถูกตัดไฟทันที ข้อมูลที่ยังไม่บันทึกอาจหาย ควรปิดเครื่องใน Linux ก่อน", "Quitting now cuts power to the machine immediately and unsaved work may be lost. Shut down Linux first.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: tr("ยกเลิก", "Cancel"))
        alert.addButton(withTitle: tr("ปิดแอพเลย", "Quit Anyway"))
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
