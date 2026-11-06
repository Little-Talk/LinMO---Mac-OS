import Foundation

enum Desktop: String, CaseIterable, Identifiable, Hashable {
    case xfce
    case gnome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xfce: return tr("XFCE (เบา เร็ว)", "XFCE (light and fast)")
        case .gnome: return tr("GNOME (สวย ทันสมัย ใช้ RAM มากกว่า)", "GNOME (polished and modern, uses more RAM)")
        }
    }
}

struct Distro: Identifiable, Hashable {
    enum Family: Hashable {
        case debian, ubuntu, fedora
    }

    let id: String
    let name: String
    let shortName: String
    let summary: String
    let family: Family
    let source: ImageSource
    let desktops: [Desktop]
    let approximateDownloadMB: Int
}

enum HashAlgorithm: Hashable {
    case sha256, sha512
}

enum ImageFormat: Hashable {
    case tarXZ
    case qcow2
    case rawXZ
}

enum ImageSource: Hashable {
    case fixed(url: URL, checksumsURL: URL, algorithm: HashAlgorithm, format: ImageFormat)
    case fedoraLatestCloud
}

enum DistroCatalog {
    static var all: [Distro] {
        [
            Distro(
                id: "debian-13",
                name: "Debian 13 (Trixie)",
                shortName: "Debian",
                summary: tr("เสถียร เบา — แนะนำสำหรับมือใหม่", "Stable and light. Recommended for beginners"),
                family: .debian,
                source: .fixed(
                    url: URL(string: "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.tar.xz")!,
                    checksumsURL: URL(string: "https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS")!,
                    algorithm: .sha512,
                    format: .tarXZ
                ),
                desktops: [.xfce, .gnome],
                approximateDownloadMB: 450
            ),
            Distro(
                id: "ubuntu-24.04",
                name: "Ubuntu 24.04 LTS",
                shortName: "Ubuntu",
                summary: tr("นิยมที่สุด หาวิธีแก้ปัญหาง่าย มีโปรแกรมให้เลือกเยอะ", "The most popular. Easy to find help and lots of software"),
                family: .ubuntu,
                source: .fixed(
                    url: URL(string: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img")!,
                    checksumsURL: URL(string: "https://cloud-images.ubuntu.com/noble/current/SHA256SUMS")!,
                    algorithm: .sha256,
                    format: .qcow2
                ),
                desktops: [.xfce, .gnome],
                approximateDownloadMB: 600
            ),
            Distro(
                id: "fedora-latest",
                name: tr("Fedora (รุ่นล่าสุด)", "Fedora (latest)"),
                shortName: "Fedora",
                summary: tr("ซอฟต์แวร์ใหม่ล่าสุด เหมาะกับสาย dev", "The newest software. Great for developers"),
                family: .fedora,
                source: .fedoraLatestCloud,
                desktops: [.xfce],
                approximateDownloadMB: 550
            ),
        ]
    }

    static func distro(id: String?) -> Distro? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
