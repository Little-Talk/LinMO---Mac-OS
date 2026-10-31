import AppKit
import Foundation
import Virtualization

enum SharedTags {
    static let folder = "linmo"
    static let rosetta = "rosetta"
}

enum ConfigurationBuilder {
    @MainActor
    static func make(bundle: MachineBundle, config: MachineConfig) throws -> VZVirtualMachineConfiguration {
        let vz = VZVirtualMachineConfiguration()

        vz.cpuCount = min(
            max(config.cpuCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount),
            VZVirtualMachineConfiguration.maximumAllowedCPUCount
        )
        let requestedMemory = UInt64(config.memoryGB) * 1024 * 1024 * 1024
        vz.memorySize = min(
            max(requestedMemory, VZVirtualMachineConfiguration.minimumAllowedMemorySize),
            VZVirtualMachineConfiguration.maximumAllowedMemorySize
        )

        let platform = VZGenericPlatformConfiguration()
        let identifierData = try Data(contentsOf: bundle.machineIdentifierURL)
        guard let identifier = VZGenericMachineIdentifier(dataRepresentation: identifierData) else {
            throw LinMOError.message("ไฟล์รหัสเครื่องเสีย")
        }
        platform.machineIdentifier = identifier
        vz.platform = platform

        let bootLoader = VZEFIBootLoader()
        bootLoader.variableStore = VZEFIVariableStore(url: bundle.nvramURL)
        vz.bootLoader = bootLoader

        var storage: [VZStorageDeviceConfiguration] = [
            VZVirtioBlockDeviceConfiguration(
                attachment: try VZDiskImageStorageDeviceAttachment(url: bundle.diskURL, readOnly: false)
            )
        ]
        if config.attachCloudInitSeed, FileManager.default.fileExists(atPath: bundle.cloudInitSeedURL.path) {
            storage.append(
                VZVirtioBlockDeviceConfiguration(
                    attachment: try VZDiskImageStorageDeviceAttachment(url: bundle.cloudInitSeedURL, readOnly: true)
                )
            )
        }
        if let tools = try? GuestTools.ensureISO() {
            storage.append(
                VZVirtioBlockDeviceConfiguration(
                    attachment: try VZDiskImageStorageDeviceAttachment(url: tools, readOnly: true)
                )
            )
        }
        if let isoPath = config.installerISOPath {
            guard FileManager.default.fileExists(atPath: isoPath) else {
                throw LinMOError.message("หาไฟล์ ISO ไม่เจอ: \(isoPath) — ถ้าติดตั้งเสร็จแล้ว ให้กด \"ถอดแผ่นติดตั้ง\"")
            }
            storage.append(
                VZUSBMassStorageDeviceConfiguration(
                    attachment: try VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: isoPath), readOnly: true)
                )
            )
        }
        vz.storageDevices = storage

        let network = VZVirtioNetworkDeviceConfiguration()
        network.macAddress = bundle.macAddress()
        network.attachment = VZNATNetworkDeviceAttachment()
        vz.networkDevices = [network]

        let graphics = VZVirtioGraphicsDeviceConfiguration()
        let display = displaySize(hiDPI: config.hiDPI)
        graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(widthInPixels: display.width, heightInPixels: display.height)]
        vz.graphicsDevices = [graphics]

        vz.keyboards = [VZUSBKeyboardConfiguration()]
        vz.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        let sound = VZVirtioSoundDeviceConfiguration()
        let output = VZVirtioSoundDeviceOutputStreamConfiguration()
        output.sink = VZHostAudioOutputStreamSink()
        sound.streams = [output]
        vz.audioDevices = [sound]

        vz.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        vz.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

        let console = VZVirtioConsoleDeviceConfiguration()
        let spicePort = VZVirtioConsolePortConfiguration()
        spicePort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
        let spiceAgent = VZSpiceAgentPortAttachment()
        spiceAgent.sharesClipboard = true
        spicePort.attachment = spiceAgent
        console.ports[0] = spicePort
        vz.consoleDevices = [console]

        var directoryShares: [VZDirectorySharingDeviceConfiguration] = []
        if let folderPath = config.sharedFolderPath {
            let share = VZVirtioFileSystemDeviceConfiguration(tag: SharedTags.folder)
            share.share = VZSingleDirectoryShare(
                directory: VZSharedDirectory(url: URL(fileURLWithPath: folderPath, isDirectory: true), readOnly: false)
            )
            directoryShares.append(share)
        }
        if config.rosettaEnabled, RosettaSupport.availability == .installed {
            let share = VZVirtioFileSystemDeviceConfiguration(tag: SharedTags.rosetta)
            share.share = try VZLinuxRosettaDirectoryShare()
            directoryShares.append(share)
        }
        vz.directorySharingDevices = directoryShares

        vz.socketDevices = [VZVirtioSocketDeviceConfiguration()]

        return vz
    }

    @MainActor
    private static func displaySize(hiDPI: Bool) -> (width: Int, height: Int) {
        guard hiDPI else { return (1920, 1200) }
        let screen = NSScreen.screens.max { $0.frame.width * $0.backingScaleFactor < $1.frame.width * $1.backingScaleFactor }
        guard let screen else { return (3840, 2400) }
        let width = Int(screen.frame.width * screen.backingScaleFactor)
        let height = Int(screen.frame.height * screen.backingScaleFactor)
        return (min(max(width, 1920), 7680), min(max(height, 1200), 4320))
    }
}

enum RosettaSupport {
    enum Availability: Equatable {
        case notSupported, notInstalled, installed
    }

    static var availability: Availability {
        switch VZLinuxRosettaDirectoryShare.availability {
        case .installed: return .installed
        case .notInstalled: return .notInstalled
        default: return .notSupported
        }
    }

    static func install() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            VZLinuxRosettaDirectoryShare.installRosetta { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
