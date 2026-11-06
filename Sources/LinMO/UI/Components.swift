import SwiftUI
import Virtualization

struct StatusBadge: View {
    let state: MachineController.State
    var suspended = false

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
        case .stopped: return suspended ? tr("พักอยู่", "Suspended") : tr("ปิดอยู่", "Stopped")
        case .starting: return tr("กำลังเปิด…", "Starting…")
        case .running: return tr("ทำงานอยู่", "Running")
        case .suspending: return tr("กำลังพักเครื่อง…", "Suspending…")
        case .stopping: return tr("กำลังปิด…", "Shutting down…")
        }
    }

    private var color: Color {
        switch state {
        case .running: return .green
        case .starting, .suspending, .stopping: return .orange
        case .stopped: return suspended ? .blue : .gray
        }
    }
}

struct VMDisplayView: NSViewRepresentable {
    let controller: MachineController
    let machine: VZVirtualMachine

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = controller.display(for: machine)
        view.removeFromSuperview()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
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
            tr("เกิดข้อผิดพลาด", "Something went wrong"),
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button(tr("ตกลง", "OK"), role: .cancel) {}
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
            return tr("ตั้งค่าเสร็จ แต่มี \(status.errors) ขั้นตอนที่ไม่สำเร็จ", "Setup finished, but \(status.errors) steps failed")
        }
        if status.finished {
            return tr("ตั้งค่าเสร็จแล้ว กำลังรีบูตเข้าหน้าจอ desktop…", "Setup finished. Restarting into the desktop…")
        }
        if let progress = status.progress {
            return tr("กำลังตั้งค่าครั้งแรก… \(Int(progress * 100))%", "First-time setup… \(Int(progress * 100))%")
        }
        return tr("กำลังตั้งค่าครั้งแรก…", "First-time setup…")
    }

    private var subtitle: String {
        if status.finished && status.errors > 0 {
            return tr("ดูรายละเอียดใน Linux ที่ /var/log/cloud-init-output.log", "See details in Linux at /var/log/cloud-init-output.log")
        }
        if status.finished {
            return tr("ขั้นตอนนี้ทำแค่ครั้งเดียว", "This only happens once")
        }
        return status.line
    }
}
