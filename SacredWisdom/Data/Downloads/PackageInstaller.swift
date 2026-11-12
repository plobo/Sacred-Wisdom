import Foundation

/// Verifies a downloaded file against its manifest entry and installs it. Nothing is stored or imported unless
/// every check passes: size, SHA-256, schema, structural validation, and that it contains exactly the
/// collection the manifest promised.
struct PackageInstaller: Sendable {
    enum Rejection: Error, Equatable, Sendable {
        case sizeMismatch(expected: Int, actual: Int)
        case checksumMismatch
        case schemaMismatch
        case wrongCollection
        case invalidContent(String)

        var userMessage: String {
            switch self {
            case .sizeMismatch, .checksumMismatch:
                String(localized: "The download was incomplete or damaged and was not installed.")
            case .schemaMismatch, .wrongCollection, .invalidContent:
                String(localized: "The package didn’t pass validation and was not installed.")
            }
        }
    }

    let store: PackageFileStore
    let database: DatabaseManager

    /// Nil when the data is exactly the package the manifest describes.
    static func verify(_ data: Data, against entry: ManifestEntry) -> Rejection? {
        guard data.count == entry.fileSize else { return .sizeMismatch(expected: entry.fileSize, actual: data.count) }
        guard PackageFileStore.sha256(data) == entry.sha256 else { return .checksumMismatch }
        let dto: SampleLibraryDTO
        do {
            dto = try SampleLibraryDTO.decode(from: data)
            _ = try SampleLibraryIndex(dto)
        } catch {
            return .invalidContent(String(describing: error))
        }
        guard dto.schemaVersion == entry.schemaVersion else { return .schemaMismatch }
        guard dto.collections.map(\.id) == [entry.collectionID] else { return .wrongCollection }
        return nil
    }

    /// Verifies, saves, then imports. If the import fails the saved files are removed again.
    func install(fileAt url: URL, entry: ManifestEntry) async throws -> Void {
        defer { try? FileManager.default.removeItem(at: url) }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw Rejection.invalidContent("unreadable file") }
        if let rejection = Self.verify(data, against: entry) { throw rejection }
        try store.save(data, entry: entry)
        do {
            try await database.installDownloadedPackage(id: entry.id, data: data)
        } catch {
            store.remove(id: entry.id)
            throw error
        }
    }

    func uninstall(id: String) async throws(AppError) {
        try await database.removeDownloadedPackage(id: id)
        store.remove(id: id)
    }
}
