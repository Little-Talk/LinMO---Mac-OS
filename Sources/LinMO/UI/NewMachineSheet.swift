import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NewMachineSheet: View {
    enum Source: Hashable {
        case distro(Distro)
        case customISO
    }

    enum Step {
        case chooseSource, configure, progress
    }

    @EnvironmentObject private var library: MachineLibrary
    @Environment(\.dismiss) private var dismiss
    let onCreated: (MachineController) -> Void

    @State private var step: Step = .chooseSource
    @State private var source: Source = .distro(DistroCatalog.all[0])

    @State private var name = DistroCatalog.all[0].shortName
    @State private var cpuCount = min(4, max(2, ProcessInfo.processInfo.processorCount / 2))
    @State private var memoryGB = 4
    @State private var diskGB = 32
    @State private var isoPath: String?
    @State private var isoBookmark: Data?
    @State private var sharedFolderPath: String?
    @State private var sharedFolderBookmark: Data?

    @State private var username = NSUserName().lowercased()
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var thaiKeyboard = true
    @State private var thaiInterface = false
    @State private var autologin = true
    @State private var rosetta = false
    @State private var desktop: Desktop = .xfce
    @State private var preset: Preset = .basic

    @State private var showingISOPicker = false
    @State private var showingFolderPicker = false
    @StateObject private var provisioner = Provisioner()
    @State private var errorMessage: String?

    private let maxCPU = ProcessInfo.processInfo.processorCount
    private let maxMemoryGB = max(2, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) - 2)
    private let rosettaAvailability = RosettaSupport.availability

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .chooseSource: chooseSourceView
                case .configure: configureView
                case .progress: progressView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            footer
        }
        .frame(width: 620, height: 640)
        .interactiveDismissDisabled(step == .progress)
        .errorAlert($errorMessage)
    }


    private var chooseSourceView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("เลือก Linux ที่จะติดตั้ง")
                .font(.title2.bold())

            ForEach(DistroCatalog.all) { distro in
                SourceCard(
                    title: distro.name,
                    subtitle: distro.summary,
                    detail: ImageStore.cachedDisk(for: distro) != nil
                        ? "ดาวน์โหลดไว้แล้ว — สร้างได้ทันที"
                        : "ติดตั้งอัตโนมัติ · ดาวน์โหลดประมาณ \(distro.approximateDownloadMB) MB",
                    systemImage: "sparkles",
                    isSelected: source == .distro(distro)
                ) {
                    source = .distro(distro)
                    name = distro.shortName
                    if !distro.desktops.contains(desktop) { desktop = distro.desktops[0] }
                }
            }

            SourceCard(
                title: "ติดตั้งเองจากไฟล์ ISO",
                subtitle: "ใช้ไฟล์ติดตั้ง ARM64 ของ distro ไหนก็ได้ เช่น Ubuntu, Fedora",
                detail: "สำหรับผู้ที่คุ้นเคย ต้องกดติดตั้งเองตามขั้นตอนของ distro",
                systemImage: "opticaldisc",
                isSelected: source == .customISO
            ) {
                source = .customISO
                name = "Linux"
            }
            Spacer()
        }
        .padding(24)
    }


    private var configureView: some View {
        Form {
            if source != .customISO {
                Section {
                    ForEach(Preset.allCases) { option in
                        PresetRow(preset: option, isSelected: preset == option) { choose(option) }
                    }
                } header: {
                    Text("ชุดโปรแกรม")
                } footer: {
                    if preset != .basic {
                        Text("ติดตั้งระหว่างตั้งค่าครั้งแรก ใช้เวลาและเน็ตเพิ่มขึ้น — โปรแกรมที่ distro นี้ไม่มีจะถูกข้ามไป")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("เครื่อง") {
                TextField("ชื่อเครื่อง", text: $name)
                Stepper("CPU: \(cpuCount) คอร์", value: $cpuCount, in: 1...max(1, maxCPU))
                Stepper("RAM: \(memoryGB) GB", value: $memoryGB, in: 2...maxMemoryGB)
                Stepper("ดิสก์: \(diskGB) GB", value: $diskGB, in: 16...1024, step: 8)
            }

            if source == .customISO {
                Section("ไฟล์ติดตั้ง") {
                    LabeledContent("ไฟล์ ISO (ARM64)") {
                        HStack {
                            Text(isoPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "ยังไม่ได้เลือก")
                                .foregroundStyle(isoPath == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("เลือกไฟล์…") { showingISOPicker = true }
                        }
                    }
                    .fileImporter(
                        isPresented: $showingISOPicker,
                        allowedContentTypes: [UTType(filenameExtension: "iso") ?? .diskImage, .diskImage]
                    ) { result in
                        if case .success(let url) = result {
                            isoPath = url.path
                            isoBookmark = SecurityScopedBookmark.make(for: url)
                        }
                    }
                }
            } else {
                if case .distro(let distro) = source, distro.desktops.count > 1 {
                    Section("หน้าจอ desktop") {
                        Picker("หน้าจอ desktop", selection: $desktop) {
                            ForEach(distro.desktops) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }

                Section("บัญชีผู้ใช้ใน Linux") {
                    TextField("ชื่อผู้ใช้ (ภาษาอังกฤษตัวเล็ก)", text: $username)
                    if !username.isEmpty && !GuestSetupOptions.isValidUsername(username) {
                        Text("ใช้ได้เฉพาะ a-z, 0-9, _ และ - และต้องขึ้นต้นด้วยตัวอักษร")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    SecureField("รหัสผ่าน", text: $password)
                    SecureField("ยืนยันรหัสผ่าน", text: $confirmPassword)
                    if !confirmPassword.isEmpty && password != confirmPassword {
                        Text("รหัสผ่านไม่ตรงกัน")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Toggle("เข้าระบบอัตโนมัติ (ไม่ต้องใส่รหัสตอนเปิดเครื่อง)", isOn: $autologin)
                }

                Section("ภาษาไทย") {
                    Toggle(
                        desktop == .gnome
                            ? "คีย์บอร์ดไทย (สลับภาษาด้วย Cmd + Space)"
                            : "คีย์บอร์ดไทย (สลับภาษาด้วย Option + Shift)",
                        isOn: $thaiKeyboard
                    )
                    Toggle("เมนูภาษาไทย", isOn: $thaiInterface)
                    Text("ฟอนต์ไทยติดตั้งให้เสมอ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("เชื่อมกับ Mac") {
                LabeledContent("โฟลเดอร์แชร์") {
                    HStack {
                        Text(sharedFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "ไม่แชร์")
                            .foregroundStyle(sharedFolderPath == nil ? .secondary : .primary)
                        if sharedFolderPath != nil {
                            Button("ยกเลิก") {
                                sharedFolderPath = nil
                                sharedFolderBookmark = nil
                            }
                        }
                        Button("เลือก…") { showingFolderPicker = true }
                    }
                }
                .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        sharedFolderPath = url.path
                        sharedFolderBookmark = SecurityScopedBookmark.make(for: url)
                    }
                }
                if source != .customISO {
                    Text("ใน Linux จะเห็นโฟลเดอร์นี้ที่ ~/Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if rosettaAvailability != .notSupported {
                    Toggle("รันโปรแกรม x86_64 ผ่าน Rosetta", isOn: $rosetta)
                    if rosetta && rosettaAvailability == .notInstalled {
                        Text("macOS จะขอติดตั้ง Rosetta ก่อนสร้างเครื่อง")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }


    private var progressView: some View {
        VStack(spacing: 18) {
            Spacer()
            switch provisioner.phase {
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("สร้างเครื่องเสร็จแล้ว")
                    .font(.title2.bold())
                Text("กด \"เปิดเครื่อง\" ได้เลย ครั้งแรก Linux จะติดตั้งหน้าจอและภาษาไทยเอง ใช้เวลาประมาณ 10–30 นาที (ต้องต่ออินเทอร์เน็ต) ดูความคืบหน้าได้ที่แถบด้านล่างของหน้าจอ เสร็จแล้วจะเข้าหน้าจอ desktop ให้อัตโนมัติ")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            default:
                if let fraction = provisioner.phase.fraction {
                    ProgressView(value: fraction)
                        .frame(maxWidth: 360)
                } else {
                    ProgressView()
                }
                Text(provisioner.phase.title)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }


    private var footer: some View {
        HStack {
            switch step {
            case .chooseSource:
                Button("ยกเลิก") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("ถัดไป") { step = .configure }
                    .keyboardShortcut(.defaultAction)

            case .configure:
                Button("ย้อนกลับ") { step = .chooseSource }
                Spacer()
                Button(source == .customISO ? "สร้างเครื่อง" : "ติดตั้ง") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)

            case .progress:
                switch provisioner.phase {
                case .finished:
                    Spacer()
                    Button("เสร็จ") { finish(start: false) }
                    Button("เปิดเครื่อง") { finish(start: true) }
                        .keyboardShortcut(.defaultAction)
                case .failed:
                    Button("ปิด") { dismiss() }
                    Spacer()
                    Button("ย้อนกลับไปแก้ไข") { step = .configure }
                        .keyboardShortcut(.defaultAction)
                default:
                    Spacer()
                    Text("ปิดหน้าต่างนี้ไม่ได้ระหว่างติดตั้ง")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }


    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch source {
        case .customISO:
            return isoPath != nil
        case .distro:
            return GuestSetupOptions.isValidUsername(username)
                && !password.isEmpty
                && password == confirmPassword
        }
    }

    private func makeConfig() -> MachineConfig {
        var config = MachineConfig(name: name.trimmingCharacters(in: .whitespaces))
        config.cpuCount = cpuCount
        config.memoryGB = memoryGB
        config.diskGB = diskGB
        config.sharedFolderPath = sharedFolderPath
        config.sharedFolderBookmark = sharedFolderBookmark
        config.hiDPI = NSScreen.main.map { $0.backingScaleFactor >= 2 } ?? false
        return config
    }

    private func create() {
        switch source {
        case .customISO:
            var config = makeConfig()
            config.installerISOPath = isoPath
            config.installerISOBookmark = isoBookmark
            config.rosettaEnabled = rosetta && rosettaAvailability == .installed
            do {
                let bundle = try MachineBundle.create(config: config)
                let controller = MachineController(bundle: bundle, config: config)
                library.add(controller)
                onCreated(controller)
                dismiss()
            } catch {
                errorMessage = "สร้างเครื่องไม่สำเร็จ: \(error.localizedDescription)"
            }

        case .distro(let distro):
            let options = GuestSetupOptions(
                hostname: GuestSetupOptions.hostname(from: name),
                username: username,
                password: password,
                desktop: distro.desktops.contains(desktop) ? desktop : distro.desktops[0],
                thaiKeyboard: thaiKeyboard,
                thaiInterface: thaiInterface,
                autologin: autologin,
                rosetta: rosetta,
                preset: preset
            )
            var config = makeConfig()
            config.preset = preset
            step = .progress
            Task {
                await provisioner.run(distro: distro, config: config, options: options, library: library)
            }
        }
    }

    private func choose(_ option: Preset) {
        preset = option
        let recommended = option.recommended
        cpuCount = min(max(cpuCount, recommended.cpu), max(1, maxCPU))
        memoryGB = min(max(memoryGB, recommended.memoryGB), maxMemoryGB)
        diskGB = max(diskGB, recommended.diskGB)
    }

    private func finish(start: Bool) {
        if let machine = provisioner.createdMachine {
            onCreated(machine)
            if start { machine.start() }
        }
        dismiss()
    }
}

private struct PresetRow: View {
    let preset: Preset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: preset.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title).font(.body.weight(.medium))
                    Text(preset.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SourceCard: View {
    let title: String
    let subtitle: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).foregroundStyle(.secondary)
                    Text(detail).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
