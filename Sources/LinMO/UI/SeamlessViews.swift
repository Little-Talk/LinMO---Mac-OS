import AppKit
import SwiftUI
import Virtualization

struct SeamlessToggle: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
    @ObservedObject var session: SeamlessSession
    @State private var showingInstallHelp = false

    var body: some View {
        if session.isConnected {
            HStack(spacing: 4) {
                Toggle(isOn: Binding(get: { session.isEnabled }, set: { session.setEnabled($0) })) {
                    Label(tr("หน้าต่างแยก", "Separate Windows"), systemImage: "macwindow.on.rectangle")
                }
                .toggleStyle(.button)
                .help(tr("เปิดแอพ Linux เป็นหน้าต่างแยกบน Mac", "Open Linux apps as separate Mac windows"))

                if session.agentNeedsUpdate {
                    Button {
                        showingInstallHelp = true
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help(tr("มี LinMO Agent รุ่นใหม่ — คลิกเพื่อดูวิธีอัปเดต", "A new LinMO Agent is available. Click to see how to update"))
                    .popover(isPresented: $showingInstallHelp, arrowEdge: .bottom) {
                        AgentInstallHelp(isUpdate: true)
                    }
                }
            }
        } else {
            Button {
                showingInstallHelp = true
            } label: {
                Label(tr("หน้าต่างแยก", "Separate Windows"), systemImage: "macwindow.on.rectangle")
            }
            .help(tr("ยังไม่พบ LinMO Agent ใน Linux — คลิกเพื่อดูวิธีติดตั้ง", "LinMO Agent was not found in Linux. Click to see how to install it"))
            .popover(isPresented: $showingInstallHelp, arrowEdge: .bottom) {
                AgentInstallHelp()
            }
        }
    }
}

struct AgentInstallHelp: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
    var isUpdate = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isUpdate ? tr("อัปเดต LinMO Agent", "Update LinMO Agent") : tr("ยังไม่พบ LinMO Agent", "LinMO Agent not found"))
                .font(.headline)
            Text(isUpdate
                 ? tr("agent ใน Linux เป็นรุ่นเก่า รุ่นใหม่ทำให้หน้าต่างลื่นขึ้น คมชัดบน Retina พิมพ์ไทยด้วยแป้นพิมพ์ Mac ลากไฟล์มาวางได้ และไฟล์ในโฟลเดอร์แชร์อัปเดตเองทันที เปิด Terminal ใน Linux แล้ววางคำสั่งนี้:", "The agent in Linux is out of date. The new one gives smoother windows, sharp Retina text, typing with the Mac keyboard, file drag and drop, and instant shared folder updates. Open Terminal in Linux and paste this command:")
                 : tr("โหมดหน้าต่างแยกต้องใช้ LinMO Agent ใน Linux เครื่องที่สร้างด้วยตัวช่วยติดตั้งตั้งแต่ v0.4 จะมีให้แล้ว ถ้ายังไม่มี ให้เปิด Terminal ใน Linux แล้ววางคำสั่งนี้:", "Separate windows mode needs LinMO Agent in Linux. Machines created with the setup assistant since v0.4 already have it. If not, open Terminal in Linux and paste this command:"))
                .fixedSize(horizontal: false, vertical: true)
            Text(GuestTools.installCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(copied ? tr("คัดลอกแล้ว", "Copied") : tr("คัดลอกคำสั่ง", "Copy Command")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(GuestTools.installCommand, forType: .string)
                    copied = true
                }
                Spacer()
            }
            Text(tr("ติดตั้งเสร็จแล้วให้ออกจากระบบแล้วเข้าใหม่ใน Linux ต้องใช้หน้าจอแบบ X11 (XFCE หรือ GNOME on Xorg) ทำแค่ครั้งเดียว ต่อจากนี้เมื่อ LinMO มีรุ่นใหม่ แค่ปิดแล้วเปิดเครื่อง Linux ใหม่ agent จะอัปเดตเอง", "When it finishes, log out and back in to Linux. This needs an X11 desktop (XFCE or GNOME on Xorg) and only has to be done once. After that, when LinMO has a new version, just restart the Linux machine and the agent updates itself."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 440)
    }
}

