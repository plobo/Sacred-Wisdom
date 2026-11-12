import Foundation

/// Scripture repository backed by the SQLite database. Works entirely offline.
struct SQLiteScriptureRepository: ReligionRepository, ScriptureRepository, PassageRepository, RelatedPassageRepository {
    let database: DatabaseManager

    // MARK: ReligionRepository

    func fetchReligions() async throws(AppError) -> [Religion] {
        var religions: [Religion] = []
        for row in try await query("SELECT * FROM religions ORDER BY sort_order;") {
            religions.append(Religion(
                id: try row.string("id"), name: try row.string("name"), summary: try row.string("description"),
                emblem: try row.string("icon_name"), tintKey: try row.string("tint_key"), sortOrder: try row.int("sort_order")
            ))
        }
        return religions
    }

    func fetchCollections() async throws(AppError) -> [ScriptureCollection] {
        try await collections(where: "1 = 1", [])
    }

    // MARK: ScriptureRepository

    func collection(id: String) async throws(AppError) -> ScriptureCollection {
        try Self.require(try await collections(where: "c.id = ?", [.text(id)]).first, "collection \(id)")
    }

    func translations(collectionID: String) async throws(AppError) -> [Translation] {
        let rows = try await query("""
            SELECT \(Self.translationColumns) FROM translations t JOIN content_sources s ON s.id = t.source_id
            WHERE t.collection_id = ? ORDER BY t.sort_order;
            """, [.text(collectionID)])
        var result: [Translation] = []
        for row in rows { result.append(try Self.translation(row)) }
        return result
    }

    func books(collectionID: String) async throws(AppError) -> [ScriptureBook] {
        try await books(where: "collection_id = ?", [.text(collectionID)])
    }

    func book(id: String) async throws(AppError) -> ScriptureBook {
        try Self.require(try await books(where: "id = ?", [.text(id)]).first, "book \(id)")
    }

    func sections(bookID: String) async throws(AppError) -> [ScriptureSection] {
        try await sections(where: "s.book_id = ?", [.text(bookID)])
    }

    func section(id: String) async throws(AppError) -> ScriptureSection {
        try Self.require(try await sections(where: "s.id = ?", [.text(id)]).first, "section \(id)")
    }

    func passages(sectionID: String) async throws(AppError) -> [ScripturePassage] {
        try await passages(where: "p.section_id = ?", [.text(sectionID)])
    }

    func passage(id: String) async throws(AppError) -> ScripturePassage {
        try Self.require(try await passages(where: "p.id = ?", [.text(id)]).first, "passage \(id)")
    }

