import Foundation

/// Owns the scripture database lifecycle: open → migrate → import bundled packages → import downloaded packages.
/// Initialization happens once, lazily, on first use; a failure is not cached so callers can retry.
/// Downloaded packages live as files in `downloadedPackagesDirectory`, so the database can always be rebuilt
/// from bundled + downloaded files without the network.
actor DatabaseManager {
    struct BundledPackage: Sendable {
        let id: String
        let url: URL
    }

    static let fileName = "scripture.sqlite"

    private let location: SQLiteConnection.Location
    private let packages: [BundledPackage]
    private let downloadedPackagesDirectory: URL?
    private let migrator: DatabaseMigrator
    private var ready: SQLiteConnection?
    private var opening: Task<SQLiteConnection, any Error>?

    init(
        location: SQLiteConnection.Location,
        bundledPackages: [BundledPackage],
        downloadedPackagesDirectory: URL? = nil,
        migrator: DatabaseMigrator = ScriptureSchema.migrator
    ) {
        self.location = location
        self.packages = bundledPackages
        self.downloadedPackagesDirectory = downloadedPackagesDirectory
        self.migrator = migrator
    }

    func connection() async throws(AppError) -> SQLiteConnection {
        if let ready { return ready }
        let task: Task<SQLiteConnection, any Error>
        if let opening {
            task = opening
        } else {
            let location = location, packages = packages, migrator = migrator, downloads = downloadedPackagesDirectory
            task = Task {
                try await Self.open(location: location, packages: packages, downloads: downloads, migrator: migrator)
            }
            opening = task
        }
        do {
            let db = try await task.value
            ready = db
            opening = nil
            return db
        } catch {
            opening = nil
            Log.database.error("Opening the scripture database failed: \(String(describing: error), privacy: .public)")
            throw (error as? AppError) ?? .database(String(describing: error))
        }
    }

    private static func open(
        location: SQLiteConnection.Location,
        packages: [BundledPackage],
        downloads: URL?,
        migrator: DatabaseMigrator
    ) async throws(AppError) -> SQLiteConnection {
        if case .file(let url) = location {
            try prepareDirectory(for: url)
        }
        let db = try SQLiteConnection(location: location)
        try await migrator.migrate(db)
        let importer = ContentImporter(database: db)
        for package in packages {
            let data: Data
            do {
                data = try Data(contentsOf: package.url)
            } catch {
                throw .contentNotFound("\(package.id): \(error)")
            }
            try await importer.importPackage(id: package.id, data: data)
        }
        // A downloaded file that no longer validates is skipped (and stays out of the database) rather than
        // blocking the whole library; the download screen offers to remove or re-download it.
        for file in PackageFileStore.packageFiles(in: downloads) {
            do {
                let data = try Data(contentsOf: file.url)
                try await importer.importPackage(id: file.id, data: data, role: .downloaded)
            } catch {
                Log.downloads.error("Skipped downloaded package \(file.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return db
    }

    // MARK: Downloaded packages

    /// Imports a verified downloaded package; it supersedes the bundled sample of its collection.
    @discardableResult
    func installDownloadedPackage(id: String, data: Data) async throws(AppError) -> ContentImporter.Outcome {
        try await ContentImporter(database: connection()).importPackage(id: id, data: data, role: .downloaded)
    }

    /// Removes a downloaded package and restores the bundled sample it had superseded.
    func removeDownloadedPackage(id: String) async throws(AppError) {
        let db = try await connection()
        let importer = ContentImporter(database: db)
        try await importer.removePackage(id: id)
        for package in packages {
            guard let data = try? Data(contentsOf: package.url) else { throw .contentNotFound(package.id) }
            try await importer.importPackage(id: package.id, data: data, role: .bundled, force: true)
        }
    }

    /// Bytes used by the database file (and its WAL/SHM sidecars); zero for in-memory databases.
    func databaseSize() -> Int64 {
        guard case .file(let url) = location else { return 0 }
        return ["", "-wal", "-shm"].reduce(0) { total, suffix in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path + suffix)
            return total + ((attributes?[.size] as? Int64) ?? 0)
        }
    }

    /// The database is rebuilt from bundled/downloaded packages, so it is excluded from backups.
    private static func prepareDirectory(for url: URL) throws(AppError) {
        var directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        } catch {
            throw .database("Cannot prepare \(directory.path): \(error)")
        }
    }

    static func defaultFileURL(fileManager: FileManager = .default) throws(AppError) -> URL {
        do {
            return try fileManager
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "SacredWisdom", directoryHint: .isDirectory)
                .appending(path: fileName)
        } catch {
            throw .database("Application Support unavailable: \(error)")
        }
    }
}
