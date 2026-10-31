import AppKit
import SwiftUI
import Virtualization

struct SeamlessToggle: View {
    @ObservedObject var session: SeamlessSession
    @State private var showingInstallHelp = false

    var body: some View {
        if session.isConnected {
            HStack(spacing: 4) {
                Toggle(isOn: Binding(get: { session.isEnabled }, set: { session.setEnabled($0) })) {
                    Label("หน้าต่างแยก", systemImage: "macwindow.on.rectangle")
                }
                .toggleStyle(.button)
                .help("เปิดแอพ Linux เป็นหน้าต่างแยกบน Mac")

                if session.agentNeedsUpdate {
                    Button {
                        showingInstallHelp = true
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help("มี LinMO Agent รุ่นใหม่ — คลิกเพื่อดูวิธีอัปเดต")
                    .popover(isPresented: $showingInstallHelp, arrowEdge: .bottom) {
                        AgentInstallHelp(isUpdate: true)
                    }
                }
            }
        } else {
            Button {
                showingInstallHelp = true
            } label: {
                Label("หน้าต่างแยก", systemImage: "macwindow.on.rectangle")
            }
            .help("ยังไม่พบ LinMO Agent ใน Linux — คลิกเพื่อดูวิธีติดตั้ง")
            .popover(isPresented: $showingInstallHelp, arrowEdge: .bottom) {
                AgentInstallHelp()
            }
        }
    }
}

struct AgentInstallHelp: View {
    var isUpdate = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isUpdate ? "อัปเดต LinMO Agent" : "ยังไม่พบ LinMO Agent")
                .font(.headline)
            Text(isUpdate
                 ? "agent ใน Linux เป็นรุ่นเก่า รุ่นใหม่ทำให้หน้าต่างลื่นขึ้น คมชัดบน Retina พิมพ์ไทยด้วยแป้นพิมพ์ Mac และลากไฟล์มาวางได้ เปิด Terminal ใน Linux แล้ววางคำสั่งนี้:"
                 : "โหมดหน้าต่างแยกต้องใช้ LinMO Agent ใน Linux เครื่องที่สร้างด้วยตัวช่วยติดตั้งตั้งแต่ v0.4 จะมีให้แล้ว ถ้ายังไม่มี ให้เปิด Terminal ใน Linux แล้ววางคำสั่งนี้:")
                .fixedSize(horizontal: false, vertical: true)
            Text(GuestTools.installCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(copied ? "คัดลอกแล้ว" : "คัดลอกคำสั่ง") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(GuestTools.installCommand, forType: .string)
                    copied = true
                }
                Spacer()
            }
            Text("ติดตั้งเสร็จแล้วให้ออกจากระบบแล้วเข้าใหม่ใน Linux ต้องใช้หน้าจอแบบ X11 (XFCE หรือ GNOME on Xorg)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 440)
    }
}

struct FullScreenButton: View {
    @ObservedObject var session: SeamlessSession

    var body: some View {
        if !session.isEnabled {
            Button {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
            } label: {
                Label("เต็มจอ", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("แสดง Linux เต็มจอ (Ctrl+Cmd+F)")
        }
    }
}

struct RunningDisplay: View {
    let vm: VZVirtualMachine
    @ObservedObject var seamless: SeamlessSession

    var body: some View {
        if seamless.isEnabled {
            SeamlessLauncherView(session: seamless)
        } else {
            VMDisplayView(machine: vm)
        }
    }
}

struct SeamlessLauncherView: View {
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
                Text("โหมดหน้าต่างแยก")
                    .font(.title2.bold())
                Text("แอพ Linux จะเปิดเป็นหน้าต่างของตัวเองบน Mac เลือกแอพด้านล่างเพื่อเปิด หรือกดปุ่ม \"หน้าต่างแยก\" อีกครั้งเพื่อกลับไปดูหน้าจอ Linux ทั้งจอ")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("ค้นหาแอพ", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 6)
            }
            .padding(20)

            Divider()

            if session.apps.isEmpty {
                Text("กำลังโหลดรายการแอพ…")
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
            }
        }
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
