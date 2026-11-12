import Foundation
import Testing
@testable import SacredWisdom

@Suite struct SQLiteConnectionTests {
    @Test func bindsAndReadsAllValueTypes() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        try await db.execute("CREATE TABLE t (i INTEGER, r REAL, s TEXT, n TEXT);")
        try await db.run("INSERT INTO t VALUES (?, ?, ?, ?);", [.integer(42), .real(1.5), .text("ਸਤਿ ﷽ שָׁלוֹם"), .null])
        let row = try #require(try await db.query("SELECT * FROM t;").first)
        #expect(try row.int("i") == 42)
        #expect(try row.double("r") == 1.5)
        #expect(try row.string("s") == "ਸਤਿ ﷽ שָׁלוֹם")
        #expect(row.optionalString("n") == nil)
        #expect(throws: AppError.self) { try row.string("n") }
    }

    @Test func wrongBindingCountAndBadSQLThrow() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        await #expect(throws: AppError.self) { try await db.run("SELECT ?;", []) }
        await #expect(throws: AppError.self) { try await db.query("SELEKT 1;") }
    }

    @Test func failedTransactionRollsBackEverything() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        try await db.execute("CREATE TABLE t (id TEXT PRIMARY KEY);")
        await #expect(throws: AppError.self) {
            try await db.transaction([
                SQLStatement("INSERT INTO t VALUES (?);", [.text("a")]),
                SQLStatement("INSERT INTO t VALUES (?);", [.text("a")]), // duplicate key
            ])
        }
        #expect(try await db.query("SELECT * FROM t;").isEmpty)
        // The connection remains usable after a rollback.
        try await db.transaction([SQLStatement("INSERT INTO t VALUES (?);", [.text("b")])])
        #expect(try await db.query("SELECT * FROM t;").count == 1)
    }

    @Test func foreignKeysAreEnforced() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        try await db.execute("CREATE TABLE p (id TEXT PRIMARY KEY); CREATE TABLE c (pid TEXT REFERENCES p(id));")
        await #expect(throws: AppError.self) { try await db.run("INSERT INTO c VALUES ('missing');") }
    }
}

@Suite struct DatabaseMigratorTests {
    private func tables(_ db: SQLiteConnection) async throws -> Set<String> {
        var names = Set<String>()
        for row in try await db.query("SELECT name FROM sqlite_master WHERE type IN ('table');") {
            names.insert(try row.string("name"))
        }
        return names
    }

    @Test func freshDatabaseReachesLatestSchemaIncludingFTS5() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        let applied = try await ScriptureSchema.migrator.migrate(db)
        #expect(applied == [1, 2, 3, 4, 5])
        #expect(try await ScriptureSchema.migrator.currentVersion(of: db) == 5)
        let names = try await tables(db)
        for table in ["religions", "content_sources", "scripture_collections", "translations", "scripture_books",
                      "scripture_sections", "scripture_passages", "passage_texts", "content_packages", "passage_search",
                      "themes", "passage_themes"] {
            #expect(names.contains(table), "missing \(table)")
        }
    }

    @Test func migratingTwiceIsANoOp() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        try await ScriptureSchema.migrator.migrate(db)
        #expect(try await ScriptureSchema.migrator.migrate(db).isEmpty)
    }

    @Test func upgradesFromAnOlderVersion() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        try await DatabaseMigrator(migrations: Array(ScriptureSchema.migrations.prefix(1))).migrate(db)
        #expect(try await !tables(db).contains("passage_search"))
        #expect(try await ScriptureSchema.migrator.migrate(db) == [2, 3, 4, 5])
        #expect(try await tables(db).contains("passage_search"))
    }

    @Test func refusesDatabaseNewerThanSupported() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        try await db.execute("PRAGMA user_version = 99;")
        await #expect(throws: AppError.self) { try await ScriptureSchema.migrator.migrate(db) }
    }

    @Test func failingMigrationRollsBackAndKeepsVersion() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        let migrator = DatabaseMigrator(migrations: [
            DatabaseMigration(version: 1, name: "ok", sql: "CREATE TABLE a (x);"),
            DatabaseMigration(version: 2, name: "broken", sql: "CREATE TABLE b (x); CREATE TABLE a (x);"),
        ])
        await #expect(throws: AppError.self) { try await migrator.migrate(db) }
        #expect(try await migrator.currentVersion(of: db) == 1)
        #expect(try await !tables(db).contains("b"))
    }

    @Test func rejectsOutOfOrderMigrations() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        let migrator = DatabaseMigrator(migrations: [
            DatabaseMigration(version: 2, name: "b", sql: "CREATE TABLE b (x);"),
            DatabaseMigration(version: 1, name: "a", sql: "CREATE TABLE a (x);"),
        ])
        await #expect(throws: AppError.self) { try await migrator.migrate(db) }
    }
}

