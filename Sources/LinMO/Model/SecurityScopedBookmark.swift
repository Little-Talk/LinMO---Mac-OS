import Foundation

enum AppEnvironment {
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
}

enum SecurityScopedBookmark {
    static func make(for url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        return AppEnvironment.isSandboxed ? nil : try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
            return (url, stale)
        }
        if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            return (url, stale)
        }
        return nil
    }
}

final class SecurityScopedAccess {
    private var urls: [URL] = []

    func begin(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            urls.append(url)
        }
    }

    func endAll() {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
        urls.removeAll()
    }

    deinit { endAll() }
}