struct WineInstallButton: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
    let rosettaEnabled: Bool
    @State private var showing = false
    @State private var copied = false
    @State private var hangover = true

    private var command: String { GuestTools.wineInstallCommand(hangover: hangover) }

    var body: some View {
        Button {
            copied = false
            showing = true
        } label: {
            Label("Wine", systemImage: "wineglass")
        }
        .help(tr("ติดตั้ง Wine เพื่อเปิดโปรแกรม Windows ใน Linux", "Install Wine to run Windows programs in Linux"))
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("ติดตั้ง Wine", "Install Wine"))
                    .font(.headline)
                Picker("", selection: $hangover) {
                    Text("Hangover").tag(true)
                    Text("WineHQ + Rosetta").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: hangover) { copied = false }
                Text(hangover
                     ? tr("เปิดโปรแกรม Windows ได้ทั้ง 32 และ 64 บิต ไม่ต้องใช้ Rosetta แนะนำสำหรับโปรแกรมส่วนใหญ่", "Runs both 32-bit and 64-bit Windows programs without Rosetta. Recommended for most programs")
                     : tr("เร็วกว่า แต่เปิดได้เฉพาะโปรแกรม Windows 64 บิต ต้องเปิด Rosetta ในตั้งค่าเครื่อง", "Faster, but only runs 64-bit Windows programs. Needs Rosetta turned on in Machine Settings"))
                    .fixedSize(horizontal: false, vertical: true)
                if !hangover && !rosettaEnabled {
                    Text(tr("ยังไม่ได้เปิด Rosetta ให้ปิดเครื่อง เปิด \"รันโปรแกรม x86_64 ผ่าน Rosetta\" ในตั้งค่าเครื่อง แล้วเปิดเครื่องและกดปุ่มนี้อีกครั้ง", "Rosetta is off. Shut down the machine, turn on \"Run x86_64 programs with Rosetta\" in Machine Settings, then start the machine and click this button again."))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(tr("รองรับ Debian และ Ubuntu เปิด Terminal ใน Linux แล้ววางคำสั่งนี้ ติดตั้งได้ทีละแบบ ถ้าลงอีกแบบไว้แล้วจะถูกถอดออกให้", "Works on Debian and Ubuntu. Open Terminal in Linux and paste this command. Only one kind can be installed at a time, and the other kind is removed if present."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    HStack {
                        Button(copied ? tr("คัดลอกแล้ว", "Copied") : tr("คัดลอกคำสั่ง", "Copy Command")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            copied = true
                        }
                        Spacer()
                    }
                    Text(tr("ติดตั้งเสร็จแล้วดับเบิลคลิกไฟล์ .exe หรือพิมพ์ wine ชื่อไฟล์.exe ใน Terminal", "When it finishes, double-click an .exe file or type wine filename.exe in Terminal"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(width: 440)
        }
    }
}

struct FullScreenButton: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
    @ObservedObject var session: SeamlessSession

    var body: some View {
        if !session.isEnabled {
            Button {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
            } label: {
                Label(tr("เต็มจอ", "Full Screen"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help(tr("แสดง Linux เต็มจอ (Ctrl+Cmd+F)", "Show Linux full screen (Ctrl+Cmd+F)"))
        }
    }
}

struct RunningDisplay: View {
    let controller: MachineController
    let vm: VZVirtualMachine
    @ObservedObject var seamless: SeamlessSession

    var body: some View {
        if seamless.isEnabled {
            SeamlessLauncherView(session: seamless)
        } else {
            VMDisplayView(controller: controller, machine: vm)
        }
    }
}

struct SeamlessLauncherView: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
    @ObservedObject var session: SeamlessSession
    @State private var search = ""

    private var filtered: [SeamlessSession.App] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return session.apps }
        return session.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.generic ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("โหมดหน้าต่างแยก", "Separate windows mode"))
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        session.setEnabled(false)
                    } label: {
                        Label(tr("กลับไปหน้าจอ Linux", "Back to Linux Desktop"), systemImage: "chevron.backward")
                    }
                    .help(tr("ปิดโหมดหน้าต่างแยก แล้วกลับไปดูหน้าจอ Linux ทั้งจอ", "Turn off separate windows and go back to the full Linux desktop"))
                }
                Text(tr("แอพ Linux จะเปิดเป็นหน้าต่างของตัวเองบน Mac เลือกแอพด้านล่างเพื่อเปิด หรือกดปุ่ม \"กลับไปหน้าจอ Linux\" เพื่อกลับไปดูหน้าจอ Linux ทั้งจอ", "Linux apps open in their own Mac windows. Pick an app below to open it, or click \"Back to Linux Desktop\" to return to the full Linux desktop."))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                TextField(tr("ค้นหาแอพ", "Search apps"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 6)
            }
            .padding(20)

            Divider()

            if session.apps.isEmpty {
                Text(tr("กำลังโหลดรายการแอพ…", "Loading apps…"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { app in
                    Button {
                        session.launch(app)
                    } label: {
                        HStack(spacing: 12) {
                            AppIcon(app: app, fallback: icon(for: app))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                if let generic = app.generic, !generic.isEmpty {
                                    Text(generic)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func icon(for app: SeamlessSession.App) -> String {
        let categories = Set(app.categories ?? [])
        if categories.contains("TerminalEmulator") { return "terminal" }
        if categories.contains("WebBrowser") { return "globe" }
        if categories.contains("Development") { return "chevron.left.forwardslash.chevron.right" }
        if categories.contains("Graphics") { return "paintpalette" }
        if categories.contains("Office") { return "doc.text" }
        if categories.contains("AudioVideo") || categories.contains("Audio") || categories.contains("Video") { return "play.rectangle" }
        if categories.contains("Game") { return "gamecontroller" }
        if categories.contains("Settings") || categories.contains("System") { return "gearshape" }
        if categories.contains("FileManager") { return "folder" }
        return "app"
    }
}

private struct AppIcon: View {
    let app: SeamlessSession.App
    let fallback: String

    private static var cache: [String: NSImage] = [:]

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: fallback)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
    }

    private var image: NSImage? {
        if let cached = Self.cache[app.id] { return cached }
        guard let encoded = app.icon, let data = Data(base64Encoded: encoded),
              let image = NSImage(data: data), image.isValid else { return nil }
        Self.cache[app.id] = image
        return image
    }
}