@Suite struct ContentImporterTests {
    private func count(_ db: SQLiteConnection, _ table: String) async throws -> Int {
        try #require(try await db.query("SELECT COUNT(*) AS n FROM \(table);").first).int("n")
    }

    private func migrated() async throws -> SQLiteConnection {
        let db = try SQLiteConnection(location: .inMemory)
        try await ScriptureSchema.migrator.migrate(db)
        return db
    }

    @Test func importsEveryRowAndIndexesEveryText() async throws {
        let db = try await migrated()
        let outcome = try await ContentImporter(database: db).importPackage(id: "fixture", data: Fixtures.libraryData())
        #expect(outcome == .imported(passages: 5))
        #expect(try await count(db, "religions") == 2)
        #expect(try await count(db, "scripture_collections") == 2)
        #expect(try await count(db, "translations") == 3)
        #expect(try await count(db, "scripture_passages") == 5)
        #expect(try await count(db, "passage_texts") == 7)
        #expect(try await count(db, "passage_search") == 7)
        #expect(try await count(db, "themes") == 2)
        #expect(try await count(db, "passage_themes") == 6)
    }

    @Test func reimportReplacesThemeLinksWithoutLeftovers() async throws {
        let db = try await migrated()
        let importer = ContentImporter(database: db)
        try await importer.importPackage(id: "fixture", data: Fixtures.libraryData())
        let retagged = try Fixtures.libraryData { json in
            json["themes"] = [["id": "th1", "name": "Renamed"]]
            var passages = json["passages"] as? [[String: Any]] ?? []
            for index in passages.indices {
                passages[index]["themes"] = passages[index]["id"] as? String == "p1" ? ["th1"] : []
            }
            json["passages"] = passages
        }
        try await importer.importPackage(id: "fixture", data: retagged)
        #expect(try await count(db, "passage_themes") == 1)
        #expect(try await db.query("SELECT name FROM themes WHERE id = 'th1';").first?.string("name") == "Renamed")
    }

    /// The importer always runs on a fully migrated database, so the v3-era import is simulated by its record.
    @Test func upgradingToThemesSchemaForcesReimportOfAnUnchangedPackage() async throws {
        let db = try SQLiteConnection(location: .inMemory)
        try await DatabaseMigrator(migrations: Array(ScriptureSchema.migrations.prefix(3))).migrate(db)
        let data = try Fixtures.libraryData()
        let checksum = PackageFileStore.sha256(data)
        try await db.run("INSERT INTO content_packages (id, checksum, schema_version, imported_at) VALUES (?, ?, 2, 0);",
                         [.text("fixture"), .text(checksum)])

        #expect(try await ScriptureSchema.migrator.migrate(db) == [4, 5])
        #expect(try await count(db, "content_packages") == 0)
        let importer = ContentImporter(database: db)
        #expect(try await importer.importPackage(id: "fixture", data: data) == .imported(passages: 5))
        #expect(try await importer.importPackage(id: "fixture", data: data) == .alreadyCurrent)
        #expect(try await count(db, "passage_themes") == 6)
    }

