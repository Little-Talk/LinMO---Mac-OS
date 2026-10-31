import Foundation
import Virtualization

struct MachineBundle {
    let url: URL

    static var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinMO", isDirectory: true)
    }

    static var machinesDirectory: URL {
        appSupportDirectory.appendingPathComponent("Machines", isDirectory: true)
    }

    static func url(for id: UUID) -> URL {
        machinesDirectory.appendingPathComponent("\(id.uuidString).vmbundle", isDirectory: true)
    }

    var diskURL: URL { url.appendingPathComponent("Disk.img") }
    var nvramURL: URL { url.appendingPathComponent("NVRAM") }
    var machineIdentifierURL: URL { url.appendingPathComponent("MachineIdentifier") }
    var macAddressURL: URL { url.appendingPathComponent("MACAddress") }
    var configURL: URL { url.appendingPathComponent("config.json") }
    var cloudInitSeedURL: URL { url.appendingPathComponent("CloudInit.iso") }
    var snapshotsURL: URL { url.appendingPathComponent("Snapshots", isDirectory: true) }


    func loadConfig() throws -> MachineConfig {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MachineConfig.self, from: Data(contentsOf: configURL))
    }

    func save(_ config: MachineConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(config).write(to: configURL, options: .atomic)
    }


    static func create(config: MachineConfig, diskSource: URL? = nil) throws -> MachineBundle {
        let fm = FileManager.default
        let bundle = MachineBundle(url: url(for: config.id))
        try fm.createDirectory(at: bundle.url, withIntermediateDirectories: true)

        do {
            if let diskSource {
                try fm.copyItem(at: diskSource, to: bundle.diskURL)
            } else {
                guard fm.createFile(atPath: bundle.diskURL.path, contents: nil) else {
                    throw LinMOError.message("สร้างไฟล์ดิสก์ไม่สำเร็จ")
                }
            }
            try bundle.growDisk(toGB: config.diskGB)

            _ = try VZEFIVariableStore(creatingVariableStoreAt: bundle.nvramURL)
            try VZGenericMachineIdentifier().dataRepresentation.write(to: bundle.machineIdentifierURL)
            try VZMACAddress.randomLocallyAdministered().string.write(to: bundle.macAddressURL, atomically: true, encoding: .utf8)
            try bundle.save(config)
        } catch {
            try? fm.removeItem(at: bundle.url)
            throw error
        }
        return bundle
    }

    func macAddress() -> VZMACAddress {
        if let text = try? String(contentsOf: macAddressURL, encoding: .utf8),
           let saved = VZMACAddress(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return saved
        }
        let fresh = VZMACAddress.randomLocallyAdministered()
        try? fresh.string.write(to: macAddressURL, atomically: true, encoding: .utf8)
        return fresh
    }

    func growDisk(toGB gb: Int) throws {
        let target = UInt64(gb) * 1024 * 1024 * 1024
        let handle = try FileHandle(forWritingTo: diskURL)
        defer { try? handle.close() }
        let current = try handle.seekToEnd()
        if current < target {
            try handle.truncate(atOffset: target)
        }
    }

    func delete() throws {
        try FileManager.default.removeItem(at: url)
    }


    private func snapshotDirectory(_ id: UUID) -> URL {
        snapshotsURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func listSnapshots() -> [Snapshot] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: snapshotsURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return items.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("snapshot.json")) else { return nil }
            return try? decoder.decode(Snapshot.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func createSnapshot(named name: String) throws -> Snapshot {
        let fm = FileManager.default
        let snapshot = Snapshot(name: name)
        let dir = snapshotDirectory(snapshot.id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try fm.copyItem(at: diskURL, to: dir.appendingPathComponent("Disk.img"))
            try fm.copyItem(at: nvramURL, to: dir.appendingPathComponent("NVRAM"))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: dir.appendingPathComponent("snapshot.json"))
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
        return snapshot
    }

    func restoreSnapshot(_ snapshot: Snapshot) throws {
        let fm = FileManager.default
        let dir = snapshotDirectory(snapshot.id)
        let savedDisk = dir.appendingPathComponent("Disk.img")
        let savedNVRAM = dir.appendingPathComponent("NVRAM")
        guard fm.fileExists(atPath: savedDisk.path), fm.fileExists(atPath: savedNVRAM.path) else {
            throw LinMOError.message("ไฟล์ของ snapshot ไม่ครบ")
        }

        let tempDisk = url.appendingPathComponent("Disk.img.restoring")
        let tempNVRAM = url.appendingPathComponent("NVRAM.restoring")
        try? fm.removeItem(at: tempDisk)
        try? fm.removeItem(at: tempNVRAM)
        try fm.copyItem(at: savedDisk, to: tempDisk)
        try fm.copyItem(at: savedNVRAM, to: tempNVRAM)
        _ = try fm.replaceItemAt(diskURL, withItemAt: tempDisk)
        _ = try fm.replaceItemAt(nvramURL, withItemAt: tempNVRAM)
    }

    func deleteSnapshot(_ snapshot: Snapshot) throws {
        try FileManager.default.removeItem(at: snapshotDirectory(snapshot.id))
    }
}
