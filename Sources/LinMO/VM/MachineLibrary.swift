import Foundation

@MainActor
final class MachineLibrary: ObservableObject {
    static let shared = MachineLibrary()

    @Published private(set) var machines: [MachineController] = []
    @Published var errorMessage: String?

    private init() {
        migrateLegacyMachineIfNeeded()
        load()
    }

    var hasRunningMachines: Bool {
        machines.contains { $0.isRunning }
    }

    func load() {
        let fm = FileManager.default
        try? fm.createDirectory(at: MachineBundle.machinesDirectory, withIntermediateDirectories: true)
        let items = (try? fm.contentsOfDirectory(at: MachineBundle.machinesDirectory, includingPropertiesForKeys: nil)) ?? []

        let loaded: [MachineController] = items
            .filter { $0.pathExtension == "vmbundle" }
            .compactMap { url in
                let bundle = MachineBundle(url: url)
                guard let config = try? bundle.loadConfig() else { return nil }
                if let existing = machines.first(where: { $0.id == config.id }) {
                    return existing
                }
                return MachineController(bundle: bundle, config: config)
            }
        machines = loaded.sorted { $0.config.createdAt < $1.config.createdAt }
    }

    func add(_ controller: MachineController) {
        machines.append(controller)
    }

    func delete(_ controller: MachineController) {
        guard !controller.isRunning else { return }
        do {
            try controller.bundle.delete()
            machines.removeAll { $0.id == controller.id }
            LinuxAppCatalog.shared.removeMachine(controller.id)
        } catch {
            errorMessage = "ลบเครื่องไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    private func migrateLegacyMachineIfNeeded() {
        struct LegacySettings: Decodable {
            var cpuCount: Int?
            var memoryGB: Int?
            var diskGB: Int?
            var installerISOPath: String?
            var sharedFolderPath: String?
        }

        let fm = FileManager.default
        let legacyURL = MachineBundle.appSupportDirectory.appendingPathComponent("Default.vmbundle", isDirectory: true)
        let legacySettingsURL = legacyURL.appendingPathComponent("settings.json")
        guard fm.fileExists(atPath: legacySettingsURL.path) else { return }

        do {
            let legacy = try JSONDecoder().decode(LegacySettings.self, from: Data(contentsOf: legacySettingsURL))
            var config = MachineConfig(name: "Linux")
            config.cpuCount = legacy.cpuCount ?? config.cpuCount
            config.memoryGB = legacy.memoryGB ?? config.memoryGB
            config.diskGB = legacy.diskGB ?? config.diskGB
            config.installerISOPath = legacy.installerISOPath
            config.sharedFolderPath = legacy.sharedFolderPath

            try fm.createDirectory(at: MachineBundle.machinesDirectory, withIntermediateDirectories: true)
            let newURL = MachineBundle.url(for: config.id)
            try fm.moveItem(at: legacyURL, to: newURL)
            let bundle = MachineBundle(url: newURL)
            try bundle.save(config)
            try? fm.removeItem(at: newURL.appendingPathComponent("settings.json"))
        } catch {
            errorMessage = "ย้ายเครื่องจากเวอร์ชันเก่าไม่สำเร็จ: \(error.localizedDescription)"
        }
    }
}
