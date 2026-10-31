import Foundation

enum ProvisioningPhase: Equatable, Sendable {
    case preparing
    case installingRosetta
    case downloading(Double)
    case verifying
    case extracting
    case creatingMachine
    case finished
    case failed(String)

    var title: String {
        switch self {
        case .preparing: return "กำลังเตรียม…"
        case .installingRosetta: return "กำลังติดตั้ง Rosetta…"
        case .downloading(let f): return "กำลังดาวน์โหลด Linux… \(Int(f * 100))%"
        case .verifying: return "กำลังตรวจสอบไฟล์…"
        case .extracting: return "กำลังแตกไฟล์…"
        case .creatingMachine: return "กำลังสร้างเครื่อง…"
        case .finished: return "เสร็จแล้ว"
        case .failed(let message): return message
        }
    }

    var fraction: Double? {
        if case .downloading(let f) = self { return f }
        return nil
    }
}

@MainActor
final class Provisioner: ObservableObject {
    @Published private(set) var phase: ProvisioningPhase = .preparing
    @Published private(set) var createdMachine: MachineController?
    private var acceptsImagePhases = false

    func run(distro: Distro, config: MachineConfig, options: GuestSetupOptions, library: MachineLibrary) async {
        phase = .preparing
        do {
            var config = config
            config.distroID = distro.id
            config.attachCloudInitSeed = true

            if options.rosetta {
                if RosettaSupport.availability == .notInstalled {
                    phase = .installingRosetta
                    try await RosettaSupport.install()
                }
                config.rosettaEnabled = RosettaSupport.availability == .installed
            }

            acceptsImagePhases = true
            let disk = try await ImageStore.prepareDisk(for: distro) { [weak self] newPhase in
                Task { @MainActor in
                    guard let self, self.acceptsImagePhases else { return }
                    self.phase = newPhase
                }
            }
            acceptsImagePhases = false

            phase = .creatingMachine
            var guestOptions = options
            guestOptions.rosetta = config.rosettaEnabled
            let machineConfig = config
            let bundle = try await Task.detached(priority: .userInitiated) {
                let bundle = try MachineBundle.create(config: machineConfig, diskSource: disk)
                do {
                    try CloudInit.makeSeedImage(
                        at: bundle.cloudInitSeedURL,
                        userData: CloudInit.userData(for: distro, options: guestOptions),
                        metaData: CloudInit.metaData(instanceID: machineConfig.id, hostname: guestOptions.hostname)
                    )
                } catch {
                    try? bundle.delete()
                    throw error
                }
                return bundle
            }.value

            let controller = MachineController(bundle: bundle, config: config)
            library.add(controller)
            createdMachine = controller
            phase = .finished
        } catch {
            acceptsImagePhases = false
            phase = .failed("สร้างเครื่องไม่สำเร็จ: \(error.localizedDescription)")
        }
    }
}
