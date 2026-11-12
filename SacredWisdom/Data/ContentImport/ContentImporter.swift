import CryptoKit
import Foundation

/// Imports a content package (the `SampleLibraryDTO` JSON format) into the scripture database.
///
/// * Validation reuses `SampleLibraryIndex`: an invalid package is rejected before anything is written.
/// * The whole import is one transaction: the database never holds half a package.
/// * Re-importing an unchanged package (same SHA-256) is a no-op unless forced; a changed package replaces
///   every collection it previously owned, including their search index rows.
/// * Ownership: a *downloaded* package may take over a collection owned by a *bundled* package (a full
///   chapter supersedes the sample); a bundled package never overwrites a downloaded collection. Any other
///   overlap is a conflict and the import is rejected.
struct ContentImporter: Sendable {
    enum Outcome: Equatable, Sendable {
        case imported(passages: Int)
        case alreadyCurrent
    }

    enum Role: String, Sendable {
        case bundled, downloaded
    }

    let database: SQLiteConnection

    @discardableResult
    func importPackage(
        id packageID: String, data: Data, role: Role = .bundled, force: Bool = false, now: Date = Date()
    ) async throws(AppError) -> Outcome {
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let existing = try await database.query("SELECT checksum FROM content_packages WHERE id = ?;", [.text(packageID)])
        if !force, try existing.first?.string("checksum") == checksum {
            return .alreadyCurrent
        }

        let dto = try SampleLibraryDTO.decode(from: data)
        let index = try SampleLibraryIndex(dto)
        var statements = Self.removal(packageID: packageID)
        statements += Self.shared(dto: dto, index: index)
        var passageCount = 0
        for collection in index.collections {
            switch try await ownership(of: collection.id, incoming: packageID, role: role) {
            case .free:
                break
            case .supersede(let owner):
                statements += Self.removal(collectionID: collection.id, ownedBy: owner)
            case .keepExisting:
                continue
            }
            statements += Self.collection(collection, packageID: packageID, index: index)
            passageCount += index.readingOrder[collection.id]?.count ?? 0
        }
        statements.append(SQLStatement(
            """
            INSERT INTO content_packages (id, checksum, schema_version, imported_at, role) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET checksum = excluded.checksum, schema_version = excluded.schema_version,
                imported_at = excluded.imported_at, role = excluded.role;
            """,
            [.text(packageID), .text(checksum), .integer(dto.schemaVersion), .real(now.timeIntervalSince1970), .text(role.rawValue)]
        ))
        try await database.transaction(statements)
        return .imported(passages: passageCount)
    }

    /// Deletes a package's collections (cascading to passages, texts and theme links), its search rows and its
    /// record. Shared rows (religions, sources, themes) stay.
    func removePackage(id packageID: String) async throws(AppError) {
        try await database.transaction(Self.removal(packageID: packageID) + [
            SQLStatement("DELETE FROM content_packages WHERE id = ?;", [.text(packageID)]),
        ])
    }

    private enum Ownership {
        case free
        case supersede(owner: String)
        case keepExisting
    }

    private func ownership(of collectionID: String, incoming: String, role: Role) async throws(AppError) -> Ownership {
        let rows = try await database.query("""
            SELECT c.package_id AS owner, COALESCE(p.role, 'bundled') AS role
            FROM scripture_collections c LEFT JOIN content_packages p ON p.id = c.package_id
            WHERE c.id = ?;
            """, [.text(collectionID)])
        guard let row = rows.first else { return .free }
        let owner = try row.string("owner")
        if owner == incoming { return .free } // already removed by this import's own removal step
        let ownerRole = Role(rawValue: try row.string("role")) ?? .bundled
        switch (role, ownerRole) {
        case (.downloaded, .bundled): return .supersede(owner: owner)
        case (.bundled, .downloaded): return .keepExisting
        default: throw .contentCorrupted("Collection \(collectionID) already belongs to package \(owner)")
        }
    }

    // MARK: Statement builders

    private static func removal(packageID: String) -> [SQLStatement] {
        [
            SQLStatement("DELETE FROM passage_search WHERE collection_id IN (SELECT id FROM scripture_collections WHERE package_id = ?);", [.text(packageID)]),
            SQLStatement("DELETE FROM scripture_collections WHERE package_id = ?;", [.text(packageID)]),
        ]
    }

    private static func removal(collectionID: String, ownedBy owner: String) -> [SQLStatement] {
        [
            SQLStatement("DELETE FROM passage_search WHERE collection_id = ?;", [.text(collectionID)]),
            SQLStatement("DELETE FROM scripture_collections WHERE id = ? AND package_id = ?;", [.text(collectionID), .text(owner)]),
        ]
    }

