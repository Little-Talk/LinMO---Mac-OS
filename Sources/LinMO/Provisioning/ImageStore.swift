import Foundation

enum ImageStore {
    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinMO", isDirectory: true)
    }

    static func cachedDisk(for distro: Distro) -> URL? {
        let url = preparedDiskURL(for: distro)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func preparedDiskURL(for distro: Distro) -> URL {
        cacheDirectory.appendingPathComponent(distro.id, isDirectory: true).appendingPathComponent("disk.raw")
    }

    static func prepareDisk(
        for distro: Distro,
        onPhase: @escaping @Sendable (ProvisioningPhase) -> Void
    ) async throws -> URL {
        if let cached = cachedDisk(for: distro) {
            return cached
        }

        let fm = FileManager.default
        let workDir = cacheDirectory.appendingPathComponent("\(distro.id).work", isDirectory: true)
        try? fm.removeItem(at: workDir)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        onPhase(.preparing)
        let image = try await ImageResolver.resolve(distro.source)
        let archive = workDir.appendingPathComponent(image.fileName)

        onPhase(.downloading(0))
        try await Downloader().download(from: image.url, to: archive) { fraction in
            onPhase(.downloading(fraction))
        }

        onPhase(.verifying)
        let actual = try await Task.detached(priority: .userInitiated) {
            try DiskConverters.hash(of: archive, algorithm: image.algorithm)
        }.value
        guard actual == image.expectedHash.lowercased() else {
            throw LinMOError.message("ไฟล์ที่ดาวน์โหลดเสียหาย (checksum ไม่ตรง) ลองใหม่อีกครั้ง")
        }

        onPhase(.extracting)
        let converted = workDir.appendingPathComponent("disk.raw")
        try await Task.detached(priority: .userInitiated) {
            switch image.format {
            case .tarXZ:
                let extractDir = workDir.appendingPathComponent("extract", isDirectory: true)
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
                try Shell.run("/usr/bin/tar", ["-xJf", archive.path, "-C", extractDir.path])
                guard let disk = ImageStore.largestFile(in: extractDir) else {
                    throw LinMOError.message("ไม่พบไฟล์ดิสก์ในไฟล์ที่ดาวน์โหลดมา")
                }
                try fm.moveItem(at: disk, to: converted)
            case .qcow2:
                try DiskConverters.convertQcow2(source: archive, destination: converted)
            case .rawXZ:
                try DiskConverters.decompressXZ(source: archive, destination: converted)
            }
        }.value

        let destination = preparedDiskURL(for: distro)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: converted, to: destination)
        return destination
    }


    struct CachedImage: Identifiable {
        let distro: Distro
        let bytes: Int64
        var id: String { distro.id }
    }

    static func cachedImages() -> [CachedImage] {
        DistroCatalog.all.compactMap { distro in
            guard cachedDisk(for: distro) != nil else { return nil }
            return CachedImage(
                distro: distro,
                bytes: allocatedSize(of: cacheDirectory.appendingPathComponent(distro.id, isDirectory: true))
            )
        }
    }

    static func totalCacheSize() -> Int64 {
        allocatedSize(of: cacheDirectory)
    }

    static func removeCache(for distro: Distro) throws {
        let dir = cacheDirectory.appendingPathComponent(distro.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    static func clearCache() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheDirectory.path) {
            try fm.removeItem(at: cacheDirectory)
        }
    }


    private static func allocatedSize(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    private static func largestFile(in directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return nil
        }
        var best: (url: URL, size: Int)?
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            if size > (best?.size ?? -1) {
                best = (url, size)
            }
        }
        return best?.url
    }
}


struct ResolvedImage: Sendable {
    let url: URL
    let expectedHash: String
    let algorithm: HashAlgorithm
    let format: ImageFormat

    var fileName: String { url.lastPathComponent }
}

enum ImageResolver {
    static func resolve(_ source: ImageSource) async throws -> ResolvedImage {
        switch source {
        case let .fixed(url, checksumsURL, algorithm, format):
            let (data, response) = try await URLSession.shared.data(from: checksumsURL)
            try checkHTTP(response)
            guard let hash = expectedHash(in: String(decoding: data, as: UTF8.self), for: url.lastPathComponent) else {
                throw LinMOError.message("ไม่พบค่า checksum ของ \(url.lastPathComponent)")
            }
            return ResolvedImage(url: url, expectedHash: hash, algorithm: algorithm, format: format)

        case .fedoraLatestCloud:
            return try await resolveFedora()
        }
    }

    private static func resolveFedora() async throws -> ResolvedImage {
        struct Entry: Decodable {
            let version: String
            let arch: String
            let link: String
            let variant: String?
            let subvariant: String?
            let sha256: String?
        }

        let url = URL(string: "https://fedoraproject.org/releases.json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try checkHTTP(response)
        let entries = try JSONDecoder().decode([Entry].self, from: data)

        let candidates = entries.compactMap { entry -> (version: Int, url: URL, sha: String)? in
            guard entry.arch == "aarch64",
                  entry.variant == "Cloud",
                  entry.subvariant == "Cloud_Base",
                  entry.link.hasSuffix(".raw.xz"),
                  let version = Int(entry.version),
                  let link = URL(string: entry.link),
                  let sha = entry.sha256, !sha.isEmpty else { return nil }
            return (version, link, sha)
        }
        guard let best = candidates.max(by: { $0.version < $1.version }) else {
            throw LinMOError.message("หาไฟล์ Fedora Cloud สำหรับ ARM64 ไม่เจอ")
        }
        return ResolvedImage(url: best.url, expectedHash: best.sha, algorithm: .sha256, format: .rawXZ)
    }

    private static func checkHTTP(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LinMOError.message("ดาวน์โหลดข้อมูลไม่สำเร็จ (HTTP \(http.statusCode))")
        }
    }

    static func expectedHash(in sums: String, for fileName: String) -> String? {
        for rawLine in sums.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("SHA"), let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"),
               let eq = line.lastIndex(of: "=") {
                let name = line[line.index(after: open)..<close]
                if name == fileName {
                    return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).lowercased()
                }
                continue
            }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let name = parts.last!.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if name == fileName {
                return parts[0].lowercased()
            }
        }
        return nil
    }
}


private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progress: ((Double) -> Void)?
    private var moveError: Error?

    func download(from source: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        self.destination = destination
        self.progress = progress
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            session.downloadTask(with: source).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destination else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            moveError = LinMOError.message("ดาวน์โหลดไม่สำเร็จ (HTTP \(http.statusCode))")
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result = error ?? moveError
        if let result {
            continuation?.resume(throwing: result)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
