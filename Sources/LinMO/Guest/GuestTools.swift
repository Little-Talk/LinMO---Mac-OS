import Foundation

enum GuestTools {
    static var isoURL: URL {
        MachineBundle.appSupportDirectory.appendingPathComponent("LinMOTools-\(GuestFiles.version).iso")
    }

    static let installCommand = """
    sudo sh -c 'mkdir -p /mnt/linmo-tools; for d in /dev/vd? /dev/sr?; do mount -o ro "$d" /mnt/linmo-tools 2>/dev/null || continue; [ -e /mnt/linmo-tools/install.sh ] && break; umount /mnt/linmo-tools; done; sh /mnt/linmo-tools/install.sh; umount /mnt/linmo-tools'
    """

    @discardableResult
    static func ensureISO() throws -> URL {
        let fm = FileManager.default
        let url = isoURL
        if fm.fileExists(atPath: url.path) { return url }

        try fm.createDirectory(at: MachineBundle.appSupportDirectory, withIntermediateDirectories: true)
        if let old = try? fm.contentsOfDirectory(at: MachineBundle.appSupportDirectory, includingPropertiesForKeys: nil) {
            for file in old where file.lastPathComponent.hasPrefix("LinMOTools-") {
                try? fm.removeItem(at: file)
            }
        }

        let staging = fm.temporaryDirectory.appendingPathComponent("linmo-tools-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try GuestFiles.agent.write(to: staging.appendingPathComponent("linmo-agent.py"))
        try GuestFiles.install.write(to: staging.appendingPathComponent("install.sh"))

        if let binary = Bundle.main.url(forResource: "linmo-wayland-aarch64", withExtension: nil) {
            try fm.copyItem(at: binary, to: staging.appendingPathComponent("linmo-wayland-aarch64"))
        }
        let source = staging.appendingPathComponent("linmo-wayland-src", isDirectory: true)
        for (path, encoded) in GuestFiles.waylandSource {
            let destination = source.appendingPathComponent(path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(base64Encoded: encoded)?.write(to: destination)
        }
        try """
        LinMO Tools \(GuestFiles.version)

        ติดตั้ง agent สำหรับโหมดหน้าต่างแยก:
            sudo sh /mnt/linmo-tools/install.sh

        """.write(to: staging.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        try Shell.run("/usr/bin/hdiutil", [
            "makehybrid", "-iso", "-joliet",
            "-default-volume-name", "linmotools",
            "-o", url.path,
            staging.path,
        ])
        return url
    }
}
