import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NewMachineSheet: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
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
    @State private var isoKind: DiskImageKind = .iso
    @State private var useImageAsDisk = false
    @State private var importingDisk = false
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
        .interactiveDismissDisabled(step == .progress || importingDisk)
        .errorAlert($errorMessage)
    }


    private var chooseSourceView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("เลือก Linux ที่จะติดตั้ง", "Choose a Linux to install"))
                .font(.title2.bold())

            ForEach(DistroCatalog.all) { distro in
                SourceCard(
                    title: distro.name,
                    subtitle: distro.summary,
                    detail: ImageStore.cachedDisk(for: distro) != nil
                        ? tr("ดาวน์โหลดไว้แล้ว — สร้างได้ทันที", "Already downloaded. Ready to create right away")
                        : tr("ติดตั้งอัตโนมัติ · ดาวน์โหลดประมาณ \(distro.approximateDownloadMB) MB", "Automatic install · about \(distro.approximateDownloadMB) MB download"),
                    systemImage: "sparkles",
                    isSelected: source == .distro(distro)
                ) {
                    source = .distro(distro)
                    name = distro.shortName
                    if !distro.desktops.contains(desktop) { desktop = distro.desktops[0] }
                }
            }

            SourceCard(
                title: tr("ติดตั้งเองจากไฟล์ ISO หรือ IMG", "Install from an ISO or IMG file"),
                subtitle: tr("ใช้ไฟล์ติดตั้ง หรือไฟล์ดิสก์ .img ARM64 ของ distro ไหนก็ได้ เช่น Ubuntu, Fedora, Armbian", "Use an ARM64 installer or .img disk file from any distro, such as Ubuntu, Fedora or Armbian"),
                detail: tr("สำหรับผู้ที่คุ้นเคย ต้องกดติดตั้งเองตามขั้นตอนของ distro", "For experienced users. You go through the distro installer yourself"),
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
                    Text(tr("ชุดโปรแกรม", "Software set"))
                } footer: {
                    if preset != .basic {
                        Text(tr("ติดตั้งระหว่างตั้งค่าครั้งแรก ใช้เวลาและเน็ตเพิ่มขึ้น — โปรแกรมที่ distro นี้ไม่มีจะถูกข้ามไป", "Installed during first-time setup, which takes more time and data. Programs this distro lacks are skipped."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(tr("เครื่อง", "Machine")) {
                TextField(tr("ชื่อเครื่อง", "Machine name"), text: $name)
                Stepper(tr("CPU: \(cpuCount) คอร์", "CPU: \(cpuCount) cores"), value: $cpuCount, in: 1...max(1, maxCPU))
                Stepper("RAM: \(memoryGB) GB", value: $memoryGB, in: 2...maxMemoryGB)
                Stepper(tr("ดิสก์: \(diskGB) GB", "Disk: \(diskGB) GB"), value: $diskGB, in: 16...1024, step: 8)
            }

            if source == .customISO {
                Section(tr("ไฟล์ติดตั้ง", "Installer file")) {
                    LabeledContent(tr("ไฟล์ ISO / IMG (ARM64)", "ISO / IMG file (ARM64)")) {
                        HStack {
                            Text(isoPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? tr("ยังไม่ได้เลือก", "None selected"))
                                .foregroundStyle(isoPath == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(tr("เลือกไฟล์…", "Choose File…")) { showingISOPicker = true }
                        }
                    }
                    .fileImporter(
                        isPresented: $showingISOPicker,
                        allowedContentTypes: ["iso", "img", "raw", "qcow2"].compactMap { UTType(filenameExtension: $0) } + [.diskImage]
                    ) { result in
                        if case .success(let url) = result {
                            let accessing = url.startAccessingSecurityScopedResource()
                            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                            isoPath = url.path
                            isoBookmark = SecurityScopedBookmark.make(for: url)
                            isoKind = DiskImageKind.detect(at: url)
                            useImageAsDisk = isoKind != .iso
                        }
                    }
                    if isoPath != nil {
                        if isoKind == .qcow2 {
                            Text(tr("ไฟล์ qcow2 จะถูกแปลงเป็นดิสก์ของเครื่อง แล้วบูตจากดิสก์นั้นเลย", "The qcow2 file is converted into the machine disk and the machine boots from it"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if isoKind == .raw || isoPath.map({ URL(fileURLWithPath: $0).pathExtension.lowercased() != "iso" }) == true {
                            Picker(tr("ใช้ไฟล์นี้เป็น", "Use this file as"), selection: $useImageAsDisk) {
                                Text(tr("แผ่นติดตั้ง (เหมือน ISO)", "Installer disc (like an ISO)")).tag(false)
                                Text(tr("ดิสก์ของเครื่อง (บูตได้เลย)", "Machine disk (boots directly)")).tag(true)
                            }
                            .pickerStyle(.radioGroup)
                            Text(useImageAsDisk
                                 ? tr("คัดลอกไฟล์เป็นดิสก์ของเครื่องแล้วขยายเป็น \(diskGB) GB ไฟล์ต้นฉบับไม่ถูกแก้ ใช้กับไฟล์ดิสก์ที่บูตด้วย UEFI ได้ เช่น Armbian, Debian raw", "Copies the file as the machine disk and grows it to \(diskGB) GB. The original file is not changed. Works with UEFI-bootable disk files such as Armbian or Debian raw")
                                 : tr("ต่อไฟล์เข้าเครื่องเป็น USB แบบอ่านอย่างเดียว ใช้กับไฟล์ติดตั้งแบบ live USB", "Attaches the file as a read-only USB drive. Use this for live USB installers"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                if case .distro(let distro) = source, distro.desktops.count > 1 {
                    Section(tr("หน้าจอ desktop", "Desktop")) {
                        Picker(tr("หน้าจอ desktop", "Desktop"), selection: $desktop) {
                            ForEach(distro.desktops) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }

                Section(tr("บัญชีผู้ใช้ใน Linux", "Linux user account")) {
                    TextField(tr("ชื่อผู้ใช้ (ภาษาอังกฤษตัวเล็ก)", "Username (lowercase English)"), text: $username)
                    if !username.isEmpty && !GuestSetupOptions.isValidUsername(username) {
                        Text(tr("ใช้ได้เฉพาะ a-z, 0-9, _ และ - และต้องขึ้นต้นด้วยตัวอักษร", "Only a-z, 0-9, _ and - are allowed, and it must start with a letter"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    SecureField(tr("รหัสผ่าน", "Password"), text: $password)
                    SecureField(tr("ยืนยันรหัสผ่าน", "Confirm password"), text: $confirmPassword)
                    if !confirmPassword.isEmpty && password != confirmPassword {
                        Text(tr("รหัสผ่านไม่ตรงกัน", "Passwords do not match"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Toggle(tr("เข้าระบบอัตโนมัติ (ไม่ต้องใส่รหัสตอนเปิดเครื่อง)", "Log in automatically (no password at startup)"), isOn: $autologin)
                }

                Section(tr("ภาษาไทย", "Thai language")) {
                    Toggle(
                        desktop == .gnome
                            ? tr("คีย์บอร์ดไทย (สลับภาษาด้วย Cmd + Space)", "Thai keyboard (switch with Cmd + Space)")
                            : tr("คีย์บอร์ดไทย (สลับภาษาด้วย Option + Shift)", "Thai keyboard (switch with Option + Shift)"),
                        isOn: $thaiKeyboard
                    )
                    Toggle(tr("เมนูภาษาไทย", "Thai menus in Linux"), isOn: $thaiInterface)
                    Text(tr("ฟอนต์ไทยติดตั้งให้เสมอ", "Thai fonts are always installed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(tr("เชื่อมกับ Mac", "Connect with the Mac")) {
                LabeledContent(tr("โฟลเดอร์แชร์", "Shared folder")) {
                    HStack {
                        Text(sharedFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? tr("ไม่แชร์", "Not shared"))
                            .foregroundStyle(sharedFolderPath == nil ? .secondary : .primary)
                        if sharedFolderPath != nil {
                            Button(tr("ยกเลิก", "Cancel")) {
                                sharedFolderPath = nil
                                sharedFolderBookmark = nil
                            }
                        }
                        Button(tr("เลือก…", "Choose…")) { showingFolderPicker = true }
                    }
                }
                .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        sharedFolderPath = url.path
                        sharedFolderBookmark = SecurityScopedBookmark.make(for: url)
                    }
                }
                if source != .customISO {
                    Text(tr("ใน Linux จะเห็นโฟลเดอร์นี้ที่ ~/Mac", "In Linux this folder appears at ~/Mac"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if rosettaAvailability != .notSupported {
                    Toggle(tr("รันโปรแกรม x86_64 ผ่าน Rosetta", "Run x86_64 programs with Rosetta"), isOn: $rosetta)
                    if rosetta && rosettaAvailability == .notInstalled {
                        Text(tr("macOS จะขอติดตั้ง Rosetta ก่อนสร้างเครื่อง", "macOS will ask to install Rosetta before creating the machine"))
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
                Text(tr("สร้างเครื่องเสร็จแล้ว", "Machine created"))
                    .font(.title2.bold())
                Text(tr("กด \"เปิดเครื่อง\" ได้เลย ครั้งแรก Linux จะติดตั้งหน้าจอและภาษาไทยเอง ใช้เวลาประมาณ 10–30 นาที (ต้องต่ออินเทอร์เน็ต) ดูความคืบหน้าได้ที่แถบด้านล่างของหน้าจอ เสร็จแล้วจะเข้าหน้าจอ desktop ให้อัตโนมัติ", "Click \"Start\". The first time, Linux sets up the desktop and language by itself, which takes about 10–30 minutes (internet required). Progress shows in the bar at the bottom of the screen, and the desktop opens automatically when it is done."))
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
                Button(tr("ยกเลิก", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(tr("ถัดไป", "Next")) { step = .configure }
                    .keyboardShortcut(.defaultAction)

            case .configure:
                Button(tr("ย้อนกลับ", "Back")) { step = .chooseSource }
                    .disabled(importingDisk)
                Spacer()
                if importingDisk {
                    ProgressView().controlSize(.small)
                    Text(tr("กำลังเตรียมดิสก์…", "Preparing the disk…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(source == .customISO ? tr("สร้างเครื่อง", "Create Machine") : tr("ติดตั้ง", "Install")) { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || importingDisk)

            case .progress:
                switch provisioner.phase {
                case .finished:
                    Spacer()
                    Button(tr("เสร็จ", "Done")) { finish(start: false) }
                    Button(tr("เปิดเครื่อง", "Start")) { finish(start: true) }
                        .keyboardShortcut(.defaultAction)
                case .failed:
                    Button(tr("ปิด", "Close")) { dismiss() }
                    Spacer()
                    Button(tr("ย้อนกลับไปแก้ไข", "Go Back and Edit")) { step = .configure }
                        .keyboardShortcut(.defaultAction)
                default:
                    Spacer()
                    Text(tr("ปิดหน้าต่างนี้ไม่ได้ระหว่างติดตั้ง", "This window cannot be closed during installation"))
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
            config.rosettaEnabled = rosetta && rosettaAvailability == .installed
            if useImageAsDisk, let isoPath {
                let image = isoBookmark.flatMap { SecurityScopedBookmark.resolve($0)?.url } ?? URL(fileURLWithPath: isoPath)
                let kind = isoKind
                let pending = config
                importingDisk = true
                Task {
                    let result = await Task.detached(priority: .userInitiated) {
                        Result { try MachineBundle.create(config: pending, importing: image, kind: kind) }
                    }.value
                    importingDisk = false
                    switch result {
                    case .success(let (bundle, saved)):
                        let controller = MachineController(bundle: bundle, config: saved)
                        library.add(controller)
                        onCreated(controller)
                        dismiss()
                    case .failure(let error):
                        errorMessage = tr("สร้างเครื่องไม่สำเร็จ: \(error.localizedDescription)", "Could not create the machine: \(error.localizedDescription)")
                    }
                }
                return
            }
            config.installerISOPath = isoPath
            config.installerISOBookmark = isoBookmark
            do {
                let bundle = try MachineBundle.create(config: config)
                let controller = MachineController(bundle: bundle, config: config)
                library.add(controller)
                onCreated(controller)
                dismiss()
            } catch {
                errorMessage = tr("สร้างเครื่องไม่สำเร็จ: \(error.localizedDescription)", "Could not create the machine: \(error.localizedDescription)")
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
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
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
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
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