    private static func shared(dto: SampleLibraryDTO, index: SampleLibraryIndex) -> [SQLStatement] {
        let religions = index.religions.map { r in
            SQLStatement(
                """
                INSERT INTO religions (id, name, description, icon_name, tint_key, sort_order) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, description = excluded.description,
                    icon_name = excluded.icon_name, tint_key = excluded.tint_key, sort_order = excluded.sort_order;
                """,
                [.text(r.id), .text(r.name), .text(r.summary), .text(r.emblem), .text(r.tintKey), .integer(r.sortOrder)]
            )
        }
        let sources = dto.sources.map { s in
            SQLStatement(
                """
                INSERT INTO content_sources (id, source_name, source_url, license, attribution_text) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET source_name = excluded.source_name, source_url = excluded.source_url,
                    license = excluded.license, attribution_text = excluded.attribution_text;
                """,
                [.text(s.id), .text(s.name), .text(s.url), .text(s.license), .text(s.attribution)]
            )
        }
        let themes = index.themes.map { t in
            SQLStatement(
                "INSERT INTO themes (id, name) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name;",
                [.text(t.id), .text(t.name)]
            )
        }
        return religions + sources + themes
    }

    private static func collection(_ c: ScriptureCollection, packageID: String, index: SampleLibraryIndex) -> [SQLStatement] {
        var statements = [SQLStatement(
            """
            INSERT INTO scripture_collections (id, religion_id, name, structure_description, languages, availability,
                original_language, original_source_id, default_translation_id, package_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [.text(c.id), .text(c.religionID), .text(c.name), .text(c.structureDescription),
             .text(c.languages.joined(separator: ",")), .text(c.availability.rawValue), .text(c.originalLanguage),
             .text(c.originalSource?.id), .text(c.defaultTranslationID), .text(packageID)]
        )]
        for (order, t) in (index.translationsByCollection[c.id] ?? []).enumerated() {
            statements.append(SQLStatement(
                """
                INSERT INTO translations (id, collection_id, name, language_code, translator, year, source_id, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                [.text(t.id), .text(c.id), .text(t.name), .text(t.languageCode), .text(t.translator),
                 .integer(t.year), .text(t.source.id), .integer(order)]
            ))
        }
        for book in index.booksByCollection[c.id] ?? [] {
            statements.append(SQLStatement(
                "INSERT INTO scripture_books (id, collection_id, title, division, sequence_number) VALUES (?, ?, ?, ?, ?);",
                [.text(book.id), .text(c.id), .text(book.title), .text(book.division), .integer(book.sequence)]
            ))
            for section in index.sectionsByBook[book.id] ?? [] {
                statements.append(SQLStatement(
                    "INSERT INTO scripture_sections (id, book_id, title, sequence_number) VALUES (?, ?, ?, ?);",
                    [.text(section.id), .text(book.id), .text(section.title), .integer(section.sequence)]
                ))
                for passage in index.passagesBySection[section.id] ?? [] {
                    statements += Self.passage(passage, book: book, section: section, index: index)
                }
            }
        }
        return statements
    }

    private static func passage(
        _ p: ScripturePassage, book: ScriptureBook, section: ScriptureSection, index: SampleLibraryIndex
    ) -> [SQLStatement] {
        var statements = [SQLStatement(
            """
            INSERT INTO scripture_passages (id, collection_id, book_id, section_id, reference, original_text,
                sequence_number, reading_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [.text(p.id), .text(p.collectionID), .text(book.id), .text(section.id), .text(p.reference),
             .text(p.originalText), .integer(p.sequence), .integer(index.readingPosition[p.id] ?? 0)]
        )]
        for (order, themeID) in (index.themeIDsByPassage[p.id] ?? []).enumerated() {
            statements.append(SQLStatement(
                "INSERT INTO passage_themes (passage_id, theme_id, sort_order) VALUES (?, ?, ?);",
                [.text(p.id), .text(themeID), .integer(order)]
            ))
        }
        for text in p.texts {
            statements.append(SQLStatement(
                "INSERT INTO passage_texts (passage_id, translation_id, text) VALUES (?, ?, ?);",
                [.text(p.id), .text(text.translation.id), .text(text.text)]
            ))
            statements.append(SQLStatement(
                """
                INSERT INTO passage_search (passage_id, translation_id, collection_id, religion_id, language_code,
                    original_text, translated_text, book_title, section_title, reference)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                // Searchable columns hold folded text (see SearchTextNormalizer); display text is read from
                // passage_texts and scripture_passages, never from this table.
                [.text(p.id), .text(text.translation.id), .text(p.collectionID), .text(p.religionID),
                 .text(text.translation.languageCode), .text(fold(p.originalText ?? "")), .text(fold(text.text)),
                 .text(fold(book.title)), .text(fold(section.title)), .text(fold(p.reference))]
            ))
        }
        return statements
    }

    private static func fold(_ text: String) -> String {
        SearchTextNormalizer.normalize(text)
    }
}
