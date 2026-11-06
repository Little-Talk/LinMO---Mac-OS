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
                Text(tr("บันทึกสถานะของเครื่องไว้ ถ้าลองอะไรแล้วพังก็ย้อนกลับมาได้ทันที ใช้พื้นที่เพิ่มเฉพาะส่วนที่เปลี่ยนไป", "Save the machine state so you can go back right away if something breaks. Only the changes use extra space."))
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            HStack {
                TextField(tr("ชื่อ snapshot (เช่น ก่อนลองโปรแกรมใหม่)", "Snapshot name (for example, before trying a new program)"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                Button(tr("บันทึกตอนนี้", "Save Now"), action: create)
                    .disabled(machine.state != .stopped)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if machine.snapshots.isEmpty {
                Text(tr("ยังไม่มี snapshot", "No snapshots yet"))
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
                        Button(tr("ย้อนกลับ", "Restore")) { pendingRestore = snapshot }
                            .disabled(machine.state != .stopped)
                        Button {
                            pendingDelete = snapshot
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(tr("ลบ snapshot", "Delete snapshot"))
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()
            HStack {
                if machine.state != .stopped {
                    Text(tr("ต้องปิดเครื่องก่อนจึงจะบันทึกหรือย้อนกลับได้", "Shut down the machine before saving or restoring"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("เสร็จ", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 460)
        .confirmationDialog(
            tr("ย้อนกลับไปที่ \"\(pendingRestore?.name ?? "")\"?", "Restore to \"\(pendingRestore?.name ?? "")\"?"),
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
        ) {
            Button(tr("ย้อนกลับ", "Restore"), role: .destructive) {
                if let snapshot = pendingRestore { machine.restoreSnapshot(snapshot) }
                pendingRestore = nil
            }
        } message: {
            Text(tr("ทุกอย่างที่เปลี่ยนหลังจาก snapshot นี้จะหายไป (ถ้าไม่แน่ใจ ให้บันทึก snapshot ของตอนนี้ไว้ก่อน)", "Everything changed after this snapshot will be lost. (If you are not sure, save a snapshot of the current state first.)"))
        }
        .confirmationDialog(
            tr("ลบ snapshot \"\(pendingDelete?.name ?? "")\"?", "Delete snapshot \"\(pendingDelete?.name ?? "")\"?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button(tr("ลบ", "Delete"), role: .destructive) {
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
