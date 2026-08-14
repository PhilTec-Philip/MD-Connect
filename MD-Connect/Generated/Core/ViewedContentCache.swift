import Foundation

/// Simple on-disk cache for content the user has actually viewed (wiki pages,
/// documents). Unlike the removed offline-caching feature it has no toggles,
/// budget or bulk download — viewed pages are stored automatically and can be
/// cleared with a single button in the account menu.
final class ViewedContentCache {
    static let shared = ViewedContentCache()

    private let directory: URL
    private let fileManager = FileManager.default

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = caches.appendingPathComponent("ViewedContent", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Stores a serialized payload (e.g. `serializedBytes()`) under a stable key.
    func store(_ data: Data, for key: String) {
        guard !data.isEmpty else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    /// Returns the stored payload for `key`, or `nil` if none is cached.
    func load(for key: String) -> Data? {
        let url = url(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Removes every cached payload.
    func clear() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    /// Number of cached payloads.
    var count: Int {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return 0 }
        return files.count
    }

    /// Total size in bytes of all cached payloads.
    var totalBytes: Int {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return total }
            return total + (values.fileSize ?? 0)
        }
    }

    private func url(for key: String) -> URL {
        let safeKey = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return directory.appendingPathComponent(String(safeKey), isDirectory: false)
    }
}
