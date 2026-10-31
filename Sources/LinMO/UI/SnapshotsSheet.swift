import SwiftUI

struct SnapshotsSheet: View {
    @ObservedObject var machine: MachineController
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var pendingRestore: Snapshot?
    @State private var pendingDelete: Snapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Snapshot")
                    .font(.title2.bold())
                Text("บันทึกสถานะของเครื่องไว้ ถ้าลองอะไรแล้วพังก็ย้อนกลับมาได้ทันที ใช้พื้นที่เพิ่มเฉพาะส่วนที่เปลี่ยนไป")
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            HStack {
                TextField("ชื่อ snapshot (เช่น ก่อนลองโปรแกรมใหม่)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                Button("บันทึกตอนนี้", action: create)
                    .disabled(machine.state != .stopped)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if machine.snapshots.isEmpty {
                Text("ยังไม่มี snapshot")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(machine.snapshots) { snapshot in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.name)
                            Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("ย้อนกลับ") { pendingRestore = snapshot }
                            .disabled(machine.state != .stopped)
                        Button {
                            pendingDelete = snapshot
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("ลบ snapshot")
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()
            HStack {
                if machine.state != .stopped {
                    Text("ต้องปิดเครื่องก่อนจึงจะบันทึกหรือย้อนกลับได้")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("เสร็จ") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 460)
        .confirmationDialog(
            "ย้อนกลับไปที่ \"\(pendingRestore?.name ?? "")\"?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
        ) {
            Button("ย้อนกลับ", role: .destructive) {
                if let snapshot = pendingRestore { machine.restoreSnapshot(snapshot) }
                pendingRestore = nil
            }
        } message: {
            Text("ทุกอย่างที่เปลี่ยนหลังจาก snapshot นี้จะหายไป (ถ้าไม่แน่ใจ ให้บันทึก snapshot ของตอนนี้ไว้ก่อน)")
        }
        .confirmationDialog(
            "ลบ snapshot \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("ลบ", role: .destructive) {
                if let snapshot = pendingDelete { machine.deleteSnapshot(snapshot) }
                pendingDelete = nil
            }
        }
    }

    private func create() {
        guard machine.state == .stopped else { return }
        machine.createSnapshot(named: newName)
        newName = ""
    }
}
