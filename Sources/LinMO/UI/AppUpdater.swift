import Combine
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false

    var isAvailable: Bool {
        #if canImport(Sparkle)
        return controller != nil
        #else
        return false
        #endif
    }

    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController?

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        guard !key.isEmpty, !feed.isEmpty else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
    #else
    private init() {}
    #endif

    var automaticallyChecks: Bool {
        get {
            #if canImport(Sparkle)
            return controller?.updater.automaticallyChecksForUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
            #endif
        }
    }

    var automaticallyDownloads: Bool {
        get {
            #if canImport(Sparkle)
            return controller?.updater.automaticallyDownloadsUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
            #endif
        }
    }

    var lastCheck: Date? {
        #if canImport(Sparkle)
        return controller?.updater.lastUpdateCheckDate
        #else
        return nil
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        controller?.checkForUpdates(nil)
        #endif
    }
}

struct AppUpdateCommands: Commands {
    @ObservedObject var updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if updater.isAvailable {
                Button("ตรวจหาอัปเดต LinMO…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}

struct AppUpdateSettingsSection: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        if updater.isAvailable {
            Section {
                Toggle("ตรวจหารุ่นใหม่อัตโนมัติ", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 }
                ))
                Toggle("ดาวน์โหลดและติดตั้งให้เอง", isOn: Binding(
                    get: { updater.automaticallyDownloads },
                    set: { updater.automaticallyDownloads = $0 }
                ))
                .disabled(!updater.automaticallyChecks)
                HStack {
                    if let last = updater.lastCheck {
                        Text("ตรวจล่าสุด \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("ตรวจหาอัปเดตตอนนี้") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            } header: {
                Text("อัปเดตแอพ LinMO")
            } footer: {
                Text("รุ่นปัจจุบัน \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-") ถ้าเปิดดาวน์โหลดให้เอง รุ่นใหม่จะติดตั้งตอนปิดแอพครั้งถัดไป")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