    @Test func unchangedPackageIsSkipped() async throws {
        let db = try await migrated()
        let importer = ContentImporter(database: db)
        try await importer.importPackage(id: "fixture", data: Fixtures.libraryData())
        #expect(try await importer.importPackage(id: "fixture", data: Fixtures.libraryData()) == .alreadyCurrent)
    }

    @Test func changedPackageReplacesItsContentAndSearchRows() async throws {
        let db = try await migrated()
        let importer = ContentImporter(database: db)
        try await importer.importPackage(id: "fixture", data: Fixtures.libraryData())
        let smaller = try Fixtures.libraryData { json in
            json["passages"] = (json["passages"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != "p4" }
        }
        #expect(try await importer.importPackage(id: "fixture", data: smaller) == .imported(passages: 4))
        #expect(try await count(db, "scripture_passages") == 4)
        #expect(try await count(db, "passage_search") == 5)
        #expect(try await db.query("SELECT id FROM scripture_passages WHERE id = 'p4';").isEmpty)
    }

    @Test func invalidPackageLeavesDatabaseUntouched() async throws {
        let db = try await migrated()
        let importer = ContentImporter(database: db)
        try await importer.importPackage(id: "fixture", data: Fixtures.libraryData())
        let broken = try Fixtures.libraryData { json in
            var collections = json["collections"] as? [[String: Any]] ?? []
            collections[0]["defaultTranslationID"] = "nope"
            json["collections"] = collections
        }
        await #expect(throws: AppError.self) { try await importer.importPackage(id: "fixture", data: broken) }
        #expect(try await count(db, "scripture_passages") == 5)
        #expect(try await count(db, "passage_search") == 7)
    }

    @Test func packageCannotOverwriteAnotherPackagesCollection() async throws {
        let db = try await migrated()
        let importer = ContentImporter(database: db)
        try await importer.importPackage(id: "fixture", data: Fixtures.libraryData())
        await #expect(throws: AppError.self) {
            try await importer.importPackage(id: "other", data: Fixtures.libraryData())
        }
        #expect(try await count(db, "scripture_passages") == 5)
    }
}

@Suite struct FullTextSearchIndexTests {
    private func query(_ clauses: SearchQuery.Clause...) -> SearchQuery {
        SearchQuery(clauses: clauses, droppedStopWords: [])
    }

    @Test func matchExpressionQuotesTermsAndNeutralizesSyntax() {
        #expect(FullTextSearchIndex.matchExpression([], combinator: .all) == nil)
        #expect(FullTextSearchIndex.matchExpression([.term("  ", prefix: false)], combinator: .all) == nil)
        #expect(FullTextSearchIndex.matchExpression([.term("love", prefix: false), .term("peace", prefix: true)], combinator: .all)
                == #""love" "peace" *"#)
        #expect(FullTextSearchIndex.matchExpression([.term("love", prefix: false), .term("peace", prefix: false)], combinator: .any)
                == #""love" OR "peace""#)
        #expect(FullTextSearchIndex.matchExpression([.phrase(["skill", "in", "action"])], combinator: .all)
                == #""skill" + "in" + "action""#)
        #expect(FullTextSearchIndex.matchExpression([.term(#"a"b"#, prefix: false)], combinator: .all) == #""a""b""#)
    }

    @Test func findsTranslationTextsAndFiltersByReligion() async throws {
        let index = FullTextSearchIndex(database: try await Fixtures.database())
        let t2 = try await index.search(terms: ["t2"])
        #expect(Set(t2.map(\.passageID)) == ["p1", "p4"])
        #expect(t2.allSatisfy { $0.translationID == "t2" })
        #expect(try await index.search(terms: ["t3"]).map(\.passageID) == ["p5"])
        #expect(try await index.search(terms: ["t3"], religionIDs: ["r1"]).isEmpty)
        #expect(try await index.search(terms: ["REF", "5"], religionIDs: ["r2"]).map(\.passageID) == ["p5"])
    }

