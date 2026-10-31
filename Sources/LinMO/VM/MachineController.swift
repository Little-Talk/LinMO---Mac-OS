import AppKit
import Foundation
import Virtualization

@MainActor
final class MachineController: NSObject, ObservableObject, Identifiable {
    enum State: Equatable {
        case stopped, starting, running, stopping
    }

    let bundle: MachineBundle
    nonisolated let id: UUID

    @Published private(set) var config: MachineConfig
    @Published private(set) var state: State = .stopped
    @Published private(set) var virtualMachine: VZVirtualMachine?
    @Published private(set) var snapshots: [Snapshot] = []
    @Published private(set) var setupStatus: SetupStatus?
    @Published var errorMessage: String?

    private var setupListener: SetupProgressListener?
    private var displayView: VZVirtualMachineView?
    let seamless: SeamlessSession
    private var restartAfterSetup = false
    private let fileAccess = SecurityScopedAccess()

    init(bundle: MachineBundle, config: MachineConfig) {
        self.bundle = bundle
        self.id = config.id
        self.config = config
        self.seamless = SeamlessSession(machineName: config.name)
        super.init()
        reloadSnapshots()
        seamless.onAppsChanged = { [weak self] apps in
            guard let self else { return }
            LinuxAppCatalog.shared.update(machine: self.id, machineName: self.config.name, apps: apps)
        }
    }

    var isRunning: Bool { state != .stopped }


    func update(_ change: (inout MachineConfig) -> Void) {
        var copy = config
        change(&copy)
        do {
            try bundle.save(copy)
            if copy.name != config.name {
                LinuxAppCatalog.shared.renameMachine(id, to: copy.name)
            }
            config = copy
            seamless.prefersMacTextInput = copy.macTextInput
            seamless.prefersWayland = copy.preferWayland
        } catch {
            errorMessage = "บันทึกการตั้งค่าไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    func growDisk(toGB gb: Int) {
        guard state == .stopped, gb > config.diskGB else { return }
        do {
            try bundle.growDisk(toGB: gb)
            update { $0.diskGB = gb }
        } catch {
            errorMessage = "ขยายดิสก์ไม่สำเร็จ: \(error.localizedDescription)"
        }
    }


    func launchLinuxApp(_ appID: String) {
        if state == .stopped {
            start()
            guard state != .stopped else { return }
        }
        seamless.launchWhenReady(appID)
    }


    func start() {
        guard state == .stopped else { return }
        do {
            try openUserSelectedFiles()
            let configuration = try ConfigurationBuilder.make(bundle: bundle, config: config)
            try configuration.validate()

            let machine = VZVirtualMachine(configuration: configuration)
            machine.delegate = self
            virtualMachine = machine
            state = .starting
            listenForSetupProgress(on: machine)
            seamless.machineName = config.name
            seamless.prefersHiDPI = config.hiDPI
            seamless.prefersMacTextInput = config.macTextInput
            seamless.prefersWayland = config.preferWayland
            seamless.attach(to: machine)

            machine.start { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.state = .running
                    case .failure(let error):
                        self.errorMessage = "เปิดเครื่องไม่สำเร็จ: \(error.localizedDescription)"
                        self.didStop()
                    }
                }
            }
        } catch {
            fileAccess.endAll()
            errorMessage = "ตั้งค่าเครื่องไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    private func openUserSelectedFiles() throws {
        fileAccess.endAll()
        if let data = config.sharedFolderBookmark, let resolved = SecurityScopedBookmark.resolve(data) {
            fileAccess.begin(resolved.url)
            if resolved.url.path != config.sharedFolderPath || resolved.isStale {
                let fresh = resolved.isStale ? SecurityScopedBookmark.make(for: resolved.url) ?? data : data
                update { $0.sharedFolderPath = resolved.url.path; $0.sharedFolderBookmark = fresh }
            }
        } else if AppEnvironment.isSandboxed && config.sharedFolderPath != nil {
            throw LinMOError.message("ต้องเลือกโฟลเดอร์แชร์ใหม่อีกครั้งเพื่อให้สิทธิ์ LinMO (เมนู ••• → เปลี่ยนโฟลเดอร์แชร์) หรือเลิกแชร์โฟลเดอร์")
        }
        if let data = config.installerISOBookmark, let resolved = SecurityScopedBookmark.resolve(data) {
            fileAccess.begin(resolved.url)
            if resolved.url.path != config.installerISOPath || resolved.isStale {
                let fresh = resolved.isStale ? SecurityScopedBookmark.make(for: resolved.url) ?? data : data
                update { $0.installerISOPath = resolved.url.path; $0.installerISOBookmark = fresh }
            }
        }
    }

