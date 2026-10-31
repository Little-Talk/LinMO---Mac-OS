import SwiftUI
import Virtualization

struct StatusBadge: View {
    let state: MachineController.State

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var label: String {
        switch state {
        case .stopped: return "ปิดอยู่"
        case .starting: return "กำลังเปิด…"
        case .running: return "ทำงานอยู่"
        case .stopping: return "กำลังปิด…"
        }
    }

    private var color: Color {
        switch state {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .stopped: return .gray
        }
    }
}

struct VMDisplayView: NSViewRepresentable {
    let machine: VZVirtualMachine

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.virtualMachine = machine
        view.capturesSystemKeys = true
        view.automaticallyReconfiguresDisplay = true
        return view
    }

    func updateNSView(_ view: VZVirtualMachineView, context: Context) {
        if view.virtualMachine !== machine {
            view.virtualMachine = machine
        }
    }
}

struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "เกิดข้อผิดพลาด",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}

struct SetupProgressBanner: View {
    let status: SetupStatus
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                if !status.finished, let progress = status.progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 320)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if status.finished {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 2)
    }

    @ViewBuilder
    private var icon: some View {
        if status.finished && status.errors > 0 {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title2)
        } else if status.finished {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var title: String {
        if status.finished && status.errors > 0 {
            return "ตั้งค่าเสร็จ แต่มี \(status.errors) ขั้นตอนที่ไม่สำเร็จ"
        }
        if status.finished {
            return "ตั้งค่าเสร็จแล้ว กำลังรีบูตเข้าหน้าจอ desktop…"
        }
        if let progress = status.progress {
            return "กำลังตั้งค่าครั้งแรก… \(Int(progress * 100))%"
        }
        return "กำลังตั้งค่าครั้งแรก…"
    }

    private var subtitle: String {
        if status.finished && status.errors > 0 {
            return "ดูรายละเอียดใน Linux ที่ /var/log/cloud-init-output.log"
        }
        if status.finished {
            return "ขั้นตอนนี้ทำแค่ครั้งเดียว"
        }
        return status.line
    }
}
