import Foundation

struct DatabaseMigration: Sendable {
    let version: Int
    let name: String
    let sql: String
}

/// Applies ordered migrations, tracking progress in `PRAGMA user_version`.
/// Each migration runs in its own transaction together with the version bump.
struct DatabaseMigrator: Sendable {
    let migrations: [DatabaseMigration]

    var latestVersion: Int { migrations.map(\.version).max() ?? 0 }

    func currentVersion(of db: SQLiteConnection) async throws(AppError) -> Int {
        try await db.query("PRAGMA user_version;").first?.int("user_version") ?? 0
    }

    @discardableResult
    func migrate(_ db: SQLiteConnection) async throws(AppError) -> [Int] {
        let versions = migrations.map(\.version)
        guard versions == versions.sorted(), Set(versions).count == versions.count else {
            throw .database("Migrations must have unique, ascending versions")
        }
        let current = try await currentVersion(of: db)
        guard current <= latestVersion else {
            throw .database("Database version \(current) is newer than supported version \(latestVersion)")
        }
        var applied: [Int] = []
        for migration in migrations where migration.version > current {
            do {
                try await db.transaction(Self.statements(in: migration.sql) + [
                    SQLStatement("PRAGMA user_version = \(migration.version);"),
                ])
            } catch {
                throw .database("Migration \(migration.version) (\(migration.name)) failed: \(error)")
            }
            applied.append(migration.version)
        }
        return applied
    }

    /// Splits a schema script into statements. Scripts must not contain ';' inside literals.
    static func statements(in script: String) -> [SQLStatement] {
        script.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { SQLStatement($0 + ";") }
    }
}
