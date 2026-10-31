import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MachineLibrary
    @State private var selection: UUID?
    @State private var showingNewMachine = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("เครื่องของฉัน") {
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
                        Label("สร้างเครื่องใหม่", systemImage: "plus")
                    }
                    .help("สร้างเครื่องใหม่")
                }
            }
        } detail: {
            if let machine = library.machines.first(where: { $0.id == selection }) {
                MachineDetailView(machine: machine)
                    .id(machine.id)
            } else {
                EmptyLibraryView(hasMachines: !library.machines.isEmpty) {
                    showingNewMachine = true
                }
            }
        }
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
            StatusBadge(state: machine.state)
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
                Text("เลือกเครื่องจากรายการด้านซ้าย")
                    .font(.title3)
            } else {
                Text("ยินดีต้อนรับสู่ LinMO")
                    .font(.largeTitle.bold())
                Text("ใช้ Linux บน Mac ได้ในไม่กี่คลิก")
                    .foregroundStyle(.secondary)
                Button("สร้างเครื่องแรก", action: onCreate)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
