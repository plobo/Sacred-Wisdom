import Foundation

/// Every source behind the installed content, grouped by collection, for Settings → Sources & Licenses.
struct CollectionAttribution: Identifiable, Equatable, Sendable {
    let religion: Religion
    let collection: ScriptureCollection
    /// Original-text source first (if any), then each translation's source, without duplicates.
    let sources: [ContentSource]

    var id: String { collection.id }
}

struct LoadAttributionsUseCase: Sendable {
    let scripture: any ScriptureRepository & ReligionRepository

    func execute() async throws(AppError) -> [CollectionAttribution] {
        let religions = Dictionary(uniqueKeysWithValues: try await scripture.fetchReligions().map { ($0.id, $0) })
        var result: [CollectionAttribution] = []
        for collection in try await scripture.fetchCollections() {
            guard let religion = religions[collection.religionID] else { continue }
            var sources = [collection.originalSource].compactMap { $0 }
            for translation in try await scripture.translations(collectionID: collection.id)
            where !sources.contains(where: { $0.id == translation.source.id }) {
                sources.append(translation.source)
            }
            result.append(CollectionAttribution(religion: religion, collection: collection, sources: sources))
        }
        return result.sorted { $0.religion.sortOrder < $1.religion.sortOrder }
    }
}
