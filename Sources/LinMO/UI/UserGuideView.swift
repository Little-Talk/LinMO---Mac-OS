import AppKit
import SwiftUI

enum GuideLanguage: String, CaseIterable, Identifiable {
    case thai = "th"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thai: "ไทย"
        case .english: "English"
        }
    }

    static var systemDefault: GuideLanguage {
        let preferred = Locale.preferredLanguages.first ?? ""
        return preferred.hasPrefix("th") ? .thai : .english
    }

}

struct GuideText {
    let th: String
    let en: String

    init(_ th: String, _ en: String) {
        self.th = th
        self.en = en
    }

    func callAsFunction(_ language: GuideLanguage) -> String {
        language == .thai ? th : en
    }
}

enum GuideBlock {
    case paragraph(GuideText)
    case steps([GuideText])
    case bullets([GuideText])
    case note(GuideText)
    case code(String)
    case heading(GuideText)
}

struct GuideTopic: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: GuideText
    let blocks: [GuideBlock]

    static func == (lhs: GuideTopic, rhs: GuideTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct UserGuideCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(GuideLanguage.systemDefault == .thai ? "วิธีใช้ LinMO" : "LinMO Help") {
                openWindow(id: "guide")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct UserGuideView: View {
    @AppStorage("guideLanguage") private var languageRaw = GuideLanguage.systemDefault.rawValue
    @State private var selection: String? = UserGuide.topics.first?.id

    private var language: GuideLanguage {
        GuideLanguage(rawValue: languageRaw) ?? .thai
    }

    var body: some View {
        NavigationSplitView {
            List(UserGuide.topics, selection: $selection) { topic in
                Label(topic.title(language), systemImage: topic.icon)
                    .tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            if let topic = UserGuide.topics.first(where: { $0.id == selection }) {
                GuideTopicView(topic: topic, language: language)
                    .id("\(topic.id)-\(language.rawValue)")
            } else {
                Text(language == .thai ? "เลือกหัวข้อจากรายการด้านซ้าย" : "Choose a topic from the list")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(language == .thai ? "คู่มือการใช้งาน LinMO" : "LinMO User Guide")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: $languageRaw) {
                    ForEach(GuideLanguage.allCases) { lang in
                        Text(lang.label).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(language == .thai ? "เปลี่ยนภาษาของคู่มือ" : "Change the guide language")
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct GuideTopicView: View {
    let topic: GuideTopic
    let language: GuideLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(topic.title(language), systemImage: topic.icon)
                    .font(.largeTitle.weight(.semibold))
                    .padding(.bottom, 4)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func blockView(_ block: GuideBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text(language))
                .font(.title3.weight(.semibold))
                .padding(.top, 8)
        case .paragraph(let text):
            Text(markdown(text(language)))
                .fixedSize(horizontal: false, vertical: true)
        case .steps(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.callout.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.accentColor))
                        Text(markdown(item(language)))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(markdown(item(language)))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .note(let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.orange)
                Text(markdown(text(language)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        case .code(let command):
            GuideCodeBlock(command: command, language: language)
        }
    }

    private func markdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }
}

private struct GuideCodeBlock: View {
    let command: String
    let language: GuideLanguage
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Button(copied
                   ? (language == .thai ? "คัดลอกแล้ว" : "Copied")
                   : (language == .thai ? "คัดลอกคำสั่ง" : "Copy command")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            }
            .controlSize(.small)
        }
    }
}

enum UserGuide {
    static let topics: [GuideTopic] = [
        GuideTopic(
            id: "welcome",
            icon: "hand.wave",
            title: GuideText("เริ่มต้นใช้งาน", "Getting started"),
            blocks: [
                .paragraph(GuideText(
                    "LinMO ให้คุณใช้ Linux บน Mac ได้ง่ายๆ และเปิดแอพ Linux เป็นหน้าต่างแยกบน Mac เหมือนแอพทั่วไป copy-paste ข้อความและรูปภาพ ลากไฟล์เข้าออกกับ Finder และเปิดแอพ Linux จาก Spotlight หรือ Launchpad ได้",
                    "LinMO makes it easy to run Linux on your Mac and open each Linux app in its own Mac window, just like a regular app. You can copy and paste text and images, drag files to and from Finder, and open Linux apps from Spotlight or Launchpad."
                )),
                .heading(GuideText("สิ่งที่ต้องมี", "Requirements")),
                .bullets([
                    GuideText("Mac ชิป Apple (M1 ขึ้นไป)", "A Mac with Apple silicon (M1 or later)"),
                    GuideText("macOS 14 Sonoma ขึ้นไป", "macOS 14 Sonoma or later"),
                    GuideText("อินเทอร์เน็ต สำหรับติดตั้งแบบคลิกเดียว", "An internet connection for one-click setup"),
                    GuideText("พื้นที่ว่างประมาณ 40 GB ต่อเครื่อง", "About 40 GB of free space per machine")
                ]),
                .heading(GuideText("ขั้นตอนโดยย่อ", "Quick start")),
                .steps([
                    GuideText("กด **+** (สร้างเครื่องใหม่) แล้วเลือก Linux ที่ต้องการ", "Click **+** (New Machine) and pick a Linux distribution."),
                    GuideText("ตั้งชื่อผู้ใช้และรหัสผ่าน แล้วกด **ติดตั้ง**", "Set a user name and password, then click **ติดตั้ง** (Install)."),
                    GuideText("กด **เปิดเครื่อง** และรอการตั้งค่าครั้งแรก", "Click **เปิดเครื่อง** (Start) and wait for first-boot setup to finish."),
                    GuideText("กด **หน้าต่างแยก** เพื่อเปิดแอพ Linux เป็นหน้าต่าง Mac", "Click **หน้าต่างแยก** (Separate Windows) to open Linux apps as Mac windows.")
                ]),
                .note(GuideText(
                    "เปิดคู่มือนี้ได้ทุกเมื่อจากเมนู **วิธีใช้ → วิธีใช้ LinMO** หรือกด **Cmd + ?**",
                    "Open this guide any time from **Help → LinMO Help** or press **Cmd + ?**."
                ))
            ]
        ),
        GuideTopic(
            id: "create",
            icon: "plus.circle",
            title: GuideText("สร้างเครื่อง Linux", "Create a Linux machine"),
            blocks: [
                .heading(GuideText("แบบคลิกเดียว (แนะนำ)", "One-click setup (recommended)")),
                .steps([
                    GuideText("กด **+** แล้วเลือก **Debian**, **Ubuntu** หรือ **Fedora** แล้วกด **ถัดไป**", "Click **+**, choose **Debian**, **Ubuntu** or **Fedora**, then click **ถัดไป** (Next)."),
                    GuideText("เลือกชุดโปรแกรม: พื้นฐาน, สายเรียน Linux, สาย dev, สาย security lab, สาย data science หรือสายออกแบบ", "Pick a software set: Basic, Learn Linux, Developer, Security lab, Data science or Design."),
                    GuideText("เลือกหน้าจอ **XFCE** (เบา) หรือ **GNOME** (Debian, Ubuntu)", "Pick a desktop: **XFCE** (lightweight) or **GNOME** (Debian, Ubuntu)."),
                    GuideText("ตั้งชื่อผู้ใช้ รหัสผ่าน เลือกเข้าระบบอัตโนมัติและเมนูภาษาไทยได้ แล้วเลือกโฟลเดอร์ Mac ที่จะแชร์ (ไม่บังคับ)", "Set a user name and password, optionally turn on automatic login and a Thai interface, and choose a Mac folder to share (optional)."),
                    GuideText("เปิด **รันโปรแกรม x86_64 ผ่าน Rosetta** ถ้าต้องการใช้โปรแกรม Intel", "Turn on **รันโปรแกรม x86_64 ผ่าน Rosetta** (Run x86_64 programs with Rosetta) if you need Intel programs."),
                    GuideText("กด **ติดตั้ง** แล้วรอดาวน์โหลด (ครั้งแรกประมาณ 450–600 MB ครั้งต่อไปใช้ไฟล์เดิมได้ทันที)", "Click **ติดตั้ง** (Install) and wait for the download (about 450–600 MB the first time; later machines reuse the cached file)."),
                    GuideText("กด **เปิดเครื่อง** ครั้งแรก Linux จะติดตั้งหน้าจอและภาษาไทยเอง ใช้เวลาประมาณ 10–30 นาที ดูความคืบหน้าได้ที่แถบด้านล่าง เมื่อเสร็จแอพจะเปิดเครื่องใหม่เข้าหน้าจอ desktop ให้เอง", "Click **เปิดเครื่อง** (Start). On first boot Linux installs the desktop and Thai support by itself, which takes about 10–30 minutes. Watch the progress bar at the bottom. When it finishes, the app restarts the machine into the desktop.")
                ]),
                .paragraph(GuideText(
                    "เมื่อตั้งค่าครั้งแรกเสร็จ LinMO บันทึก snapshot ชื่อ **หลังติดตั้งเสร็จ** ไว้ให้ ย้อนกลับมาเป็นเครื่องใหม่เอี่ยมได้ทุกเมื่อ",
                    "When first-boot setup finishes, LinMO saves a snapshot named **หลังติดตั้งเสร็จ** (After setup), so you can always go back to a fresh machine."
                )),
                .note(GuideText(
                    "Fedora มีให้เฉพาะ XFCE เพราะ GNOME ของ Fedora รุ่นใหม่ใช้ Wayland อย่างเดียว",
                    "Fedora offers XFCE only, because recent Fedora GNOME is Wayland-only."
                )),
                .heading(GuideText("ติดตั้งเองจากไฟล์ ISO หรือดิสก์", "Install from an ISO or disk image")),
                .steps([
                    GuideText("กด **+** แล้วเลือก **ติดตั้งเองจากไฟล์ ISO หรือ IMG** และเลือกไฟล์รุ่น **ARM64 / aarch64**", "Click **+**, choose **ติดตั้งเองจากไฟล์ ISO หรือ IMG** (Install from ISO or IMG file), and pick an **ARM64 / aarch64** file."),
                    GuideText("เปิดเครื่อง ถ้าเป็นแผ่นติดตั้งให้ติดตั้งตามขั้นตอนของ distro", "Start the machine. If the file is an installer, follow the distribution's installer."),
                    GuideText("ติดตั้งเสร็จ ปิดเครื่อง กด **ถอดแผ่นติดตั้ง** แล้วเปิดเครื่องใหม่", "When done, shut down, click **ถอดแผ่นติดตั้ง** (Eject Installer), and start the machine again.")
                ]),
                .bullets([
                    GuideText("`.iso` ใช้เป็นแผ่นติดตั้ง", "`.iso` is used as an installer disc."),
                    GuideText("`.img` หรือ `.raw` เลือกได้ว่าจะใช้เป็น **แผ่นติดตั้ง** (เหมือน live USB) หรือ **ดิสก์ของเครื่อง** ที่บูตได้เลย เช่นไฟล์ของ Armbian", "`.img` or `.raw` can be used as an **installer** (like a live USB) or as the machine's **disk** that boots right away, such as an Armbian image."),
                    GuideText("`.qcow2` จะถูกแปลงเป็นดิสก์ของเครื่องแล้วบูตได้เลย", "`.qcow2` is converted into the machine's disk and boots right away."),
                    GuideText("ไฟล์ต้นฉบับไม่ถูกแก้ ดิสก์ของเครื่องจะถูกขยายเป็นขนาดที่ตั้งไว้", "The original file is never changed. The machine's disk is grown to the size you set.")
                ]),
                .paragraph(GuideText(
                    "เครื่องที่ติดตั้งจาก ISO ต้องติดตั้ง LinMO Agent เอง ดูหัวข้อ **LinMO Agent และ LinMO Tools**",
                    "Machines installed from an ISO need LinMO Agent installed by hand. See **LinMO Agent and LinMO Tools**."
                ))
            ]
        ),
        GuideTopic(
            id: "run",
            icon: "power",
            title: GuideText("เปิด ปิด และตั้งค่าเครื่อง", "Start, stop and configure"),
            blocks: [
                .bullets([
                    GuideText("**เปิดเครื่อง** / **ปิดเครื่อง** อยู่ที่แถบด้านบนของเครื่อง ถ้า Linux ไม่ตอบสนองให้ใช้ **บังคับปิด**", "**เปิดเครื่อง** (Start) and **ปิดเครื่อง** (Shut Down) are in the machine's toolbar. If Linux stops responding, use **บังคับปิด** (Force Stop)."),
                    GuideText("**เต็มจอ** (Ctrl + Cmd + F) แสดงหน้าจอ Linux เต็มจอ Mac", "**เต็มจอ** (Full Screen) (Ctrl + Cmd + F) shows the Linux desktop across your whole screen."),
                    GuideText("ปิดแอพ LinMO ขณะเครื่องยังทำงาน แอพจะถามให้ **พักเครื่องแล้วปิดแอพ** ถ้าเลือกปิดเลยจะเป็นการตัดไฟทันที", "If you quit LinMO while a machine is running, it offers **พักเครื่องแล้วปิดแอพ** (Suspend and Quit). Quitting without suspending cuts the machine's power immediately.")
                ]),
                .heading(GuideText("ตั้งค่าเครื่อง", "Machine settings")),
                .paragraph(GuideText(
                    "ปิดเครื่องก่อน แล้วกดเมนู **…** และ **ตั้งค่าเครื่อง…**",
                    "Shut the machine down, then open the **…** menu and choose **ตั้งค่าเครื่อง…** (Machine Settings…)."
                )),
                .bullets([
                    GuideText("ชื่อเครื่อง, จำนวน CPU, RAM และขนาดดิสก์ (ขยายได้อย่างเดียว ลดไม่ได้)", "Name, CPU cores, memory and disk size (disks can only grow, never shrink)."),
                    GuideText("**รันโปรแกรม x86_64 ผ่าน Rosetta**", "**รันโปรแกรม x86_64 ผ่าน Rosetta** (Run x86_64 programs with Rosetta)"),
                    GuideText("**คมชัดสูงบนจอ Retina** ใช้ความละเอียดเท่าจอ Mac และขยายตัวหนังสือ 2 เท่า", "**คมชัดสูงบนจอ Retina** (High resolution on Retina displays) matches your Mac's resolution and doubles text size."),
                    GuideText("**พิมพ์ด้วยแป้นพิมพ์ของ Mac** สลับไทย/อังกฤษด้วยปุ่มของ Mac ในโหมดหน้าต่างแยก", "**พิมพ์ด้วยแป้นพิมพ์ของ Mac** (Type with the Mac keyboard) lets you switch input languages the Mac way in separate-window mode."),
                    GuideText("**เปิดแอพผ่าน Wayland (ทดลอง)** สำหรับ distro ที่ใช้ Wayland อย่างเดียว", "**เปิดแอพผ่าน Wayland (ทดลอง)** (Open apps through Wayland (experimental)) for Wayland-only distributions."),
                    GuideText("**ให้ Linux ใช้ไมโครโฟนของ Mac** แล้วกดอนุญาตเมื่อ macOS ถาม ถ้าเคยไม่อนุญาต เปิดได้ที่ System Settings → Privacy & Security → Microphone", "**ให้ Linux ใช้ไมโครโฟนของ Mac** (Let Linux use the Mac microphone), then allow access when macOS asks. If you denied it before, turn it on in System Settings → Privacy & Security → Microphone.")
                ]),
                .note(GuideText(
                    "การตั้งค่าส่วนใหญ่มีผลเมื่อเปิดเครื่องครั้งถัดไป",
                    "Most settings take effect the next time the machine starts."
                ))
            ]
        ),
        GuideTopic(
            id: "windows",
            icon: "macwindow.on.rectangle",
            title: GuideText("โหมดหน้าต่างแยก", "Separate windows"),
            blocks: [
                .paragraph(GuideText(
                    "แอพ Linux แต่ละตัวเปิดเป็นหน้าต่างของตัวเองบน Mac คมชัดบนจอ Retina และใช้ Cmd + C / Cmd + V ได้",
                    "Each Linux app opens in its own Mac window, sharp on Retina displays, with Cmd + C / Cmd + V working as usual."
                )),
                .steps([
                    GuideText("เปิดเครื่อง แล้วกดปุ่ม **หน้าต่างแยก** ที่แถบด้านบน", "Start the machine and click **หน้าต่างแยก** (Separate Windows) in the toolbar."),
                    GuideText("คลิกแอพในรายการ แอพจะเปิดเป็นหน้าต่าง Mac หน้าต่างที่เปิดอยู่แล้วใน Linux ก็จะโผล่มาด้วย", "Click an app in the list to open it as a Mac window. Windows already open in Linux appear too."),
                    GuideText("กด **กลับไปหน้าจอ Linux** หรือปุ่ม **หน้าต่างแยก** อีกครั้ง เพื่อกลับไปดูหน้าจอ Linux ทั้งจอ", "Click **กลับไปหน้าจอ Linux** (Back to Linux Desktop), or **หน้าต่างแยก** (Separate Windows) again, to return to the full Linux desktop.")
                ]),
                .heading(GuideText("คีย์บอร์ดและเมาส์", "Keyboard and mouse")),
                .bullets([
                    GuideText("**Cmd** ทำหน้าที่เป็น **Ctrl** เช่น Cmd + C, Cmd + V, Cmd + S", "**Cmd** acts as **Ctrl**, so Cmd + C, Cmd + V and Cmd + S work like on a Mac."),
                    GuideText("**Control + คลิก** = คลิกขวา", "**Control-click** is a right-click."),
                    GuideText("**Cmd + Q** ยังเป็นการปิดแอพ LinMO", "**Cmd + Q** still quits LinMO."),
                    GuideText("พิมพ์ไทย ญี่ปุ่น จีน เกาหลีผ่านระบบพิมพ์ของ Mac ได้ ข้อความที่กำลังเลือกคำจะแสดงที่มุมล่างของหน้าต่าง", "Type Thai, Japanese, Chinese or Korean with your Mac input sources. Text being composed shows at the bottom corner of the window.")
                ]),
                .note(GuideText(
                    "ต้องใช้หน้าจอแบบ X11 (XFCE หรือ GNOME on Xorg ที่ LinMO ตั้งให้) ถ้าเป็น Wayland ให้เปิด **เปิดแอพผ่าน Wayland (ทดลอง)** ในตั้งค่าเครื่อง",
                    "This needs an X11 session (XFCE, or GNOME on Xorg as set up by LinMO). For Wayland, turn on **เปิดแอพผ่าน Wayland (ทดลอง)** (Open apps through Wayland (experimental)) in machine settings."
                )),
                .bullets([
                    GuideText("หน้าต่างแอพปรับขนาดตามหน้าต่าง Mac และไม่เล็กกว่าขนาดที่แอพกำหนด", "App windows follow the Mac window when you resize it, and never shrink below the app's minimum size."),
                    GuideText("ในโหมด Wayland แอพอย่าง Firefox แสดงขนาดถูกต้องบนจอ Retina และคลิกตรงตำแหน่ง", "In Wayland mode, apps such as Firefox show at the right size on Retina displays and clicks land where you point.")
                ])
            ]
        ),
        GuideTopic(
            id: "launch",
            icon: "magnifyingglass",
            title: GuideText("เปิดแอพ Linux จาก Mac", "Open Linux apps from your Mac"),
            blocks: [
                .paragraph(GuideText(
                    "ทุกครั้งที่เปิดเครื่อง LinMO จะจำรายการแอพของเครื่องนั้นไว้ แล้วให้เปิดแอพได้จากทุกที่บน Mac ถ้าเครื่องยังปิดอยู่ LinMO จะเปิดเครื่องให้เอง",
                    "Each time a machine starts, LinMO remembers its apps so you can open them from anywhere on your Mac. If the machine is off, LinMO starts it for you."
                )),
                .bullets([
                    GuideText("**Spotlight** กด Cmd + Space แล้วพิมพ์ชื่อแอพ เช่น Firefox หรือ Terminal", "**Spotlight**: press Cmd + Space and type the app name, such as Firefox or Terminal."),
                    GuideText("**เมนู แอพ Linux** ไอคอนตารางบนแถบเมนู แยกตามเครื่องและหมวดหมู่", "**Linux Apps menu** (แอพ Linux): the grid icon in the menu bar, grouped by machine and category."),
                    GuideText("**Launchpad** เปิดที่ **LinMO → Settings…** แล้วเลือก **ใส่แอพ Linux ใน Launchpad**", "**Launchpad**: turn on **ใส่แอพ Linux ใน Launchpad** (Add Linux apps to Launchpad) in **LinMO → Settings…**.")
                ]),
                .paragraph(GuideText(
                    "ปิดหรือเปิดแต่ละอย่างได้ที่ **LinMO → Settings…**",
                    "Turn each of these on or off in **LinMO → Settings…**."
                ))
            ]
        ),
        GuideTopic(
            id: "share",
            icon: "doc.on.clipboard",
            title: GuideText("Clipboard และลากไฟล์", "Clipboard and drag and drop"),
            blocks: [
                .bullets([
                    GuideText("copy บน Mac แล้ว paste ใน Linux ได้ และกลับกัน ทั้งข้อความและรูปภาพ", "Copy on the Mac and paste in Linux, and the other way round, for both text and images."),
                    GuideText("ลากไฟล์จาก Finder ไปวางในแอพ Linux ได้ ไฟล์จะอยู่ที่ `~/Downloads/LinMO` ใน Linux ด้วย", "Drag files from Finder into a Linux app. They are also saved to `~/Downloads/LinMO` in Linux."),
                    GuideText("ลากไฟล์จากแอพ Linux เช่นตัวจัดการไฟล์ ออกมาวางที่ Finder หรือ Desktop ได้", "Drag files out of a Linux app, such as the file manager, onto Finder or the Desktop.")
                ]),
                .note(GuideText(
                    "การลากไฟล์ใช้ได้ในโหมดหน้าต่างแยก",
                    "Drag and drop works in separate-window mode."
                ))
            ]
        ),
        GuideTopic(
            id: "folder",
            icon: "folder",
            title: GuideText("แชร์โฟลเดอร์จาก Mac", "Shared folder"),
            blocks: [
                .paragraph(GuideText(
                    "โฟลเดอร์ที่เลือกตอนสร้างเครื่องจะโผล่ที่ `~/Mac` ใน Linux อัตโนมัติ เพิ่ม ลบ หรือเปลี่ยนชื่อไฟล์ใน Finder แล้วตัวจัดการไฟล์ใน Linux แสดงผลทันทีโดยไม่ต้องรีเฟรช",
                    "The folder you chose when creating the machine appears at `~/Mac` in Linux. Add, delete or rename files in Finder and the Linux file manager updates right away, without a refresh."
                )),
                .bullets([
                    GuideText("ปิดเครื่องก่อน แล้วเลือก แชร์ เปลี่ยน หรือเลิกแชร์โฟลเดอร์ได้จากเมนู **…**", "With the machine shut down, share, change or stop sharing a folder from the **…** menu."),
                    GuideText("ถ้าเขียนไฟล์ใน `~/Mac` ไม่ได้ (มักเกิดกับเครื่องจาก ISO) ให้ใช้ `sudo` หรือตั้ง uid ให้ตรงกับ `id -u` บน Mac", "If you can't write to `~/Mac` (common on ISO installs), use `sudo` or match the Linux uid to `id -u` on your Mac.")
                ]),
                .paragraph(GuideText(
                    "เครื่องที่ติดตั้งจาก ISO ต้อง mount เองใน Linux:",
                    "Machines installed from an ISO need the share mounted in Linux:"
                )),
                .code("sudo mkdir -p /mnt/linmo\necho 'linmo /mnt/linmo virtiofs rw,nofail 0 0' | sudo tee -a /etc/fstab\nsudo mount -a"),
                .heading(GuideText("แชร์โฟลเดอร์เพิ่มเติม", "More shared folders")),
                .steps([
                    GuideText("ปิดเครื่อง แล้วเลือกเมนู **…** → **โฟลเดอร์แชร์เพิ่มเติม…**", "Shut down, then open the **…** menu and choose **โฟลเดอร์แชร์เพิ่มเติม…** (More Shared Folders…)."),
                    GuideText("กด **เพิ่มโฟลเดอร์…** เลือกได้หลายโฟลเดอร์ และติ๊ก **อ่านอย่างเดียว** ถ้าไม่ให้ Linux แก้ไฟล์", "Click **เพิ่มโฟลเดอร์…** (Add Folder…), pick one or more folders, and tick **อ่านอย่างเดียว** (Read only) to stop Linux changing them."),
                    GuideText("เปิดเครื่อง แต่ละโฟลเดอร์จะอยู่ที่ `~/MacFolders/ชื่อโฟลเดอร์` และอัปเดตทันทีเหมือน `~/Mac`", "Start the machine. Each folder appears at `~/MacFolders/<folder name>` and updates right away, like `~/Mac`.")
                ]),
                .note(GuideText(
                    "เครื่องที่สร้างไว้ก่อนต้องอัปเดต LinMO Tools ก่อนจึงจะเห็น `~/MacFolders`",
                    "Older machines need a LinMO Tools update before `~/MacFolders` appears."
                ))
            ]
        ),
        GuideTopic(
            id: "suspend",
            icon: "pause.circle",
            title: GuideText("พักเครื่อง", "Suspend and resume"),
            blocks: [
                .paragraph(GuideText(
                    "พักเครื่องเก็บทุกอย่างที่เปิดอยู่ไว้ แล้วกลับมาที่เดิมได้ในไม่กี่วินาที ทั้งแอพและไฟล์ที่เปิดค้างไว้",
                    "Suspending keeps everything that's open, so you can come back to exactly where you left off in a few seconds, apps and open files included."
                )),
                .steps([
                    GuideText("ขณะเครื่องเปิดอยู่ กด **พักเครื่อง** ที่แถบด้านบน", "While the machine is running, click **พักเครื่อง** (Suspend) in the toolbar."),
                    GuideText("กด **เปิดต่อ** เมื่อจะใช้อีกครั้ง", "Click **เปิดต่อ** (Resume) when you want it back.")
                ]),
                .bullets([
                    GuideText("ปิดแอพ LinMO ขณะเครื่องเปิดอยู่ เลือก **พักเครื่องแล้วปิดแอพ** ได้", "When you quit LinMO with a machine running, you can choose **พักเครื่องแล้วปิดแอพ** (Suspend and Quit)."),
                    GuideText("ระหว่างพักอยู่ ทำ snapshot ตั้งค่าเครื่อง แชร์โฟลเดอร์ หรือทำสำเนาไม่ได้ ให้เปิดต่อแล้วปิดเครื่องก่อน", "While suspended you can't take snapshots, change settings, share folders or duplicate. Resume and shut down first."),
                    GuideText("ถ้าไม่ต้องการสถานะที่พักไว้ เลือกเมนู **…** → **ทิ้งสถานะที่พักไว้…** ครั้งหน้าจะบูตใหม่", "If you don't need the suspended state, choose **…** → **ทิ้งสถานะที่พักไว้…** (Discard Suspended State…). The machine boots fresh next time.")
                ]),
                .note(GuideText(
                    "ทิ้งสถานะที่พักไว้เหมือนถอดปลั๊กเครื่อง งานที่ยังไม่บันทึกใน Linux จะหาย",
                    "Discarding the suspended state is like pulling the plug. Unsaved work in Linux is lost."
                ))
            ]
        ),
        GuideTopic(
            id: "ports",
            icon: "network",
            title: GuideText("พอร์ต, SSH และ Docker", "Ports, SSH and Docker"),
            blocks: [
                .paragraph(GuideText(
                    "โปรแกรมที่เปิดพอร์ตใน Linux ใช้จาก Mac ได้ที่ `localhost` พอร์ตเดียวกัน ปุ่ม **พอร์ต** ที่แถบด้านบนแสดงพอร์ตที่เปิดอยู่พร้อมชื่อโปรแกรม",
                    "Programs listening on a port in Linux are reachable from the Mac at `localhost` on the same port. The **พอร์ต** (Ports) button in the toolbar lists open ports with the program that owns each one."
                )),
                .heading(GuideText("เว็บ", "Web")),
                .paragraph(GuideText(
                    "เช่นรันคำสั่งนี้ใน Linux แล้วเปิด `http://localhost:8000` บน Mac หรือคลิกจากเมนู **พอร์ต**",
                    "For example, run this in Linux, then open `http://localhost:8000` on the Mac or click it in the **พอร์ต** (Ports) menu."
                )),
                .code("python3 -m http.server 8000"),
                .heading(GuideText("SSH", "SSH")),
                .paragraph(GuideText(
                    "LinMO ติดตั้ง SSH ให้ใน Linux และส่งพอร์ต 22 มาที่ Mac พอร์ต 2222 (เครื่องถัดไปได้ 2223, 2224…) คัดลอกคำสั่งจากเมนู **พอร์ต** → **คัดลอกคำสั่ง SSH** เช่น:",
                    "LinMO sets up SSH in Linux and forwards port 22 to Mac port 2222 (the next machines get 2223, 2224…). Copy the command from **พอร์ต** (Ports) → **คัดลอกคำสั่ง SSH** (Copy SSH command), for example:"
                )),
                .code("ssh -p 2222 user@localhost"),
                .paragraph(GuideText(
                    "การเชื่อมต่อนานๆ เช่น VS Code Remote-SSH หรือ scp ไฟล์ใหญ่ ใช้ได้โดยไม่หลุด",
                    "Long-lived connections, such as VS Code Remote-SSH or copying large files with scp, stay connected."
                )),
                .heading(GuideText("Docker จาก Mac", "Docker from the Mac")),
                .steps([
                    GuideText("ติดตั้ง Docker ใน Linux (ชุดสาย dev มีให้แล้ว) และติดตั้งคำสั่ง `docker` บน Mac เช่น `brew install docker`", "Install Docker in Linux (the Developer set includes it) and the `docker` command on the Mac, for example `brew install docker`."),
                    GuideText("เลือก **พอร์ต** → **คัดลอกคำสั่งใช้ Docker ของ Linux จาก Mac** แล้ววางใน Terminal ของ Mac", "Choose **พอร์ต** (Ports) → **คัดลอกคำสั่งใช้ Docker ของ Linux จาก Mac** (Copy command to use Linux Docker from the Mac) and paste it into a Mac Terminal."),
                    GuideText("จากนั้น `docker ps` หรือ `docker run` บน Mac จะทำงานกับ Docker ใน Linux", "After that, `docker ps` and `docker run` on the Mac talk to Docker in Linux.")
                ]),
                .note(GuideText(
                    "ปุ่ม **พอร์ต** ต้องใช้ LinMO Tools รุ่นใหม่ ถ้าไม่เห็นปุ่มให้อัปเดต LinMO Tools แล้วรีสตาร์ตเครื่อง",
                    "The **พอร์ต** (Ports) button needs a recent LinMO Tools. If it's missing, update LinMO Tools and restart the machine."
                ))
            ]
        ),
        GuideTopic(
            id: "snapshot",
            icon: "clock.arrow.circlepath",
            title: GuideText("Snapshot", "Snapshots"),
            blocks: [
                .paragraph(GuideText(
                    "บันทึกสถานะเครื่องไว้ ถ้าลองอะไรแล้วพังก็ย้อนกลับได้ในไม่กี่วินาที ใช้พื้นที่เพิ่มเฉพาะส่วนที่เปลี่ยนไป",
                    "Save the state of a machine and roll back in seconds if something breaks. Snapshots only use space for what changed."
                )),
                .steps([
                    GuideText("ปิดเครื่องก่อน", "Shut the machine down."),
                    GuideText("กดปุ่ม **Snapshot** ที่แถบด้านบน", "Click **Snapshot** in the toolbar."),
                    GuideText("กด **บันทึกตอนนี้** เพื่อสร้าง หรือ **ย้อนกลับ** ที่ snapshot ที่ต้องการ", "Click **บันทึกตอนนี้** (Save Now) to create one, or **ย้อนกลับ** (Restore) on the snapshot you want.")
                ]),
                .bullets([
                    GuideText("เครื่องแบบคลิกเดียวมี snapshot **หลังติดตั้งเสร็จ** ให้อัตโนมัติ", "One-click machines get an automatic **หลังติดตั้งเสร็จ** (After setup) snapshot."),
                    GuideText("ทำ snapshot ไม่ได้ระหว่างเครื่องพักอยู่ ให้เปิดต่อแล้วปิดเครื่องก่อน", "Snapshots aren't available while the machine is suspended. Resume and shut down first.")
                ]),
                .note(GuideText(
                    "ย้อนกลับแล้วทุกอย่างที่เปลี่ยนหลังจาก snapshot นั้นจะหายไป ถ้าไม่แน่ใจให้บันทึก snapshot ของตอนนี้ไว้ก่อน",
                    "Restoring discards everything changed after that snapshot. If unsure, save a snapshot of the current state first."
                ))
            ]
        ),
        GuideTopic(
            id: "duplicate",
            icon: "plus.square.on.square",
            title: GuideText("ทำสำเนาเครื่อง", "Duplicate a machine"),
            blocks: [
                .paragraph(GuideText(
                    "ปิดเครื่อง แล้วเลือกเมนู **…** → **ทำสำเนาเครื่อง** จะได้เครื่องใหม่ชื่อ \"ชื่อเดิม (สำเนา)\" ที่มีทุกอย่างเหมือนเดิม เสร็จเร็วและใช้พื้นที่เพิ่มเฉพาะส่วนที่ต่างกัน",
                    "Shut down, then choose **…** → **ทำสำเนาเครื่อง** (Duplicate Machine). You get a new machine named \"<name> (สำเนา)\" with everything the original has. It's quick and only uses space for what changes later."
                )),
                .note(GuideText(
                    "สำเนาใช้การ์ดเครือข่ายเดียวกับต้นฉบับ จึงเปิดพร้อมกันไม่ได้ ต้องปิดเครื่องหนึ่งก่อน",
                    "A duplicate shares the original's network card, so the two can't run at the same time. Shut one down first."
                ))
            ]
        ),
        GuideTopic(
            id: "rosetta",
            icon: "cpu",
            title: GuideText("Rosetta (โปรแกรม x86_64)", "Rosetta (x86_64 programs)"),
            blocks: [
                .paragraph(GuideText(
                    "Rosetta ช่วยให้รันโปรแกรม Linux แบบ x86_64 (Intel/AMD 64 บิต) บนเครื่อง ARM ได้ ใช้กับโปรแกรม 32 บิต (i386) ไม่ได้",
                    "Rosetta lets you run x86_64 (64-bit Intel/AMD) Linux programs on an ARM machine. It does not run 32-bit (i386) programs."
                )),
                .heading(GuideText("เปิด Rosetta ให้เครื่องที่สร้างไปแล้ว", "Turn on Rosetta for an existing machine")),
                .steps([
                    GuideText("ปิดเครื่อง แล้วเปิด **รันโปรแกรม x86_64 ผ่าน Rosetta** ใน **ตั้งค่าเครื่อง…** ถ้า Mac ยังไม่มี Rosetta แอพจะติดตั้งให้", "Shut down and turn on **รันโปรแกรม x86_64 ผ่าน Rosetta** (Run x86_64 programs with Rosetta) in **ตั้งค่าเครื่อง…** (Machine Settings…). LinMO installs Rosetta on the Mac if it's missing."),
                    GuideText("เปิดเครื่องใหม่", "Start the machine again."),
                    GuideText("รันคำสั่งติดตั้ง LinMO Tools ใน Terminal ของ Linux อีกครั้ง (ดูหัวข้อ **LinMO Agent และ LinMO Tools**)", "Run the LinMO Tools install command in a Linux Terminal again (see **LinMO Agent and LinMO Tools**).")
                ])
            ]
        ),
        GuideTopic(
            id: "wine",
            icon: "wineglass",
            title: GuideText("โปรแกรม Windows (Wine)", "Windows programs (Wine)"),
            blocks: [
                .paragraph(GuideText(
                    "ติดตั้ง Wine ได้ในคลิกเดียวจากปุ่ม **Wine** ที่แถบด้านบน รองรับ Debian และ Ubuntu",
                    "Install Wine in one click with the **Wine** button in the toolbar. Debian and Ubuntu are supported."
                )),
                .bullets([
                    GuideText("**Hangover** เปิดโปรแกรม Windows ได้ทั้ง 32 และ 64 บิต ไม่ต้องใช้ Rosetta แนะนำสำหรับโปรแกรมส่วนใหญ่", "**Hangover** runs both 32-bit and 64-bit Windows programs without Rosetta. Recommended for most programs."),
                    GuideText("**WineHQ + Rosetta** เร็วกว่า แต่เปิดได้เฉพาะโปรแกรม 64 บิต และต้องเปิด Rosetta ก่อน เพราะ Rosetta แปลได้เฉพาะ x86_64 ไม่รองรับ i386", "**WineHQ + Rosetta** is faster but only runs 64-bit programs, and needs Rosetta turned on first, because Rosetta translates x86_64 only, not i386.")
                ]),
                .steps([
                    GuideText("เปิดเครื่อง แล้วกดปุ่ม **Wine** และเลือกแบบที่ต้องการ", "Start the machine, click **Wine**, and choose a flavor."),
                    GuideText("กด **คัดลอกคำสั่ง** แล้ววางใน Terminal ของ Linux", "Click **คัดลอกคำสั่ง** (Copy Command) and paste it into a Linux Terminal."),
                    GuideText("ติดตั้งเสร็จแล้วดับเบิลคลิกไฟล์ .exe หรือ .msi หรือพิมพ์ `wine ชื่อไฟล์.exe` ใน Terminal", "When it finishes, double-click a .exe or .msi file, or run `wine program.exe` in Terminal.")
                ]),
                .note(GuideText(
                    "ติดตั้งได้ทีละแบบ ถ้าลงอีกแบบไว้แล้วจะถูกถอดออกให้",
                    "Only one flavor can be installed at a time. Installing one removes the other."
                ))
            ]
        ),
        GuideTopic(
            id: "agent",
            icon: "shippingbox",
            title: GuideText("LinMO Agent และ LinMO Tools", "LinMO Agent and LinMO Tools"),
            blocks: [
                .paragraph(GuideText(
                    "LinMO Agent ทำงานใน Linux เพื่อให้หน้าต่างแยก clipboard ลากไฟล์ และรายการแอพทำงานได้ เครื่องที่สร้างแบบคลิกเดียวมีให้แล้ว แอพต่อแผ่น LinMO Tools ให้ทุกเครื่อง",
                    "LinMO Agent runs inside Linux and powers separate windows, the clipboard, drag and drop and the app list. One-click machines already have it, and LinMO attaches a LinMO Tools disk to every machine."
                )),
                .paragraph(GuideText(
                    "LinMO Tools อัปเดตเองทุกครั้งที่เปิดเครื่อง เมื่อแอพ LinMO มีรุ่นใหม่ agent ใน Linux จะอัปเดตตามโดยไม่ต้องทำอะไร",
                    "LinMO Tools updates itself every time the machine starts. When you get a new LinMO app, the agent in Linux follows without you doing anything."
                )),
                .heading(GuideText("ติดตั้งหรืออัปเดตเอง", "Install or update by hand")),
                .paragraph(GuideText(
                    "ใช้กับเครื่องจาก ISO และเครื่องเก่าที่ยังอัปเดตเองไม่ได้ ทำครั้งเดียวหลังจากนั้นจะอัปเดตเอง",
                    "Use this for ISO installs and older machines that can't update themselves yet. After doing it once, updates are automatic."
                )),
                .steps([
                    GuideText("ถ้าแอพขึ้นลูกศรสีส้มที่ปุ่ม **หน้าต่างแยก** แปลว่ามี agent รุ่นใหม่ ถ้ายังไม่มี agent ให้กดปุ่ม **หน้าต่างแยก**", "An orange arrow on **หน้าต่างแยก** (Separate Windows) means a newer agent is available. If there is no agent yet, click **หน้าต่างแยก** (Separate Windows)."),
                    GuideText("คัดลอกคำสั่งติดตั้งไปวางใน Terminal ของ Linux", "Copy the install command and paste it into a Linux Terminal."),
                    GuideText("ออกจากระบบ Linux แล้วเข้าใหม่", "Log out of Linux and log back in.")
                ]),
                .note(GuideText(
                    "ถ้าอัปเดต agent เพื่อใช้ฟีเจอร์ใหม่ (เช่นโฟลเดอร์อัปเดตเองหรือ Rosetta) ให้รีสตาร์ตเครื่องก่อน แล้วค่อยรันคำสั่งติดตั้ง",
                    "When updating the agent for new features (such as shared-folder auto refresh or Rosetta), restart the machine first, then run the install command."
                ))
            ]
        ),
        GuideTopic(
            id: "trouble",
            icon: "wrench.and.screwdriver",
            title: GuideText("ปัญหาที่พบบ่อย", "Troubleshooting"),
            blocks: [
                .heading(GuideText("ตั้งค่าครั้งแรกนานมาก", "First-boot setup takes a long time")),
                .paragraph(GuideText(
                    "ปกติใช้ 10–30 นาทีขึ้นกับความเร็วเน็ต ถ้าตัวเลขไม่ขยับเกิน 20 นาที ลองเช็กอินเทอร์เน็ตแล้วปิด-เปิดเครื่องใหม่",
                    "It usually takes 10–30 minutes depending on your connection. If the progress doesn't move for over 20 minutes, check your internet and restart the machine."
                )),
                .heading(GuideText("ค้างที่หน้าจอข้อความหลังตั้งค่าเสร็จ", "Stuck on a text console after setup")),
                .paragraph(GuideText(
                    "กด **ปิดเครื่อง** แอพจะเปิดเครื่องใหม่เข้าหน้าจอ desktop ให้เอง",
                    "Click **ปิดเครื่อง** (Shut Down). The app restarts the machine into the desktop."
                )),
                .heading(GuideText("แถบแจ้งว่ามีขั้นตอนไม่สำเร็จ", "The progress bar reports a failed step")),
                .paragraph(GuideText(
                    "ใน Linux เปิด Terminal แล้วดู log:",
                    "Open a Terminal in Linux and check the log:"
                )),
                .code("sudo less /var/log/cloud-init-output.log"),
                .heading(GuideText("Linux ต่ออินเทอร์เน็ตไม่ได้", "No internet in Linux")),
                .paragraph(GuideText(
                    "เครื่องที่สร้างก่อน v0.10 อาจต้องแก้ไฟล์ netplan ครั้งเดียว ให้จับการ์ดแลนด้วย driver `virtio_net` แทน MAC address",
                    "Machines created before v0.10 may need a one-time netplan change that matches the network card by driver `virtio_net` instead of MAC address."
                )),
                .heading(GuideText("บูตจาก ISO ไม่ขึ้น หรือบูตเข้าตัวติดตั้งซ้ำ", "ISO won't boot, or the installer keeps coming back")),
                .bullets([
                    GuideText("ตรวจว่า ISO เป็นรุ่น ARM64 ไม่ใช่ x86_64 (amd64)", "Make sure the ISO is ARM64, not x86_64 (amd64)."),
                    GuideText("ติดตั้งเสร็จแล้วให้ปิดเครื่องและกด **ถอดแผ่นติดตั้ง**", "After installing, shut down and click **ถอดแผ่นติดตั้ง** (Eject Installer).")
                ]),
                .heading(GuideText("หน้าต่างแยกไม่ทำงาน", "Separate windows don't work")),
                .bullets([
                    GuideText("ตรวจว่าติดตั้ง LinMO Agent แล้ว และออกจากระบบแล้วเข้าใหม่", "Check that LinMO Agent is installed, then log out and back in."),
                    GuideText("ใช้หน้าจอแบบ X11 หรือเปิด **เปิดแอพผ่าน Wayland (ทดลอง)**", "Use an X11 session, or turn on **เปิดแอพผ่าน Wayland (ทดลอง)** (Open apps through Wayland (experimental)).")
                ]),
                .heading(GuideText("เครื่องนี้กำลังถูกใช้อยู่ในแอพ LinMO อีกตัวหนึ่ง", "The machine is in use by another LinMO app")),
                .paragraph(GuideText(
                    "มีแอพ LinMO สองตัว เช่นตัวใน `build/` กับตัวใน Applications เปิดเครื่องเดียวกันอยู่ ปิดเครื่องหรือปิดแอพตัวนั้นก่อน LinMO ล็อกไว้เพราะถ้าเปิดดิสก์เดียวกันซ้อนกัน ดิสก์ Linux จะเสีย",
                    "Two copies of LinMO, such as one in `build/` and one in Applications, are using the same machine. Shut it down or quit the other copy first. LinMO blocks this because running one disk twice corrupts it."
                )),
                .heading(GuideText("เปิดเครื่องไม่ได้เพราะต้นฉบับหรือสำเนาเปิดอยู่", "Can't start because the original or a duplicate is running")),
                .paragraph(GuideText(
                    "ปิดเครื่องต้นฉบับหรือสำเนาที่เปิดอยู่ก่อน เพราะทั้งสองใช้การ์ดเครือข่ายเดียวกัน",
                    "Shut down the running original or duplicate first, because both use the same network card."
                )),
                .heading(GuideText("ไม่มีปุ่มพอร์ต หรือ SSH ใช้ไม่ได้", "No Ports button, or SSH doesn't work")),
                .paragraph(GuideText(
                    "อัปเดต LinMO Tools (ดูหัวข้อ **LinMO Agent และ LinMO Tools**) แล้วรีสตาร์ตเครื่อง",
                    "Update LinMO Tools (see **LinMO Agent and LinMO Tools**) and restart the machine."
                ))
            ]
        ),
        GuideTopic(
            id: "files",
            icon: "externaldrive",
            title: GuideText("ไฟล์เก็บไว้ที่ไหน", "Where files are stored"),
            blocks: [
                .bullets([
                    GuideText("`~/Library/Application Support/LinMO/Machines/` เครื่องแต่ละเครื่อง (ดิสก์, NVRAM, config, snapshot)", "`~/Library/Application Support/LinMO/Machines/`: each machine (disk, NVRAM, config, snapshots)."),
                    GuideText("`~/Library/Caches/LinMO/` ไฟล์ Linux ที่ดาวน์โหลดไว้ ดูขนาดและลบได้ที่ **LinMO → Settings…**", "`~/Library/Caches/LinMO/`: downloaded Linux images. See their size and delete them in **LinMO → Settings…**."),
                    GuideText("`~/Applications/แอพ Linux (LinMO)/` ทางลัดของแอพ Linux ใน Launchpad", "`~/Applications/แอพ Linux (LinMO)/`: Launchpad shortcuts for Linux apps."),
                    GuideText("`~/.linmo/` socket สำหรับใช้ Docker ของ Linux จาก Mac (มีเฉพาะตอนเครื่องเปิดอยู่)", "`~/.linmo/`: sockets for using Linux Docker from the Mac (only while the machine runs).")
                ]),
                .paragraph(GuideText(
                    "เปิดไฟล์ของเครื่องได้จากเมนู **…** → **แสดงไฟล์ของเครื่องใน Finder**",
                    "Open a machine's files from the **…** menu → **แสดงไฟล์ของเครื่องใน Finder** (Show Machine Files in Finder)."
                ))
            ]
        )
    ]
}