    /// One query for passages and one for their texts, instead of two per passage.
    func passages(ids: [String]) async throws(AppError) -> [ScripturePassage] {
        guard !ids.isEmpty else { return [] }
        let unique = Array(Set(ids))
        let placeholders = Array(repeating: "?", count: unique.count).joined(separator: ", ")
        let found = try await passages(where: "p.id IN (\(placeholders))", unique.map { .text($0) })
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    func adjacentPassageID(to passageID: String, direction: PassageDirection) async throws(AppError) -> String? {
        let current = try Self.require(
            try await query("SELECT collection_id, reading_order FROM scripture_passages WHERE id = ?;", [.text(passageID)]).first,
            "passage \(passageID)"
        )
        let target = try current.int("reading_order") + (direction == .next ? 1 : -1)
        return try await query(
            "SELECT id FROM scripture_passages WHERE collection_id = ? AND reading_order = ?;",
            [.text(try current.string("collection_id")), .integer(target)]
        ).first?.optionalString("id")
    }

    // MARK: PassageRepository

    func dailyPassage(on date: Date) async throws(AppError) -> ScripturePassage? {
        let pools = try await query("""
            SELECT r.id AS religion_id, COUNT(p.id) AS passage_count
            FROM religions r
            LEFT JOIN scripture_collections c ON c.religion_id = r.id
            LEFT JOIN scripture_passages p ON p.collection_id = c.id
            GROUP BY r.id ORDER BY r.sort_order;
            """)
        var sizes: [Int] = []
        for row in pools { sizes.append(try row.int("passage_count")) }
        guard let pick = DailyRotation.pick(day: DailyRotation.dayNumber(for: date), poolSizes: sizes) else { return nil }
        let religionID = try pools[pick.pool].string("religion_id")
        guard let id = try await query("""
            SELECT p.id FROM scripture_passages p JOIN scripture_collections c ON c.id = p.collection_id
            WHERE c.religion_id = ? ORDER BY c.id, p.reading_order LIMIT 1 OFFSET ?;
            """, [.text(religionID), .integer(pick.offset)]).first?.optionalString("id") else { return nil }
        return try await passage(id: id)
    }

    // MARK: RelatedPassageRepository

    func themes(passageID: String) async throws(AppError) -> [PassageTheme] {
        _ = try Self.require(
            try await query("SELECT id FROM scripture_passages WHERE id = ?;", [.text(passageID)]).first,
            "passage \(passageID)"
        )
        var result: [PassageTheme] = []
        for row in try await query("""
            SELECT t.id, t.name FROM passage_themes pt JOIN themes t ON t.id = pt.theme_id
            WHERE pt.passage_id = ? ORDER BY pt.sort_order;
            """, [.text(passageID)]) {
            result.append(PassageTheme(id: try row.string("id"), name: try row.string("name")))
        }
        return result
    }

    func relatedPassages(to passageID: String, limit: Int) async throws(AppError) -> [RelatedPassage] {
        let sourceThemes = try await themes(passageID: passageID)
        guard !sourceThemes.isEmpty, limit > 0 else { return [] }
        let rows = try await query("""
            SELECT other.passage_id AS passage_id, GROUP_CONCAT(other.theme_id) AS theme_ids, COUNT(*) AS shared
            FROM passage_themes mine
            JOIN passage_themes other ON other.theme_id = mine.theme_id
            JOIN scripture_passages p ON p.id = other.passage_id
            JOIN scripture_collections c ON c.id = p.collection_id
            JOIN religions r ON r.id = c.religion_id
            WHERE mine.passage_id = ?1
              AND c.religion_id != (SELECT sc.religion_id FROM scripture_passages sp
                                    JOIN scripture_collections sc ON sc.id = sp.collection_id WHERE sp.id = ?1)
            GROUP BY other.passage_id
            ORDER BY shared DESC, r.sort_order, c.id, p.reading_order
            LIMIT ?2;
            """, [.text(passageID), .integer(limit)])
        let religions = Dictionary(uniqueKeysWithValues: try await fetchReligions().map { ($0.id, $0) })
        var result: [RelatedPassage] = []
        for row in rows {
            let passage = try await passage(id: try row.string("passage_id"))
            let ids = Set(try row.string("theme_ids").split(separator: ",").map(String.init))
            guard let religion = religions[passage.religionID] else { throw .contentCorrupted("religion \(passage.religionID)") }
            result.append(RelatedPassage(passage: passage, religion: religion,
                                         sharedThemes: sourceThemes.filter { ids.contains($0.id) }))
        }
        return result
    }

    // MARK: Queries

    private func query(_ sql: String, _ bindings: [SQLiteValue] = []) async throws(AppError) -> [SQLiteRow] {
        try await database.connection().query(sql, bindings)
    }

    private func collections(where clause: String, _ bindings: [SQLiteValue]) async throws(AppError) -> [ScriptureCollection] {
        let rows = try await query("""
            SELECT c.*, s.id AS s_id, s.source_name AS s_name, s.source_url AS s_url,
                   s.license AS s_license, s.attribution_text AS s_attribution
            FROM scripture_collections c
            JOIN religions r ON r.id = c.religion_id
            LEFT JOIN content_sources s ON s.id = c.original_source_id
            WHERE \(clause) ORDER BY r.sort_order, c.id;
            """, bindings)
        var result: [ScriptureCollection] = []
        for row in rows {
            guard let availability = ScriptureCollection.Availability(rawValue: try row.string("availability")) else {
                throw .contentCorrupted("collection availability")
            }
            result.append(ScriptureCollection(
                id: try row.string("id"), religionID: try row.string("religion_id"), name: try row.string("name"),
                structureDescription: try row.string("structure_description"),
                languages: try row.string("languages").split(separator: ",").map(String.init),
                availability: availability, originalLanguage: try row.string("original_language"),
                originalSource: try Self.optionalSource(row), defaultTranslationID: try row.string("default_translation_id")
            ))
        }
        return result
    }

    private func books(where clause: String, _ bindings: [SQLiteValue]) async throws(AppError) -> [ScriptureBook] {
        var result: [ScriptureBook] = []
        for row in try await query("SELECT * FROM scripture_books WHERE \(clause) ORDER BY sequence_number;", bindings) {
            result.append(ScriptureBook(
                id: try row.string("id"), collectionID: try row.string("collection_id"), title: try row.string("title"),
                division: row.optionalString("division"), sequence: try row.int("sequence_number")
            ))
        }
        return result
    }

    private func sections(where clause: String, _ bindings: [SQLiteValue]) async throws(AppError) -> [ScriptureSection] {
        let rows = try await query("""
            SELECT s.*, b.collection_id FROM scripture_sections s JOIN scripture_books b ON b.id = s.book_id
            WHERE \(clause) ORDER BY s.sequence_number;
            """, bindings)
        var result: [ScriptureSection] = []
        for row in rows {
            result.append(ScriptureSection(
                id: try row.string("id"), bookID: try row.string("book_id"), collectionID: try row.string("collection_id"),
                title: try row.string("title"), sequence: try row.int("sequence_number")
            ))
        }
        return result
    }

    private func passages(where clause: String, _ bindings: [SQLiteValue]) async throws(AppError) -> [ScripturePassage] {
        let rows = try await query("""
            SELECT p.*, c.religion_id, c.original_language, c.default_translation_id,
                   s.id AS s_id, s.source_name AS s_name, s.source_url AS s_url,
                   s.license AS s_license, s.attribution_text AS s_attribution
            FROM scripture_passages p
            JOIN scripture_collections c ON c.id = p.collection_id
            LEFT JOIN content_sources s ON s.id = c.original_source_id
            WHERE \(clause) ORDER BY p.reading_order;
            """, bindings)
        guard !rows.isEmpty else { return [] }

        let textRows = try await query("""
            SELECT pt.passage_id, pt.text, \(Self.translationColumns)
            FROM passage_texts pt
            JOIN translations t ON t.id = pt.translation_id
            JOIN content_sources s ON s.id = t.source_id
            WHERE pt.passage_id IN (SELECT p.id FROM scripture_passages p WHERE \(clause))
            ORDER BY t.sort_order;
            """, bindings)
        var textsByPassage: [String: [PassageText]] = [:]
        for row in textRows {
            textsByPassage[try row.string("passage_id"), default: []]
                .append(PassageText(translation: try Self.translation(row), text: try row.string("text")))
        }

        var result: [ScripturePassage] = []
        for row in rows {
            let id = try row.string("id")
            let defaultID = try row.string("default_translation_id")
            var texts = textsByPassage[id] ?? []
            if let index = texts.firstIndex(where: { $0.translation.id == defaultID }), index > 0 {
                texts.insert(texts.remove(at: index), at: 0)
            }
            result.append(ScripturePassage(
                id: id, religionID: try row.string("religion_id"), collectionID: try row.string("collection_id"),
                bookID: try row.string("book_id"), sectionID: try row.string("section_id"),
                sequence: try row.int("sequence_number"), reference: try row.string("reference"),
                originalLanguage: try row.string("original_language"), originalText: row.optionalString("original_text"),
                originalSource: try Self.optionalSource(row), texts: texts
            ))
        }
        return result
    }

    // MARK: Row mapping

    private static let translationColumns = """
        t.id AS t_id, t.collection_id AS t_collection_id, t.name AS t_name, t.language_code AS t_language_code,
        t.translator AS t_translator, t.year AS t_year, s.id AS s_id, s.source_name AS s_name,
        s.source_url AS s_url, s.license AS s_license, s.attribution_text AS s_attribution
        """

    private static func translation(_ row: SQLiteRow) throws(AppError) -> Translation {
        Translation(
            id: try row.string("t_id"), collectionID: try row.string("t_collection_id"), name: try row.string("t_name"),
            languageCode: try row.string("t_language_code"), translator: try row.string("t_translator"),
            year: row.optionalInt("t_year"), source: try source(row)
        )
    }

    private static func source(_ row: SQLiteRow) throws(AppError) -> ContentSource {
        ContentSource(
            id: try row.string("s_id"), name: try row.string("s_name"),
            url: row.optionalString("s_url").flatMap(URL.init(string:)),
            license: try row.string("s_license"), attribution: try row.string("s_attribution")
        )
    }

    private static func optionalSource(_ row: SQLiteRow) throws(AppError) -> ContentSource? {
        row.optionalString("s_id") == nil ? nil : try source(row)
    }

    private static func require<T>(_ value: T?, _ what: String) throws(AppError) -> T {
        guard let value else { throw .contentNotFound(what) }
        return value
    }
}
