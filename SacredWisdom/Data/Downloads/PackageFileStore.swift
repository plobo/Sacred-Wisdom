import CryptoKit
import Foundation

/// Downloaded packages on disk: `<id>.json` (the package) and `<id>.entry.json` (its manifest entry, so the
/// download screen works offline). Writes are atomic. The directory is excluded from backup (re-downloadable).
struct PackageFileStore: Sendable {
    struct InstalledPackage: Equatable, Sendable {
        let entry: ManifestEntry
        let bytes: Int64
    }

    let directory: URL

    static func defaultDirectory(fileManager: FileManager = .default) throws(AppError) -> URL {
        try DatabaseManager.defaultFileURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appending(path: "Packages", directoryHint: .isDirectory)
    }

    /// Package files the database should import at launch. Static so `DatabaseManager` can use it without a store.
    static func packageFiles(in directory: URL?) -> [(id: String, url: URL)] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.sorted()
            .filter { $0.hasSuffix(".json") && !$0.hasSuffix(".entry.json") }
            .map { (String($0.dropLast(".json".count)), directory.appending(path: $0)) }
    }

    func installed() -> [InstalledPackage] {
        Self.packageFiles(in: directory).compactMap { file in
            guard let data = try? Data(contentsOf: entryURL(file.id)),
                  let entry = try? JSONDecoder().decode(ManifestEntry.self, from: data) else { return nil }
            return InstalledPackage(entry: entry, bytes: Self.size(of: file.url) + Self.size(of: entryURL(file.id)))
        }
    }

    func save(_ data: Data, entry: ManifestEntry) throws(AppError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var dir = directory
            try dir.setResourceValues(values)
            try data.write(to: packageURL(entry.id), options: .atomic)
            try JSONEncoder().encode(entry).write(to: entryURL(entry.id), options: .atomic)
        } catch {
            remove(id: entry.id)
            throw .database("Could not save package \(entry.id): \(error)")
        }
    }

    func remove(id: String) {
        try? FileManager.default.removeItem(at: packageURL(id))
        try? FileManager.default.removeItem(at: entryURL(id))
    }

    var totalBytes: Int64 { installed().reduce(0) { $0 + $1.bytes } }

    func packageURL(_ id: String) -> URL { directory.appending(path: "\(id).json") }
    private func entryURL(_ id: String) -> URL { directory.appending(path: "\(id).entry.json") }

    private static func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64) ?? 0
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
