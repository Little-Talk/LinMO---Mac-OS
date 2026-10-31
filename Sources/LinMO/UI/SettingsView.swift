import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var cached: [ImageStore.CachedImage] = []
    @State private var totalBytes: Int64 = 0
    @State private var confirmingClearAll = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            LinuxAppsSettingsSection()

            Section {
                if cached.isEmpty {
                    Text("ยังไม่มีไฟล์ที่ดาวน์โหลดไว้")
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
                            Button("ลบ") { remove(item) }
                        }
                    }
                }
            } header: {
                Text("ไฟล์ Linux ที่ดาวน์โหลดไว้")
            } footer: {
                Text("เก็บไว้เพื่อให้สร้างเครื่องใหม่ได้ทันทีโดยไม่ต้องดาวน์โหลดซ้ำ ลบได้โดยไม่กระทบเครื่องที่สร้างไปแล้ว")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("ใช้พื้นที่ทั้งหมด", value: format(totalBytes))
                HStack {
                    Button("แสดงใน Finder") {
                        try? FileManager.default.createDirectory(at: ImageStore.cacheDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ImageStore.cacheDirectory)
                    }
                    Spacer()
                    Button("ลบทั้งหมด", role: .destructive) { confirmingClearAll = true }
                        .disabled(totalBytes == 0)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
        .onAppear(perform: refresh)
        .confirmationDialog("ลบไฟล์ที่ดาวน์โหลดไว้ทั้งหมด?", isPresented: $confirmingClearAll) {
            Button("ลบทั้งหมด", role: .destructive) {
                do {
                    try ImageStore.clearCache()
                } catch {
                    errorMessage = "ลบไม่สำเร็จ: \(error.localizedDescription)"
                }
                refresh()
            }
        } message: {
            Text("ครั้งหน้าที่สร้างเครื่องใหม่จะต้องดาวน์โหลดอีกครั้ง")
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
            errorMessage = "ลบไม่สำเร็จ: \(error.localizedDescription)"
        }
        refresh()
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
