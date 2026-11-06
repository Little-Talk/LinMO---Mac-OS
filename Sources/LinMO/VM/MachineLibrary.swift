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

    var canSuspendAllRunning: Bool {
        machines.contains { $0.state == .running } && machines.allSatisfy { $0.state == .stopped || ($0.state == .running && $0.canSuspend) }
    }

    func suspendAll(completion: @escaping () -> Void) {
        let running = machines.filter { $0.state == .running }
        guard !running.isEmpty else { completion(); return }
        var remaining = running.count
        for machine in running {
            machine.suspend {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
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

    @discardableResult
    func duplicate(_ controller: MachineController) -> MachineController? {
        guard controller.state == .stopped, !controller.isSuspended else { return nil }
        var config = controller.config
        config.id = UUID()
        config.name = controller.config.name + tr(" (สำเนา)", " (copy)")
        config.createdAt = Date()
        config.sshPort = nil
        do {
            let bundle = try controller.bundle.clone(as: config)
            let copy = MachineController(bundle: bundle, config: config)
            machines.append(copy)
            return copy
        } catch {
            errorMessage = tr("ทำสำเนาเครื่องไม่สำเร็จ: \(error.localizedDescription)", "Could not duplicate the machine: \(error.localizedDescription)")
            return nil
        }
    }

    func delete(_ controller: MachineController) {
        guard !controller.isRunning else { return }
        do {
            try controller.bundle.delete()
            machines.removeAll { $0.id == controller.id }
            LinuxAppCatalog.shared.removeMachine(controller.id)
        } catch {
            errorMessage = tr("ลบเครื่องไม่สำเร็จ: \(error.localizedDescription)", "Could not delete the machine: \(error.localizedDescription)")
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
            errorMessage = tr("ย้ายเครื่องจากเวอร์ชันเก่าไม่สำเร็จ: \(error.localizedDescription)", "Could not migrate machines from the old version: \(error.localizedDescription)")
        }
    }
}
