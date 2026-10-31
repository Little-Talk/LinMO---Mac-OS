import AppKit
import SwiftUI

struct MachineDetailView: View {
    @EnvironmentObject private var library: MachineLibrary
    @ObservedObject var machine: MachineController

    @State private var showingFolderPicker = false
    @State private var showingSnapshots = false
    @State private var showingSettings = false
    @State private var confirmingDelete = false

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
        .confirmationDialog("ลบ \"\(machine.config.name)\" ทิ้ง?", isPresented: $confirmingDelete) {
            Button("ลบถาวร", role: .destructive) { library.delete(machine) }
        } message: {
            Text("ไฟล์ โปรแกรม และ snapshot ทั้งหมดของเครื่องนี้จะหายไปและกู้คืนไม่ได้")
        }
        .errorAlert($machine.errorMessage)
    }


    private var header: some View {
        HStack(spacing: 12) {
            StatusBadge(state: machine.state)

            Spacer()

            if machine.state == .stopped {
                if machine.config.installerISOPath != nil {
                    Button("ถอดแผ่นติดตั้ง") {
                        machine.ejectInstaller()
                    }
                    .help("กดหลังติดตั้ง Linux ลงดิสก์เสร็จแล้ว เพื่อให้บูตจากดิสก์")
                }

                Button {
                    showingSnapshots = true
                } label: {
                    Label("Snapshot", systemImage: "clock.arrow.circlepath")
                }
                .help("บันทึกสถานะเครื่อง และย้อนกลับเมื่อทำพัง")

                Menu {
                    Button("ตั้งค่าเครื่อง…") { showingSettings = true }
                    Divider()
                    Button(machine.config.sharedFolderPath == nil ? "แชร์โฟลเดอร์…" : "เปลี่ยนโฟลเดอร์แชร์…") {
                        showingFolderPicker = true
                    }
                    if machine.config.sharedFolderPath != nil {
                        Button("เลิกแชร์โฟลเดอร์") {
                            machine.setSharedFolder(nil)
                        }
                    }
                    Divider()
                    Button("แสดงไฟล์ของเครื่องใน Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([machine.bundle.url])
                    }
                    Divider()
                    Button("ลบเครื่องนี้…", role: .destructive) { confirmingDelete = true }
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
                    Label("เปิดเครื่อง", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
            }

            if machine.state == .running {
                SeamlessToggle(session: machine.seamless)
                FullScreenButton(session: machine.seamless)
                WineInstallButton(rosettaEnabled: machine.config.rosettaEnabled)

                Button {
                    machine.requestShutdown()
                } label: {
                    Label("ปิดเครื่อง", systemImage: "power")
                }
            }

            if machine.state == .starting || machine.state == .stopping {
                Button("บังคับปิด") { machine.forceStop() }
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
                Text("เครื่องปิดอยู่")
                    .font(.title3)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    infoRow("CPU", "\(machine.config.cpuCount) คอร์")
                    infoRow("RAM", "\(machine.config.memoryGB) GB")
                    infoRow("ดิสก์", "\(machine.config.diskGB) GB")
                    if let folder = machine.config.sharedFolderPath {
                        infoRow("โฟลเดอร์แชร์", folder)
                    }
                    if machine.config.rosettaEnabled {
                        infoRow("Rosetta", "เปิดใช้")
                    }
                    if let preset = machine.config.preset, preset != .basic {
                        infoRow("ชุดโปรแกรม", preset.title)
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
    @State private var installingRosetta = false

    private let maxCPU = ProcessInfo.processInfo.processorCount
    private let maxMemoryGB = max(2, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) - 2)

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("ชื่อเครื่อง", text: $name)
                Stepper("CPU: \(cpuCount) คอร์", value: $cpuCount, in: 1...max(1, maxCPU))
                Stepper("RAM: \(memoryGB) GB", value: $memoryGB, in: 2...maxMemoryGB)
                Stepper("ดิสก์: \(diskGB) GB", value: $diskGB, in: machine.config.diskGB...1024, step: 8)
                Text("ขยายดิสก์ได้อย่างเดียว ลดขนาดไม่ได้")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if RosettaSupport.availability != .notSupported {
                    Toggle("รันโปรแกรม x86_64 ผ่าน Rosetta", isOn: $rosetta)
                    if rosetta && !machine.config.rosettaEnabled {
                        Text("มีผลเมื่อเปิดเครื่องครั้งถัดไป จากนั้นรันคำสั่งติดตั้ง LinMO Tools ใน Linux อีกครั้งหนึ่งครั้ง")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("คมชัดสูงบนจอ Retina", isOn: $hiDPI)
                Text("Linux ใช้ความละเอียดเท่าจอ Mac และขยายตัวหนังสือ 2 เท่า มีผลเมื่อเปิดเครื่องครั้งถัดไป")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("พิมพ์ด้วยแป้นพิมพ์ของ Mac (โหมดหน้าต่างแยก)", isOn: $macTextInput)
                Text("สลับภาษาไทย/อังกฤษด้วยปุ่มของ Mac ได้เลย ปุ่ม Option จะใช้พิมพ์อักขระพิเศษแบบ Mac แทน Alt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("เปิดแอพผ่าน Wayland (ทดลอง)", isOn: $preferWayland)
                Text("ใช้ compositor ของ LinMO เอง เหมาะกับ distro ที่ใช้ Wayland อย่างเดียว แอพ X11 ก็เปิดผ่านทางนี้ได้ (Xwayland)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("ยกเลิก") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if installingRosetta { ProgressView().controlSize(.small) }
                Button("บันทึก") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || installingRosetta)
            }
            .padding(16)
        }
        .frame(width: 480, height: 620)
        .onAppear {
            name = machine.config.name
            cpuCount = machine.config.cpuCount
            memoryGB = machine.config.memoryGB
            diskGB = machine.config.diskGB
            rosetta = machine.config.rosettaEnabled
            hiDPI = machine.config.hiDPI
            macTextInput = machine.config.macTextInput
            preferWayland = machine.config.preferWayland
        }
    }

    private func save() {
        Task {
            if rosetta && RosettaSupport.availability == .notInstalled {
                installingRosetta = true
                do {
                    try await RosettaSupport.install()
                } catch {
                    machine.errorMessage = "ติดตั้ง Rosetta ไม่สำเร็จ: \(error.localizedDescription)"
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
            }
            machine.growDisk(toGB: diskGB)
            dismiss()
        }
    }
}
