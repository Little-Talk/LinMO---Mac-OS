import Foundation

struct MachineConfig: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var cpuCount: Int = 2
    var memoryGB: Int = 4
    var diskGB: Int = 32
    var distroID: String?
    var installerISOPath: String?
    var attachCloudInitSeed: Bool = false
    var sharedFolderPath: String?
    var rosettaEnabled: Bool = false
    var firstBootCompleted: Bool = false
    var hiDPI: Bool = false
    var macTextInput: Bool = true
    var preferWayland: Bool = false
    var preset: Preset?
    var sharedFolderBookmark: Data?
    var installerISOBookmark: Data?
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Linux"
        cpuCount = try c.decodeIfPresent(Int.self, forKey: .cpuCount) ?? 2
        memoryGB = try c.decodeIfPresent(Int.self, forKey: .memoryGB) ?? 4
        diskGB = try c.decodeIfPresent(Int.self, forKey: .diskGB) ?? 32
        distroID = try c.decodeIfPresent(String.self, forKey: .distroID)
        installerISOPath = try c.decodeIfPresent(String.self, forKey: .installerISOPath)
        attachCloudInitSeed = try c.decodeIfPresent(Bool.self, forKey: .attachCloudInitSeed) ?? false
        sharedFolderPath = try c.decodeIfPresent(String.self, forKey: .sharedFolderPath)
        rosettaEnabled = try c.decodeIfPresent(Bool.self, forKey: .rosettaEnabled) ?? false
        firstBootCompleted = try c.decodeIfPresent(Bool.self, forKey: .firstBootCompleted) ?? false
        hiDPI = try c.decodeIfPresent(Bool.self, forKey: .hiDPI) ?? false
        macTextInput = try c.decodeIfPresent(Bool.self, forKey: .macTextInput) ?? true
        preferWayland = try c.decodeIfPresent(Bool.self, forKey: .preferWayland) ?? false
        preset = try? c.decodeIfPresent(Preset.self, forKey: .preset)
        sharedFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .sharedFolderBookmark)
        installerISOBookmark = try c.decodeIfPresent(Data.self, forKey: .installerISOBookmark)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct Snapshot: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
}

enum LinMOError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
