import Foundation

/// In-memory repository over a content package. The app uses `SQLiteScriptureRepository`;
/// this implementation backs unit tests and acts as the reference for repository behaviour.
struct SampleLibraryRepository: ReligionRepository, ScriptureRepository, PassageRepository, RelatedPassageRepository {
    static let resourceName = "sample_library"

    private let index: SampleLibraryIndex

    init(library: SampleLibraryDTO) throws(AppError) {
        self.index = try SampleLibraryIndex(library)
    }

    static func fromBundle(_ bundle: Bundle = .main) throws(AppError) -> SampleLibraryRepository {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw .contentNotFound("\(resourceName).json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .contentCorrupted("\(resourceName).json: \(error)")
        }
        return try SampleLibraryRepository(library: SampleLibraryDTO.decode(from: data))
    }

    // MARK: ReligionRepository

    func fetchReligions() async throws(AppError) -> [Religion] { index.religions }
    func fetchCollections() async throws(AppError) -> [ScriptureCollection] { index.collections }

    // MARK: ScriptureRepository

    func collection(id: String) async throws(AppError) -> ScriptureCollection {
        try Self.require(index.collectionsByID[id], "collection \(id)")
    }

    func translations(collectionID: String) async throws(AppError) -> [Translation] {
        index.translationsByCollection[collectionID] ?? []
    }

    func books(collectionID: String) async throws(AppError) -> [ScriptureBook] {
        index.booksByCollection[collectionID] ?? []
    }

    func book(id: String) async throws(AppError) -> ScriptureBook {
        try Self.require(index.booksByID[id], "book \(id)")
    }

    func sections(bookID: String) async throws(AppError) -> [ScriptureSection] {
        index.sectionsByBook[bookID] ?? []
    }

    func section(id: String) async throws(AppError) -> ScriptureSection {
        try Self.require(index.sectionsByID[id], "section \(id)")
    }

    func passages(sectionID: String) async throws(AppError) -> [ScripturePassage] {
        index.passagesBySection[sectionID] ?? []
    }

    func passage(id: String) async throws(AppError) -> ScripturePassage {
        try Self.require(index.passagesByID[id], "passage \(id)")
    }

    func adjacentPassageID(to passageID: String, direction: PassageDirection) async throws(AppError) -> String? {
        let passage = try Self.require(index.passagesByID[passageID], "passage \(passageID)")
        guard let order = index.readingOrder[passage.collectionID],
              let position = index.readingPosition[passageID] else { return nil }
        let target = direction == .next ? position + 1 : position - 1
        return order.indices.contains(target) ? order[target] : nil
    }

    // MARK: PassageRepository

    func dailyPassage(on date: Date) async throws(AppError) -> ScripturePassage? {
        let pools = index.religions
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { religion in
                index.collections
                    .filter { $0.religionID == religion.id }
                    .sorted { $0.id < $1.id }
                    .flatMap { index.readingOrder[$0.id] ?? [] }
            }
        guard let pick = DailyRotation.pick(day: DailyRotation.dayNumber(for: date), poolSizes: pools.map(\.count)) else {
            return nil
        }
        return index.passagesByID[pools[pick.pool][pick.offset]]
    }

    // MARK: RelatedPassageRepository

    func themes(passageID: String) async throws(AppError) -> [PassageTheme] {
        _ = try Self.require(index.passagesByID[passageID], "passage \(passageID)")
        return (index.themeIDsByPassage[passageID] ?? []).compactMap { id in index.themes.first { $0.id == id } }
    }

    func relatedPassages(to passageID: String, limit: Int) async throws(AppError) -> [RelatedPassage] {
        let source = try Self.require(index.passagesByID[passageID], "passage \(passageID)")
        let sourceThemes = try await themes(passageID: passageID)
        guard !sourceThemes.isEmpty, limit > 0 else { return [] }
        let religions = Dictionary(uniqueKeysWithValues: index.religions.map { ($0.id, $0) })

        let candidates: [RelatedPassage] = index.passagesByID.values.compactMap { candidate in
            guard candidate.religionID != source.religionID, let religion = religions[candidate.religionID] else { return nil }
            let candidateThemes = Set(index.themeIDsByPassage[candidate.id] ?? [])
            let shared = sourceThemes.filter { candidateThemes.contains($0.id) }
            return shared.isEmpty ? nil : RelatedPassage(passage: candidate, religion: religion, sharedThemes: shared)
        }
        // Same order as the SQLite implementation: most shared themes, religion order, collection, reading order.
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.sharedThemes.count != rhs.sharedThemes.count { return lhs.sharedThemes.count > rhs.sharedThemes.count }
            if lhs.religion.sortOrder != rhs.religion.sortOrder { return lhs.religion.sortOrder < rhs.religion.sortOrder }
            if lhs.passage.collectionID != rhs.passage.collectionID { return lhs.passage.collectionID < rhs.passage.collectionID }
            return (index.readingPosition[lhs.passage.id] ?? 0) < (index.readingPosition[rhs.passage.id] ?? 0)
        }
        return Array(sorted.prefix(limit))
    }

    private static func require<T>(_ value: T?, _ what: String) throws(AppError) -> T {
        guard let value else { throw .contentNotFound(what) }
        return value
    }
}
