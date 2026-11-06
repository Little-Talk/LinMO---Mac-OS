import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MachineLibrary
    @State private var selection: UUID?
    @State private var showingNewMachine = false
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.thai.rawValue

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(tr("เครื่องของฉัน", "My Machines")) {
                    ForEach(library.machines) { machine in
                        MachineRow(machine: machine)
                            .tag(machine.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .toolbar {
                ToolbarItem {
                    Button {
                        showingNewMachine = true
                    } label: {
                        Label(tr("สร้างเครื่องใหม่", "New Machine"), systemImage: "plus")
                    }
                    .help(tr("สร้างเครื่องใหม่", "New Machine"))
                }
            }
        } detail: {
            if let machine = library.machines.first(where: { $0.id == selection }) {
                MachineDetailView(machine: machine)
                    .id(machine.id)
                    .navigationSplitViewColumnWidth(min: 560, ideal: 760)
            } else {
                EmptyLibraryView(hasMachines: !library.machines.isEmpty) {
                    showingNewMachine = true
                }
            }
        }
        .id(appLanguageRaw)
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingNewMachine) {
            NewMachineSheet { created in
                selection = created.id
            }
            .environmentObject(library)
        }
        .onAppear {
            if selection == nil {
                selection = library.machines.first?.id
            }
        }
        .errorAlert($library.errorMessage)
    }
}

private struct MachineRow: View {
    @ObservedObject var machine: MachineController

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(machine.config.name)
                .font(.body.weight(.medium))
            StatusBadge(state: machine.state, suspended: machine.isSuspended)
                .font(.caption)
        }
        .padding(.vertical, 3)
    }
}

private struct EmptyLibraryView: View {
    let hasMachines: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            if hasMachines {
                Text(tr("เลือกเครื่องจากรายการด้านซ้าย", "Select a machine from the list on the left"))
                    .font(.title3)
            } else {
                Text(tr("ยินดีต้อนรับสู่ LinMO", "Welcome to LinMO"))
                    .font(.largeTitle.bold())
                Text(tr("ใช้ Linux บน Mac ได้ในไม่กี่คลิก", "Run Linux on your Mac in a few clicks"))
                    .foregroundStyle(.secondary)
                Button(tr("สร้างเครื่องแรก", "Create Your First Machine"), action: onCreate)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
