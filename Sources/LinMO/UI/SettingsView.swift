import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var cached: [ImageStore.CachedImage] = []
    @State private var totalBytes: Int64 = 0
    @State private var confirmingClearAll = false
    @State private var errorMessage: String?
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue

    var body: some View {
        Form {
            LanguageSettingsSection()

            LinuxAppsSettingsSection()

            Section {
                if cached.isEmpty {
                    Text(tr("ยังไม่มีไฟล์ที่ดาวน์โหลดไว้", "No downloaded files yet"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cached) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.distro.name)
                                Text(format(item.bytes))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(tr("ลบ", "Delete")) { remove(item) }
                        }
                    }
                }
            } header: {
                Text(tr("ไฟล์ Linux ที่ดาวน์โหลดไว้", "Downloaded Linux files"))
            } footer: {
                Text(tr("เก็บไว้เพื่อให้สร้างเครื่องใหม่ได้ทันทีโดยไม่ต้องดาวน์โหลดซ้ำ ลบได้โดยไม่กระทบเครื่องที่สร้างไปแล้ว", "Kept so new machines can be created right away without downloading again. Deleting them does not affect machines you already created."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(tr("ใช้พื้นที่ทั้งหมด", "Total space used"), value: format(totalBytes))
                HStack {
                    Button(tr("แสดงใน Finder", "Show in Finder")) {
                        try? FileManager.default.createDirectory(at: ImageStore.cacheDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ImageStore.cacheDirectory)
                    }
                    Spacer()
                    Button(tr("ลบทั้งหมด", "Delete All"), role: .destructive) { confirmingClearAll = true }
                        .disabled(totalBytes == 0)
                }
            }
        }
        .formStyle(.grouped)
        .id(appLanguageRaw)
        .frame(width: 520, height: 600)
        .onAppear(perform: refresh)
        .confirmationDialog(tr("ลบไฟล์ที่ดาวน์โหลดไว้ทั้งหมด?", "Delete all downloaded files?"), isPresented: $confirmingClearAll) {
            Button(tr("ลบทั้งหมด", "Delete All"), role: .destructive) {
                do {
                    try ImageStore.clearCache()
                } catch {
                    errorMessage = tr("ลบไม่สำเร็จ: \(error.localizedDescription)", "Could not delete: \(error.localizedDescription)")
                }
                refresh()
            }
        } message: {
            Text(tr("ครั้งหน้าที่สร้างเครื่องใหม่จะต้องดาวน์โหลดอีกครั้ง", "The next new machine will need to download again."))
        }
        .errorAlert($errorMessage)
    }

    private func refresh() {
        cached = ImageStore.cachedImages()
        totalBytes = ImageStore.totalCacheSize()
    }

    private func remove(_ item: ImageStore.CachedImage) {
        do {
            try ImageStore.removeCache(for: item.distro)
        } catch {
            errorMessage = tr("ลบไม่สำเร็จ: \(error.localizedDescription)", "Could not delete: \(error.localizedDescription)")
        }
        refresh()
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct LanguageSettingsSection: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue
    @AppStorage(AppLanguage.guideStorageKey) private var guideLanguageRaw = AppLanguage.current.rawValue

    var body: some View {
        Section {
            Picker("ภาษา / Language", selection: Binding(
                get: { appLanguageRaw },
                set: { value in
                    appLanguageRaw = value
                    guideLanguageRaw = value
                }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.label).tag(language.rawValue)
                }
            }
        } footer: {
            Text(tr("บางเมนูของ macOS จะเปลี่ยนภาษาหลังเปิดแอพใหม่", "Some macOS menus switch language after you reopen the app"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