    @Test func filtersByCollectionTranslationAndLanguage() async throws {
        let index = FullTextSearchIndex(database: try await Fixtures.database())
        let ref = query(.term("ref", prefix: false))
        func ids(_ filters: SearchFilters) async throws -> Set<String> {
            Set(try await index.search(ref, filters: filters).map(\.passageID))
        }
        #expect(try await ids(SearchFilters()) == ["p1", "p2", "p3", "p4", "p5"])
        #expect(try await ids(SearchFilters(collectionIDs: ["c2"])) == ["p5"])
        #expect(try await ids(SearchFilters(translationIDs: ["t2"])) == ["p1", "p4"])
        #expect(try await ids(SearchFilters(languageCodes: ["ar"])) == ["p1", "p2", "p3", "p4"]) // c1 original language
        #expect(try await ids(SearchFilters(religionIDs: ["r1"], translationIDs: ["t3"])).isEmpty)
    }

    @Test func prefixAndAnyCombinator() async throws {
        let index = FullTextSearchIndex(database: try await Fixtures.database())
        #expect(try await index.search(query(.term("re", prefix: true))).count == 7)
        #expect(try await index.search(query(.term("re", prefix: false))).isEmpty)
        let either = query(.term("t3", prefix: false), .term("o1", prefix: false))
        #expect(try await index.search(either).isEmpty)
        #expect(Set(try await index.search(either, combinator: .any).map(\.passageID)) == ["p1", "p5"])
    }

    @Test func searchesOriginalTextAndStructureTitles() async throws {
        let index = FullTextSearchIndex(database: try await Fixtures.database())
        #expect(Set(try await index.search(terms: ["o1"]).map(\.passageID)) == ["p1"])
        #expect(Set(try await index.search(terms: ["S2a"]).map(\.passageID)) == ["p4"])
    }

    @Test func hostileInputIsTreatedAsText() async throws {
        let index = FullTextSearchIndex(database: try await Fixtures.database())
        for input in [#"""#, "*", "AND OR NOT", "t1) OR (t2", "NEAR(t1 t2)", "'; DROP TABLE religions; --"] {
            _ = try await index.search(SearchQueryParser.parse(input))
            _ = try await index.search(SearchQueryParser.parse(input), combinator: .any)
        }
        #expect(try await index.search(terms: ["t1"], limit: 0).isEmpty)
    }
}

@Suite struct DatabaseManagerTests {
    @Test func initializesLazilyOnceAndSharesTheConnection() async throws {
        let manager = DatabaseManager(location: .inMemory, bundledPackages: [])
        async let a = manager.connection()
        async let b = manager.connection()
        let (first, second) = try await (a, b)
        #expect(first === second)
        #expect(try await ScriptureSchema.migrator.currentVersion(of: first) == 5)
    }

    @Test func missingPackageFailsAndCanBeRetried() async throws {
        let missing = URL(fileURLWithPath: "/nonexistent/package.json")
        let manager = DatabaseManager(location: .inMemory, bundledPackages: [.init(id: "x", url: missing)])
        await #expect(throws: AppError.self) { try await manager.connection() }
        await #expect(throws: AppError.self) { try await manager.connection() }
    }

    @Test func fileDatabasePersistsAcrossLaunches() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: DatabaseManager.fileName)
        let package = directory.appending(path: "package.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Fixtures.libraryData().write(to: package)

        do {
            let manager = DatabaseManager(location: .file(file), bundledPackages: [.init(id: "fixture", url: package)])
            #expect(try await SQLiteScriptureRepository(database: manager).passage(id: "p1").reference == "REF 1")
        }
        #expect(FileManager.default.fileExists(atPath: file.path))

        // Second launch: content is already there; the unchanged package is not re-imported.
        let relaunched = DatabaseManager(location: .file(file), bundledPackages: [])
        let db = try await relaunched.connection()
        #expect(try await db.query("SELECT COUNT(*) AS n FROM scripture_passages;").first?.int("n") == 5)
        let outcome = try await ContentImporter(database: db).importPackage(id: "fixture", data: Fixtures.libraryData())
        #expect(outcome == .alreadyCurrent)
    }
}
