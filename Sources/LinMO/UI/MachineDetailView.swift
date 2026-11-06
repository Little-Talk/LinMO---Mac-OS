import AppKit
import AVFoundation
import SwiftUI

struct MachineDetailView: View {
    @EnvironmentObject private var library: MachineLibrary
    @ObservedObject var machine: MachineController

    @State private var showingFolderPicker = false
    @State private var showingSnapshots = false
    @State private var showingSettings = false
    @State private var showingExtraFolders = false
    @State private var confirmingDelete = false
    @State private var confirmingDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            display
        }
        .navigationTitle(machine.config.name)
        .sheet(isPresented: $showingSnapshots) {
            SnapshotsSheet(machine: machine)
        }
        .sheet(isPresented: $showingSettings) {
            MachineSettingsSheet(machine: machine)
        }
        .sheet(isPresented: $showingExtraFolders) {
            ExtraFoldersSheet(machine: machine)
        }
        .confirmationDialog(tr("ลบ \"\(machine.config.name)\" ทิ้ง?", "Delete \"\(machine.config.name)\"?"), isPresented: $confirmingDelete) {
            Button(tr("ลบถาวร", "Delete Permanently"), role: .destructive) { library.delete(machine) }
        } message: {
            Text(tr("ไฟล์ โปรแกรม และ snapshot ทั้งหมดของเครื่องนี้จะหายไปและกู้คืนไม่ได้", "All files, programs and snapshots of this machine will be removed and cannot be recovered."))
        }
        .confirmationDialog(tr("ทิ้งสถานะที่พักไว้?", "Discard the suspended state?"), isPresented: $confirmingDiscard) {
            Button(tr("ทิ้งแล้วเปิดใหม่ครั้งหน้า", "Discard and Start Fresh Next Time"), role: .destructive) { machine.discardSuspendedState() }
        } message: {
            Text(tr("แอพและไฟล์ที่เปิดค้างไว้ใน Linux จะหายไป เหมือนถอดปลั๊กเครื่อง งานที่ยังไม่บันทึกจะหาย", "Apps and files left open in Linux will be lost, like pulling the plug. Unsaved work will be lost."))
        }
        .errorAlert($machine.errorMessage)
    }


    private var header: some View {
        HStack(spacing: 12) {
            StatusBadge(state: machine.state, suspended: machine.isSuspended)

            Spacer()

            if machine.state == .stopped {
                if machine.config.installerISOPath != nil {
                    Button(tr("ถอดแผ่นติดตั้ง", "Eject Installer")) {
                        machine.ejectInstaller()
                    }
                    .help(tr("กดหลังติดตั้ง Linux ลงดิสก์เสร็จแล้ว เพื่อให้บูตจากดิสก์", "Click after Linux is installed on the disk, so the machine boots from the disk"))
                }

                Button {
                    showingSnapshots = true
                } label: {
                    Label("Snapshot", systemImage: "clock.arrow.circlepath")
                }
                .help(machine.isSuspended ? tr("เครื่องพักอยู่ เปิดเครื่องแล้วปิดเครื่องก่อนจึงจะทำ snapshot ได้", "The machine is suspended. Start it and shut it down before taking a snapshot") : tr("บันทึกสถานะเครื่อง และย้อนกลับเมื่อทำพัง", "Save the machine state and go back if something breaks"))
                .disabled(machine.isSuspended)

                Menu {
                    Group {
                        Button(tr("ตั้งค่าเครื่อง…", "Machine Settings…")) { showingSettings = true }
                        Divider()
                        Button(machine.config.sharedFolderPath == nil ? tr("แชร์โฟลเดอร์…", "Share a Folder…") : tr("เปลี่ยนโฟลเดอร์แชร์…", "Change Shared Folder…")) {
                            showingFolderPicker = true
                        }
                        if machine.config.sharedFolderPath != nil {
                            Button(tr("เลิกแชร์โฟลเดอร์", "Stop Sharing Folder")) {
                                machine.setSharedFolder(nil)
                            }
                        }
                        Button(tr("โฟลเดอร์แชร์เพิ่มเติม…", "More Shared Folders…")) { showingExtraFolders = true }
                        Divider()
                        Button(tr("ทำสำเนาเครื่อง", "Duplicate Machine")) { library.duplicate(machine) }
                            .help(tr("สร้างเครื่องใหม่ที่มีทุกอย่างเหมือนเครื่องนี้ ใช้พื้นที่เพิ่มเฉพาะส่วนที่ต่างกัน", "Create a new machine identical to this one. Only the differences use extra space"))
                    }
                    .disabled(machine.isSuspended)
                    if machine.isSuspended {
                        Divider()
                        Button(tr("ทิ้งสถานะที่พักไว้…", "Discard Suspended State…")) { confirmingDiscard = true }
                    }
                    Divider()
                    Button(tr("แสดงไฟล์ของเครื่องใน Finder", "Show Machine Files in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([machine.bundle.url])
                    }
                    Divider()
                    Button(tr("ลบเครื่องนี้…", "Delete This Machine…"), role: .destructive) { confirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        machine.setSharedFolder(url)
                    }
                }

                Button {
                    machine.start()
                } label: {
                    Label(machine.isSuspended ? tr("เปิดต่อ", "Resume") : tr("เปิดเครื่อง", "Start"), systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .help(machine.isSuspended ? tr("กลับไปที่เดิมตอนพักเครื่องไว้", "Pick up where you left off") : tr("เปิดเครื่อง", "Start"))
            }

            if machine.state == .running {
                SeamlessToggle(session: machine.seamless)
                FullScreenButton(session: machine.seamless)
                WineInstallButton(rosettaEnabled: machine.config.rosettaEnabled)
                PortsMenu(forwarder: machine.ports)

                if machine.canSuspend {
                    Button {
                        machine.suspend()
                    } label: {
                        Label(tr("พักเครื่อง", "Suspend"), systemImage: "pause.fill")
                    }
                    .help(tr("เก็บทุกอย่างที่เปิดอยู่ไว้ แล้วกลับมาที่เดิมได้ในไม่กี่วินาที", "Keep everything open and come back to it in seconds"))
                }

                Button {
                    machine.requestShutdown()
                } label: {
                    Label(tr("ปิดเครื่อง", "Shut Down"), systemImage: "power")
                }
            }

            if machine.state == .starting || machine.state == .stopping {
                Button(tr("บังคับปิด", "Force Stop")) { machine.forceStop() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }


    @ViewBuilder
    private var display: some View {
        if let vm = machine.virtualMachine {
            RunningDisplay(controller: machine, vm: vm, seamless: machine.seamless)
                .overlay(alignment: .bottom) {
                    if let status = machine.setupStatus {
                        SetupProgressBanner(status: status) {
                            machine.dismissSetupStatus()
                        }
                        .padding(16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: machine.setupStatus)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(tr("เครื่องปิดอยู่", "The machine is off"))
                    .font(.title3)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    infoRow("CPU", tr("\(machine.config.cpuCount) คอร์", "\(machine.config.cpuCount) cores"))
                    infoRow("RAM", "\(machine.config.memoryGB) GB")
                    infoRow(tr("ดิสก์", "Disk"), "\(machine.config.diskGB) GB")
                    if let folder = machine.config.sharedFolderPath {
                        infoRow(tr("โฟลเดอร์แชร์", "Shared folder"), folder)
                    }
                    if !machine.config.extraFolders.isEmpty {
                        infoRow(tr("แชร์เพิ่มเติม", "More shared folders"), machine.config.extraFolders.map(\.name).joined(separator: ", "))
                    }
                    if machine.config.rosettaEnabled {
                        infoRow("Rosetta", tr("เปิดใช้", "On"))
                    }
                    if let preset = machine.config.preset, preset != .basic {
                        infoRow(tr("ชุดโปรแกรม", "Software set"), preset.title)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
            Text(value).lineLimit(1).truncationMode(.middle)
        }
    }
}

struct MachineSettingsSheet: View {
    @ObservedObject var machine: MachineController
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cpuCount = 2
    @State private var memoryGB = 4
    @State private var diskGB = 32
    @State private var rosetta = false
    @State private var hiDPI = false
    @State private var macTextInput = true
    @State private var preferWayland = false
    @State private var microphone = false
    @State private var installingRosetta = false

    private let maxCPU = ProcessInfo.processInfo.processorCount
    private let maxMemoryGB = max(2, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) - 2)

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(tr("ชื่อเครื่อง", "Machine name"), text: $name)
                Stepper(tr("CPU: \(cpuCount) คอร์", "CPU: \(cpuCount) cores"), value: $cpuCount, in: 1...max(1, maxCPU))
                Stepper("RAM: \(memoryGB) GB", value: $memoryGB, in: 2...maxMemoryGB)
                Stepper(tr("ดิสก์: \(diskGB) GB", "Disk: \(diskGB) GB"), value: $diskGB, in: machine.config.diskGB...1024, step: 8)
                Text(tr("ขยายดิสก์ได้อย่างเดียว ลดขนาดไม่ได้", "The disk can only grow, not shrink"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if RosettaSupport.availability != .notSupported {
                    Toggle(tr("รันโปรแกรม x86_64 ผ่าน Rosetta", "Run x86_64 programs with Rosetta"), isOn: $rosetta)
                    if rosetta && !machine.config.rosettaEnabled {
                        Text(tr("มีผลเมื่อเปิดเครื่องครั้งถัดไป จากนั้นรันคำสั่งติดตั้ง LinMO Tools ใน Linux อีกครั้งหนึ่งครั้ง", "Takes effect the next time the machine starts. Then run the LinMO Tools install command in Linux once more."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(tr("ให้ Linux ใช้ไมโครโฟนของ Mac", "Let Linux use the Mac microphone"), isOn: $microphone)
                    .onChange(of: microphone) {
                        if microphone {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                if !granted {
                                    Task { @MainActor in
                                        microphone = false
                                        machine.errorMessage = tr("LinMO ยังไม่ได้รับสิทธิ์ใช้ไมโครโฟน เปิดได้ที่ System Settings → Privacy & Security → Microphone", "LinMO does not have microphone access yet. Turn it on in System Settings → Privacy & Security → Microphone")
                                    }
                                }
                            }
                        }
                    }
                Text(tr("มีผลเมื่อเปิดเครื่องครั้งถัดไป", "Takes effect the next time the machine starts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(tr("คมชัดสูงบนจอ Retina", "High resolution on Retina displays"), isOn: $hiDPI)
                Text(tr("Linux ใช้ความละเอียดเท่าจอ Mac และขยายตัวหนังสือ 2 เท่า มีผลเมื่อเปิดเครื่องครั้งถัดไป", "Linux uses the full Mac display resolution with 2x text. Takes effect the next time the machine starts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(tr("พิมพ์ด้วยแป้นพิมพ์ของ Mac (โหมดหน้าต่างแยก)", "Type with the Mac keyboard (separate windows mode)"), isOn: $macTextInput)
                Text(tr("สลับภาษาไทย/อังกฤษด้วยปุ่มของ Mac ได้เลย ปุ่ม Option จะใช้พิมพ์อักขระพิเศษแบบ Mac แทน Alt", "Switch input languages with the Mac keys. Option types special characters the Mac way instead of acting as Alt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(tr("เปิดแอพผ่าน Wayland (ทดลอง)", "Open apps through Wayland (experimental)"), isOn: $preferWayland)
                Text(tr("ใช้ compositor ของ LinMO เอง เหมาะกับ distro ที่ใช้ Wayland อย่างเดียว แอพ X11 ก็เปิดผ่านทางนี้ได้ (Xwayland)", "Uses LinMO's own compositor. Good for Wayland-only distros. X11 apps also work this way (Xwayland)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button(tr("ยกเลิก", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if installingRosetta { ProgressView().controlSize(.small) }
                Button(tr("บันทึก", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || installingRosetta)
            }
            .padding(16)
        }
        .frame(width: 480, height: 680)
        .onAppear {
            name = machine.config.name
            cpuCount = machine.config.cpuCount
            memoryGB = machine.config.memoryGB
            diskGB = machine.config.diskGB
            rosetta = machine.config.rosettaEnabled
            hiDPI = machine.config.hiDPI
            macTextInput = machine.config.macTextInput
            preferWayland = machine.config.preferWayland
            microphone = machine.config.microphoneEnabled
        }
    }

    private func save() {
        Task {
            if rosetta && RosettaSupport.availability == .notInstalled {
                installingRosetta = true
                do {
                    try await RosettaSupport.install()
                } catch {
                    machine.errorMessage = tr("ติดตั้ง Rosetta ไม่สำเร็จ: \(error.localizedDescription)", "Could not install Rosetta: \(error.localizedDescription)")
                }
                installingRosetta = false
            }
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            machine.update {
                $0.name = trimmedName
                $0.cpuCount = cpuCount
                $0.memoryGB = memoryGB
                $0.rosettaEnabled = rosetta && RosettaSupport.availability == .installed
                $0.hiDPI = hiDPI
                $0.macTextInput = macTextInput
                $0.preferWayland = preferWayland
                $0.microphoneEnabled = microphone
            }
            machine.growDisk(toGB: diskGB)
            dismiss()
        }
    }
}

struct PortsMenu: View {
    @ObservedObject var forwarder: PortForwarder

    var body: some View {
        if forwarder.isAvailable {
            Menu {
                let web = forwarder.forwarded.filter { $0.guest != 22 }
                if web.isEmpty {
                    Text(tr("ยังไม่มีโปรแกรมใน Linux เปิดพอร์ตรอรับการเชื่อมต่อ", "No program in Linux is listening on a port yet"))
                } else {
                    Section(tr("เปิดใน browser ของ Mac", "Open in a Mac browser")) {
                        ForEach(web) { port in
                            Button("localhost:\(String(port.mac))" + (port.program.map { " — \($0)" } ?? "")) {
                                if let url = URL(string: "http://localhost:\(port.mac)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                if let command = forwarder.sshCommand {
                    Divider()
                    Button(tr("คัดลอกคำสั่ง SSH: \(command)", "Copy SSH Command: \(command)")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                }
                if let command = forwarder.dockerSetupCommand {
                    Divider()
                    Button(tr("คัดลอกคำสั่งใช้ Docker ของ Linux จาก Mac", "Copy Command to Use Linux Docker from the Mac")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .help(command)
                }
            } label: {
                Label(tr("พอร์ต", "Ports"), systemImage: "network")
            }
            .fixedSize()
            .help(tr("โปรแกรมที่เปิดพอร์ตใน Linux ใช้จาก Mac ได้ที่ localhost พอร์ตเดียวกัน", "Programs listening on a port in Linux are reachable from the Mac at localhost on the same port"))
        }
    }
}

struct ExtraFoldersSheet: View {
    @ObservedObject var machine: MachineController
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("โฟลเดอร์แชร์เพิ่มเติม", "More Shared Folders"))
                .font(.headline)
            Text(tr("แต่ละโฟลเดอร์จะอยู่ที่ ~/MacFolders/ชื่อโฟลเดอร์ ใน Linux มีผลเมื่อเปิดเครื่องครั้งถัดไป เครื่องที่สร้างไว้ก่อนต้องอัปเดต LinMO Tools ก่อน", "Each folder appears at ~/MacFolders/<folder name> in Linux. Takes effect the next time the machine starts. Older machines need a LinMO Tools update first."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                if machine.config.extraFolders.isEmpty {
                    Text(tr("ยังไม่มีโฟลเดอร์", "No folders yet"))
                        .foregroundStyle(.secondary)
                }
                ForEach(machine.config.extraFolders) { folder in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                            Text(folder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Toggle(tr("อ่านอย่างเดียว", "Read only"), isOn: Binding(
                            get: { folder.readOnly },
                            set: { machine.setExtraFolder(folder.id, readOnly: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        Button {
                            machine.removeExtraFolder(folder.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(tr("เลิกแชร์โฟลเดอร์นี้", "Stop sharing this folder"))
                    }
                }
            }
            .frame(minHeight: 160)
            HStack {
                Button(tr("เพิ่มโฟลเดอร์…", "Add Folder…")) { picking = true }
                Spacer()
                Button(tr("เสร็จ", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 480)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                urls.forEach { machine.addExtraFolder($0) }
            }
        }
    }
}
