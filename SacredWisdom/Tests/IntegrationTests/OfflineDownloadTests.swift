import Foundation
import Testing
@testable import SacredWisdom

/// Real package files in the repository (the simulator can read the host file system).
enum RepoContent {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let manifestURL = root.appending(path: "content/packages/manifest.json")
    static let tamperedManifestURL = root.appending(path: "SacredWisdom/Tests/Fixtures/tampered-packages/manifest.json")

    static func manifest() throws -> ContentManifest { try ContentManifest.decode(Data(contentsOf: manifestURL)) }
    static func entry(_ id: String) throws -> ManifestEntry { try #require(try manifest().packages.first { $0.id == id }) }
    static func data(_ entry: ManifestEntry, manifest: URL = manifestURL) throws -> Data {
        try Data(contentsOf: entry.url(relativeTo: manifest))
    }

    static var bundledPackage: DatabaseManager.BundledPackage {
        get throws {
            let url = try #require(Bundle(for: AppDependencies.self)
                .url(forResource: SampleLibraryRepository.resourceName, withExtension: "json"))
            return .init(id: SampleLibraryRepository.resourceName, url: url)
        }
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sw-packages-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

/// Copies files from disk; can hold a download "in flight" until paused, and report fake progress.
actor FakeTransport: PackageTransport {
    var offline = false
    var holdDownloads = false
    private(set) var resumedWith: [Data] = []
    private var held: [String: CheckedContinuation<Void, Never>] = [:]
    private var paused: Set<String> = []

    func setOffline(_ value: Bool) { offline = value }
    func setHold(_ value: Bool) { holdDownloads = value }

    func fetch(_ url: URL) throws(DownloadFailure) -> Data {
        if offline { throw .offline }
        guard let data = try? Data(contentsOf: url) else { throw .server(status: 404) }
        return data
    }

    func download(_ key: String, _ start: DownloadStart, progress: @escaping @Sendable (Double) -> Void) async throws(DownloadFailure) -> URL {
        if offline { throw .offline }
        let url: URL
        switch start {
        case .fresh(let u): url = u
        case .resume(let data, let u): resumedWith.append(data); url = u
        }
        progress(0.4)
        if holdDownloads {
            await withCheckedContinuation { held[key] = $0 }
            if paused.remove(key) != nil { throw .paused(resumeData: Data("resume-\(key)".utf8)) }
        }
        guard let data = try? Data(contentsOf: url) else { throw .server(status: 404) }
        let file = FileManager.default.temporaryDirectory.appending(path: "fake-\(UUID().uuidString)")
        do { try data.write(to: file) } catch { throw .other("write") }
        progress(1)
        return file
    }

    func pause(_ key: String) {
        paused.insert(key)
        held.removeValue(forKey: key)?.resume()
    }

    var isHolding: Bool { !held.isEmpty }
}

@Suite struct ManifestTests {
    @Test func repositoryManifestDescribesEveryPackageCorrectly() throws {
        let manifest = try RepoContent.manifest()
        #expect(manifest.packages.map(\.id).sorted() == ["bhagavad-gita-ch2", "bible-matthew-5", "dhammapada-ch1"])
        for entry in manifest.packages {
            let data = try RepoContent.data(entry)
            #expect(PackageInstaller.verify(data, against: entry) == nil, "\(entry.id)")
            #expect(!entry.license.isEmpty && !entry.sources.isEmpty && !entry.languages.isEmpty)
        }
        #expect(try RepoContent.entry("bhagavad-gita-ch2").passageCount == 72)
        #expect(try RepoContent.entry("bible-matthew-5").passageCount == 48)
        #expect(try RepoContent.entry("dhammapada-ch1").passageCount == 20)
    }

    private func entryJSON(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var entry: [String: Any] = [
            "id": "pkg", "collectionID": "c1", "title": "T", "version": 1, "languages": ["en"], "fileSize": 10,
            "sources": ["S"], "license": "PD", "sha256": String(repeating: "a", count: 64), "schemaVersion": 3,
            "passageCount": 1, "path": "pkg.json",
        ]
        change(&entry)
        return try JSONSerialization.data(withJSONObject: ["manifestVersion": 1, "packages": [entry]])
    }

    /// Each case sets one field to an invalid value, given as a JSON fragment.
    @Test(arguments: [
        ("id", #""../etc""#), ("collectionID", #""Has Space""#), ("sha256", #""abc""#), ("fileSize", "0"),
        ("fileSize", "62914560"), ("schemaVersion", "9"), ("path", #""../../x.json""#), ("path", #""https://evil/x.json""#),
        ("path", #""/abs.json""#), ("version", "0"),
    ])
    func invalidEntriesRejectTheManifest(field: String, json: String) throws {
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        let data = try entryJSON { $0[field] = value }
        #expect(throws: AppError.self) { try ContentManifest.decode(data) }
    }

    @Test func validEntryDecodesAndResolvesRelativeToManifest() throws {
        let manifest = try ContentManifest.decode(try entryJSON { _ in })
        let url = manifest.packages[0].url(relativeTo: URL(string: "https://content.example/v1/manifest.json")!)
        #expect(url.absoluteString == "https://content.example/v1/pkg.json")
    }

    @Test func duplicateIDsAndUnknownManifestVersionAreRejected() throws {
        let one = try JSONSerialization.jsonObject(with: try entryJSON { _ in }) as? [String: Any]
        let entries = try #require(one?["packages"] as? [[String: Any]])
        let duplicate = try JSONSerialization.data(withJSONObject: ["manifestVersion": 1, "packages": entries + entries])
        #expect(throws: AppError.self) { try ContentManifest.decode(duplicate) }
        let future = try JSONSerialization.data(withJSONObject: ["manifestVersion": 2, "packages": entries])
        #expect(throws: AppError.self) { try ContentManifest.decode(future) }
    }

    @Test func productionManifestURLMustBeHTTPS() {
        #expect(AppConfiguration.contentManifestURL(arguments: [], isUITesting: false, infoValue: "") == nil)
        #expect(AppConfiguration.contentManifestURL(arguments: [], isUITesting: false, infoValue: "http://x/m.json") == nil)
        #expect(AppConfiguration.contentManifestURL(arguments: [], isUITesting: false, infoValue: "https://x/m.json")?.host() == "x")
        #expect(AppConfiguration.contentManifestURL(arguments: ["-ui-testing-manifest-url", "file:///tmp/m.json"],
                                                    isUITesting: true, infoValue: "https://x/m.json")?.isFileURL == true)
        #expect(AppConfiguration.contentManifestURL(arguments: [], isUITesting: true, infoValue: "https://x/m.json") == nil)
    }
}

@Suite struct PackageVerificationTests {
    @Test func tamperedFileWithMatchingSizeFailsChecksum() throws {
        let manifest = try ContentManifest.decode(Data(contentsOf: RepoContent.tamperedManifestURL))
        let entry = try #require(manifest.packages.first)
        let data = try RepoContent.data(entry, manifest: RepoContent.tamperedManifestURL)
        #expect(data.count == entry.fileSize)
        #expect(PackageInstaller.verify(data, against: entry) == .checksumMismatch)
    }

    @Test func truncatedFileFailsSize() throws {
        let entry = try RepoContent.entry("bible-matthew-5")
        let data = try RepoContent.data(entry).prefix(100)
        #expect(PackageInstaller.verify(Data(data), against: entry) == .sizeMismatch(expected: entry.fileSize, actual: 100))
    }

    private func entry(for data: Data, collectionID: String, schema: Int = 3) -> ManifestEntry {
        ManifestEntry(id: "x", collectionID: collectionID, title: "x", version: 1, languages: ["en"], fileSize: data.count,
                      sources: ["s"], license: "PD", sha256: PackageFileStore.sha256(data), schemaVersion: schema,
                      passageCount: 1, path: "x.json")
    }

    @Test func checksumMatchingButStructurallyWrongPackagesAreRejected() throws {
        let garbage = Data("{\"not\": \"a package\"}".utf8)
        guard case .invalidContent? = PackageInstaller.verify(garbage, against: entry(for: garbage, collectionID: "c1")) else {
            Issue.record("garbage accepted"); return
        }
        let fixture = try Fixtures.libraryData() // two collections, schema 3
        #expect(PackageInstaller.verify(fixture, against: entry(for: fixture, collectionID: "c1")) == .wrongCollection)
        let real = try RepoContent.data(try RepoContent.entry("dhammapada-ch1"))
        #expect(PackageInstaller.verify(real, against: entry(for: real, collectionID: "bible")) == .wrongCollection)
        #expect(PackageInstaller.verify(real, against: entry(for: real, collectionID: "tripitaka", schema: 2)) == .schemaMismatch)
    }
}

@Suite struct PackageOwnershipTests {
    private func database() async throws -> (DatabaseManager, SQLiteScriptureRepository) {
        let manager = DatabaseManager(location: .inMemory, bundledPackages: [try RepoContent.bundledPackage])
        return (manager, SQLiteScriptureRepository(database: manager))
    }

    private func gitaIDs(_ repo: SQLiteScriptureRepository) async throws -> [String] {
        try await repo.passages(sectionID: "gita.ch2").map(\.id)
    }

    @Test func downloadSupersedesSampleAndRemovalRestoresIt() async throws {
        let (manager, repo) = try await database()
        #expect(try await gitaIDs(repo) == (47...50).map { "gita.2.\($0)" })
        #expect(try await repo.collection(id: "bhagavad-gita").availability == .bundled)

        let entry = try RepoContent.entry("bhagavad-gita-ch2")
        #expect(try await manager.installDownloadedPackage(id: entry.id, data: RepoContent.data(entry)) == .imported(passages: 72))
        #expect(try await gitaIDs(repo).count == 72)
        #expect(try await repo.collection(id: "bhagavad-gita").availability == .downloaded)
        // Unchanged IDs: the sample's passage, its themes and its related links still resolve.
        #expect(try await repo.themes(passageID: "gita.2.47").map(\.id) == ["action-consequence"])
        let search = FullTextSearchIndex(database: manager)
        #expect(try await search.search(terms: ["Sanjaya"]).contains { $0.passageID == "gita.2.1" })

        try await manager.removeDownloadedPackage(id: entry.id)
        #expect(try await gitaIDs(repo) == (47...50).map { "gita.2.\($0)" })
        #expect(try await repo.collection(id: "bhagavad-gita").availability == .bundled)
        #expect(try await search.search(terms: ["Sanjaya"]).isEmpty)
        // Other traditions were untouched throughout.
        #expect(try await repo.passages(sectionID: "quran.surah1").count == 7)
    }

    @Test func bundledReimportNeverOverwritesADownload() async throws {
        let (manager, repo) = try await database()
        let entry = try RepoContent.entry("dhammapada-ch1")
        try await manager.installDownloadedPackage(id: entry.id, data: RepoContent.data(entry))
        let db = try await manager.connection()
        let bundled = try Data(contentsOf: try RepoContent.bundledPackage.url)
        try await ContentImporter(database: db).importPackage(id: SampleLibraryRepository.resourceName, data: bundled, force: true)
        #expect(try await repo.passages(sectionID: "dhammapada.ch1").count == 20)
        #expect(try await repo.passages(sectionID: "bible.matthew.5").count == 8)
    }

    @Test func twoDownloadsCannotClaimTheSameCollection() async throws {
        let (manager, _) = try await database()
        let entry = try RepoContent.entry("bible-matthew-5")
        let data = try RepoContent.data(entry)
        try await manager.installDownloadedPackage(id: entry.id, data: data)
        await #expect(throws: AppError.self) { try await manager.installDownloadedPackage(id: "impostor", data: data) }
    }

    /// Acceptance: downloaded collections work without internet. A relaunch rebuilds the database from the
    /// bundled sample and the package files on disk; no network is involved.
    @Test func downloadedCollectionsSurviveRelaunchWithoutNetwork() async throws {
        let directory = RepoContent.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PackageFileStore(directory: directory)
        let entry = try RepoContent.entry("bible-matthew-5")
        try store.save(try RepoContent.data(entry), entry: entry)
        // A corrupted file next to it must not stop the library from opening.
        try Data("{broken".utf8).write(to: directory.appending(path: "broken.json"))

        let relaunched = DatabaseManager(location: .inMemory, bundledPackages: [try RepoContent.bundledPackage],
                                         downloadedPackagesDirectory: directory)
        let repo = SQLiteScriptureRepository(database: relaunched)
        let verses = try await repo.passages(sectionID: "bible.matthew.5")
        #expect(verses.count == 48)
        #expect(verses.first?.reference == "Matthew 5:1")
        let love = try await repo.passage(id: "bible.matthew.5.44")
        #expect(love.texts.first?.text.hasPrefix("But I say unto you, Love your enemies") == true)
        let page = try await LoadReaderPageUseCase(repository: repo).execute(.passage("bible.matthew.5.10"))
        #expect(page.nextPassageID == "bible.matthew.5.11")
    }
}

@MainActor
@Suite struct DownloadManagerTests {
    private struct Harness {
        let manager: DownloadManager
        let transport: FakeTransport
        let database: DatabaseManager
        let repo: SQLiteScriptureRepository
        let store: PackageFileStore
        let changes: UserDataChanges
    }

    private func harness(manifest: URL? = RepoContent.manifestURL, directory: URL = RepoContent.temporaryDirectory()) throws -> Harness {
        let database = DatabaseManager(location: .inMemory, bundledPackages: [try RepoContent.bundledPackage],
                                       downloadedPackagesDirectory: directory)
        let store = PackageFileStore(directory: directory)
        let transport = FakeTransport()
        let changes = UserDataChanges()
        let manager = DownloadManager(manifestURL: manifest, transport: transport,
                                      installer: PackageInstaller(store: store, database: database), changes: changes)
        return Harness(manager: manager, transport: transport, database: database,
                       repo: SQLiteScriptureRepository(database: database), store: store, changes: changes)
    }

    @Test func downloadVerifiesInstallsAndReportsStorage() async throws {
        let h = try harness()
        defer { try? FileManager.default.removeItem(at: h.store.directory) }
        await h.manager.refresh()
        #expect(h.manager.catalog == .loaded)
        #expect(h.manager.items.map(\.status) == [.notInstalled, .notInstalled, .notInstalled])

        await h.manager.download("bhagavad-gita-ch2")
        #expect(h.manager.status(of: "bhagavad-gita-ch2") == .installed(version: 1))
        #expect(h.changes.content == 1)
        #expect(h.manager.storage.packageBytes > 46_000)
        #expect(try await h.repo.passages(sectionID: "gita.ch2").count == 72)
    }

    @Test func invalidPackageIsRejectedAndNothingIsInstalled() async throws {
        let h = try harness(manifest: RepoContent.tamperedManifestURL)
        defer { try? FileManager.default.removeItem(at: h.store.directory) }
        await h.manager.refresh()
        await h.manager.download("dhammapada-ch1")
        #expect(h.manager.status(of: "dhammapada-ch1") == .failed(PackageInstaller.Rejection.checksumMismatch.userMessage))
        #expect(h.store.installed().isEmpty)
        #expect(h.manager.storage.packageBytes == 0)
        #expect(try await h.repo.passages(sectionID: "dhammapada.ch1").count == 6) // sample unchanged
        #expect(h.changes.content == 0)
    }

    @Test func pauseKeepsProgressAndResumeContinuesFromResumeData() async throws {
        let h = try harness()
        defer { try? FileManager.default.removeItem(at: h.store.directory) }
        await h.manager.refresh()
        await h.transport.setHold(true)
        let downloading = Task { await h.manager.download("bible-matthew-5") }
        while !(await h.transport.isHolding) { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50)) // let the progress callback land on the main actor
        #expect(h.manager.status(of: "bible-matthew-5") == .downloading(0.4))

        await h.manager.pause("bible-matthew-5")
        await downloading.value
        #expect(h.manager.status(of: "bible-matthew-5") == .paused(0.4))

        await h.transport.setHold(false)
        await h.manager.download("bible-matthew-5")
        #expect(await h.transport.resumedWith == [Data("resume-bible-matthew-5".utf8)])
        #expect(h.manager.status(of: "bible-matthew-5") == .installed(version: 1))
    }

    @Test func offlineStillListsInstalledPackagesAsUsable() async throws {
        let directory = RepoContent.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try harness(directory: directory)
        await first.manager.refresh()
        await first.manager.download("dhammapada-ch1")

        let offline = try harness(directory: directory)
        await offline.transport.setOffline(true)
        await offline.manager.refresh()
        #expect(offline.manager.catalog == .unavailable("You’re offline. Installed content is still available."))
        #expect(offline.manager.items.map(\.id) == ["dhammapada-ch1"])
        #expect(offline.manager.status(of: "dhammapada-ch1") == .installed(version: 1))
        #expect(try await offline.repo.passages(sectionID: "dhammapada.ch1").count == 20)
    }

    @Test func notConfiguredStillShowsInstalledAndAllowsRemoval() async throws {
        let directory = RepoContent.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try harness(directory: directory)
        await first.manager.refresh()
        await first.manager.download("bible-matthew-5")

        let h = try harness(manifest: nil, directory: directory)
        await h.manager.refresh()
        #expect(h.manager.catalog == .notConfigured)
        #expect(h.manager.status(of: "bible-matthew-5") == .installed(version: 1))

        await h.manager.remove("bible-matthew-5")
        #expect(h.manager.items.isEmpty)
        #expect(h.store.installed().isEmpty)
        #expect(h.manager.storage.packageBytes == 0)
        #expect(try await h.repo.passages(sectionID: "bible.matthew.5").count == 8)
        #expect(h.changes.content == 1)
    }

    @Test func newerManifestVersionOffersUpdate() async throws {
        let directory = RepoContent.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PackageFileStore(directory: directory)
        let current = try RepoContent.entry("bhagavad-gita-ch2")
        let older = ManifestEntry(id: current.id, collectionID: current.collectionID, title: current.title, version: 0 + 1,
                                  languages: current.languages, fileSize: current.fileSize, sources: current.sources,
                                  license: current.license, sha256: current.sha256, schemaVersion: current.schemaVersion,
                                  passageCount: current.passageCount, path: current.path)
        try store.save(try RepoContent.data(current), entry: older)

        let manifestDir = RepoContent.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: manifestDir) }
        try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: RepoContent.manifestURL)) as? [String: Any])
        var packages = try #require(json["packages"] as? [[String: Any]])
        for index in packages.indices where packages[index]["id"] as? String == current.id { packages[index]["version"] = 2 }
        json["packages"] = packages
        let manifestURL = manifestDir.appending(path: "manifest.json")
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)

        let h = try harness(manifest: manifestURL, directory: directory)
        await h.manager.refresh()
        #expect(h.manager.status(of: current.id) == .updateAvailable(installed: 1))
    }
}

/// The real URLSession transport, against file URLs (no network in tests).
@Suite struct URLSessionTransportTests {
    @Test func fetchesAndDownloadsFileURLsWithProgress() async throws {
        let transport = URLSessionPackageTransport()
        let manifest = try await transport.fetch(RepoContent.manifestURL)
        #expect(try ContentManifest.decode(manifest).packages.count == 3)

        let entry = try RepoContent.entry("dhammapada-ch1")
        let seen = ProgressBox()
        let file = try await transport.download(entry.id, .fresh(entry.url(relativeTo: RepoContent.manifestURL))) { seen.record($0) }
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(PackageInstaller.verify(try Data(contentsOf: file), against: entry) == nil)
        #expect(seen.last == 1)
    }

    @Test func missingFileFails() async {
        let transport = URLSessionPackageTransport()
        await #expect(throws: DownloadFailure.self) {
            try await transport.download("x", .fresh(RepoContent.root.appending(path: "content/packages/nope.json"))) { _ in }
        }
    }

    final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        func record(_ value: Double) { lock.withLock { values.append(value) } }
        var last: Double? { lock.withLock { values.last } }
    }
}