    func setSharedFolder(_ url: URL?) {
        update {
            $0.sharedFolderPath = url?.path
            $0.sharedFolderBookmark = url.flatMap { SecurityScopedBookmark.make(for: $0) }
        }
    }

    func ejectInstaller() {
        update {
            $0.installerISOPath = nil
            $0.installerISOBookmark = nil
        }
    }

    func requestShutdown() {
        guard let machine = virtualMachine, state == .running else { return }
        restartAfterSetup = false
        if machine.canRequestStop {
            do {
                try machine.requestStop()
                state = .stopping
            } catch {
                errorMessage = "ส่งคำสั่งปิดเครื่องไม่สำเร็จ: \(error.localizedDescription)"
            }
        } else {
            forceStop()
        }
    }

    func forceStop() {
        guard let machine = virtualMachine, machine.canStop else { return }
        restartAfterSetup = false
        state = .stopping
        machine.stop { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = "ปิดเครื่องไม่สำเร็จ: \(error.localizedDescription)"
                }
                self.didStop()
            }
        }
    }

    func display(for vm: VZVirtualMachine) -> VZVirtualMachineView {
        if let view = displayView, view.virtualMachine === vm {
            return view
        }
        let view = VZVirtualMachineView()
        view.virtualMachine = vm
        view.capturesSystemKeys = true
        view.automaticallyReconfiguresDisplay = true
        displayView = view
        return view
    }

    fileprivate func didStop() {
        fileAccess.endAll()
        seamless.detach(from: virtualMachine)
        setupListener?.detach(from: virtualMachine)
        setupListener = nil
        if setupStatus?.finished != true {
            setupStatus = nil
        }
        virtualMachine = nil
        displayView = nil
        state = .stopped

        if restartAfterSetup {
            restartAfterSetup = false
            start()
        }
    }


    private func listenForSetupProgress(on machine: VZVirtualMachine) {
        guard config.attachCloudInitSeed, !config.firstBootCompleted else { return }
        let listener = SetupProgressListener { [weak self] status in
            self?.receive(status)
        }
        listener.attach(to: machine)
        setupListener = listener
    }

    private func receive(_ status: SetupStatus) {
        setupStatus = status
        if status.finished && !config.firstBootCompleted {
            update { $0.firstBootCompleted = true }
            restartAfterSetup = true
            if status.errors == 0 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    self?.setupStatus = nil
                }
            }
        }
    }

    func dismissSetupStatus() {
        setupStatus = nil
    }


    func reloadSnapshots() {
        snapshots = bundle.listSnapshots()
    }

    func createSnapshot(named name: String) {
        guard state == .stopped else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty
            ? "Snapshot " + Date().formatted(date: .abbreviated, time: .shortened)
            : trimmed
        do {
            _ = try bundle.createSnapshot(named: finalName)
            reloadSnapshots()
        } catch {
            errorMessage = "บันทึก snapshot ไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    func restoreSnapshot(_ snapshot: Snapshot) {
        guard state == .stopped else { return }
        do {
            try bundle.restoreSnapshot(snapshot)
        } catch {
            errorMessage = "ย้อนกลับไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    func deleteSnapshot(_ snapshot: Snapshot) {
        do {
            try bundle.deleteSnapshot(snapshot)
            reloadSnapshots()
        } catch {
            errorMessage = "ลบ snapshot ไม่สำเร็จ: \(error.localizedDescription)"
        }
    }
}


extension MachineController: VZVirtualMachineDelegate {
    nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        Task { @MainActor in self.didStop() }
    }

    nonisolated func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "เครื่องหยุดทำงานเพราะมีข้อผิดพลาด: \(error.localizedDescription)"
            self.didStop()
        }
    }
}
