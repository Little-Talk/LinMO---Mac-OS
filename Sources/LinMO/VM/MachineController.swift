import AppKit
import Foundation
import Virtualization

@MainActor
final class MachineController: NSObject, ObservableObject, Identifiable {
    enum State: Equatable {
        case stopped, starting, running, suspending, stopping
    }

    let bundle: MachineBundle
    nonisolated let id: UUID

    @Published private(set) var config: MachineConfig
    @Published private(set) var state: State = .stopped
    @Published private(set) var virtualMachine: VZVirtualMachine?
    @Published private(set) var snapshots: [Snapshot] = []
    @Published private(set) var setupStatus: SetupStatus?
    @Published private(set) var isSuspended = false
    @Published private(set) var canSuspend = false
    @Published var errorMessage: String?

    private var setupListener: SetupProgressListener?
    private var displayView: VZVirtualMachineView?
    let seamless: SeamlessSession
    let ports = PortForwarder()
    private var restartAfterSetup = false
    private let fileAccess = SecurityScopedAccess()
    private var folderWatcher: SharedFolderWatcher?
    private var extraWatchers: [SharedFolderWatcher] = []
    private var machineLock: MachineLock?

    init(bundle: MachineBundle, config: MachineConfig) {
        self.bundle = bundle
        self.id = config.id
        self.config = config
        self.seamless = SeamlessSession(machineName: config.name)
        super.init()
        isSuspended = bundle.hasSavedState
        reloadSnapshots()
        seamless.onAppsChanged = { [weak self] apps in
            guard let self else { return }
            LinuxAppCatalog.shared.update(machine: self.id, machineName: self.config.name, apps: apps)
        }
        seamless.onEnabledChanged = { [weak self] enabled in
            self?.fitDisplay(forSeamless: enabled)
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
        guard !isSuspended else {
            errorMessage = "เครื่องพักอยู่ ขยายดิสก์ไม่ได้ เปิดเครื่องแล้วปิดเครื่องก่อนจึงจะขยายดิสก์ได้"
            return
        }
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
        let mac = bundle.macAddress().string
        if let twin = MachineLibrary.shared.machines.first(where: { $0 !== self && $0.isRunning && $0.bundle.macAddress().string == mac }) {
            errorMessage = "\"\(twin.config.name)\" เป็นต้นฉบับหรือสำเนาของเครื่องนี้และเปิดอยู่ ปิดเครื่องนั้นก่อน เพราะสองเครื่องใช้การ์ดเครือข่ายเดียวกันจะต่ออินเทอร์เน็ตชนกัน"
            return
        }
        do {
            machineLock = try bundle.acquireLock()
            try openUserSelectedFiles()
            let configuration = try ConfigurationBuilder.make(bundle: bundle, config: config)
            try configuration.validate()

            canSuspend = (try? configuration.validateSaveRestoreSupport()) != nil

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
            ports.attach(to: machine, sshPort: UInt16(clamping: assignSSHPort()), name: config.name)
            startFolderWatcher()

            if bundle.hasSavedState && canSuspend {
                resume(machine)
            } else {
                bundle.discardSavedState()
                isSuspended = false
                boot(machine)
            }
        } catch {
            fileAccess.endAll()
            machineLock = nil
            errorMessage = "ตั้งค่าเครื่องไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    private func assignSSHPort() -> Int {
        if let port = config.sshPort { return port }
        let used = Set(MachineLibrary.shared.machines.compactMap { $0.config.sshPort })
        var port = 2222
        while used.contains(port) { port += 1 }
        update { $0.sshPort = port }
        return port
    }

    private func boot(_ machine: VZVirtualMachine) {
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
    }

    private func resume(_ machine: VZVirtualMachine) {
        machine.restoreMachineStateFrom(url: bundle.savedStateURL) { [weak self] error in
            Task { @MainActor in
                guard let self, self.virtualMachine === machine else { return }
                self.bundle.discardSavedState()
                self.isSuspended = false
                if error != nil {
                    self.boot(machine)
                    return
                }
                machine.resume { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        switch result {
                        case .success:
                            self.state = .running
                        case .failure(let error):
                            self.errorMessage = "เปิดเครื่องต่อจากที่พักไว้ไม่สำเร็จ: \(error.localizedDescription)"
                            self.forceStop()
                        }
                    }
                }
            }
        }
    }

    func suspend(completion: (() -> Void)? = nil) {
        guard let machine = virtualMachine, state == .running, canSuspend, machine.canPause else {
            completion?()
            return
        }
        restartAfterSetup = false
        state = .suspending
        let url = bundle.savedStateURL
        machine.pause { [weak self] result in
            Task { @MainActor in
                guard let self else { completion?(); return }
                if case .failure(let error) = result {
                    self.errorMessage = "พักเครื่องไม่สำเร็จ: \(error.localizedDescription)"
                    self.state = .running
                    completion?()
                    return
                }
                machine.saveMachineStateTo(url: url) { [weak self] error in
                    Task { @MainActor in
                        guard let self else { completion?(); return }
                        if let error {
                            self.bundle.discardSavedState()
                            self.errorMessage = "พักเครื่องไม่สำเร็จ: \(error.localizedDescription)"
                            machine.resume { _ in
                                Task { @MainActor in
                                    self.state = .running
                                    completion?()
                                }
                            }
                            return
                        }
                        self.isSuspended = true
                        machine.stop { _ in
                            Task { @MainActor in
                                self.didStop()
                                completion?()
                            }
                        }
                    }
                }
            }
        }
    }

    func discardSuspendedState() {
        guard state == .stopped else { return }
        bundle.discardSavedState()
        isSuspended = false
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
        var refreshed = config.extraFolders
        for index in refreshed.indices {
            guard let data = refreshed[index].bookmark, let resolved = SecurityScopedBookmark.resolve(data) else { continue }
            fileAccess.begin(resolved.url)
            refreshed[index].path = resolved.url.path
            if resolved.isStale, let fresh = SecurityScopedBookmark.make(for: resolved.url) {
                refreshed[index].bookmark = fresh
            }
        }
        if refreshed != config.extraFolders {
            update { $0.extraFolders = refreshed }
        }
        if let data = config.installerISOBookmark, let resolved = SecurityScopedBookmark.resolve(data) {
            fileAccess.begin(resolved.url)
            if resolved.url.path != config.installerISOPath || resolved.isStale {
                let fresh = resolved.isStale ? SecurityScopedBookmark.make(for: resolved.url) ?? data : data
                update { $0.installerISOPath = resolved.url.path; $0.installerISOBookmark = fresh }
            }
        }
    }

    private func startFolderWatcher() {
        folderWatcher?.stop()
        folderWatcher = config.sharedFolderPath.flatMap { path in
            SharedFolderWatcher(path: path) { [weak self] paths in
                Task { @MainActor in self?.seamless.notifyFolderChanges(paths) }
            }
        }
        extraWatchers.forEach { $0.stop() }
        extraWatchers = config.extraFolders.compactMap { folder in
            let name = folder.name
            return SharedFolderWatcher(path: folder.path) { [weak self] paths in
                let prefixed = paths.map { "\(name)/\($0)" }
                Task { @MainActor in self?.seamless.notifyFolderChanges(prefixed, tag: SharedTags.extraFolders) }
            }
        }
    }

    func addExtraFolder(_ url: URL) {
        update {
            guard !$0.extraFolders.contains(where: { $0.path == url.path }) else { return }
            let folder = ExtraFolder(name: ExtraFolder.uniqueName(for: url, existing: $0.extraFolders),
                                     path: url.path,
                                     bookmark: SecurityScopedBookmark.make(for: url))
            $0.extraFolders.append(folder)
        }
    }

    func removeExtraFolder(_ id: UUID) {
        update { $0.extraFolders.removeAll { $0.id == id } }
    }

    func setExtraFolder(_ id: UUID, readOnly: Bool) {
        update {
            guard let index = $0.extraFolders.firstIndex(where: { $0.id == id }) else { return }
            $0.extraFolders[index].readOnly = readOnly
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
        view.automaticallyReconfiguresDisplay = !seamless.isEnabled
        displayView = view
        return view
    }

    private var guestDisplay: VZGraphicsDisplay? {
        virtualMachine?.graphicsDevices.first?.displays.first
    }

    private func fitDisplay(forSeamless enabled: Bool) {
        displayView?.automaticallyReconfiguresDisplay = !enabled
        guard enabled else { return }
        try? guestDisplay?.reconfigure(sizeInPixels: seamlessDisplaySize())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.seamless.isEnabled, let display = self.guestDisplay else { return }
            self.displayView?.automaticallyReconfiguresDisplay = false
            let size = self.seamlessDisplaySize()
            guard display.sizeInPixels != size else { return }
            try? display.reconfigure(sizeInPixels: size)
        }
    }

    private func seamlessDisplaySize() -> CGSize {
        let factor: CGFloat = config.hiDPI ? 2 : 1
        let width = NSScreen.screens.map { $0.frame.width * factor }.max() ?? 1920 * factor
        let height = NSScreen.screens.map { $0.frame.height * factor }.max() ?? 1200 * factor
        return CGSize(width: min(max(width, 1920), 7680), height: min(max(height, 1200), 4320))
    }

    fileprivate func didStop() {
        folderWatcher?.stop()
        folderWatcher = nil
        extraWatchers.forEach { $0.stop() }
        extraWatchers = []
        fileAccess.endAll()
        seamless.detach(from: virtualMachine)
        ports.detach()
        setupListener?.detach(from: virtualMachine)
        setupListener = nil
        if setupStatus?.finished != true {
            setupStatus = nil
        }
        virtualMachine = nil
        displayView = nil
        machineLock = nil
        state = .stopped

        if restartAfterSetup {
            restartAfterSetup = false
            if setupStatus?.errors == 0, snapshots.isEmpty, (try? bundle.createSnapshot(named: "หลังติดตั้งเสร็จ")) != nil {
                reloadSnapshots()
            }
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
        guard state == .stopped, !isSuspended else { return }
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
        guard state == .stopped, !isSuspended else { return }
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
