import AppIntents
import Foundation

/// A scripture passage as Siri and Shortcuts see it. Identified by the stable passage ID.
struct PassageEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Scripture Passage")
    static let defaultQuery = PassageEntityQuery()

    let id: String
    let reference: String
    let collectionName: String
    let text: String
    let translationName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(reference)",
            subtitle: "\(collectionName) · \(translationName)"
        )
    }

    init(passage: ScripturePassage, collectionName: String) {
        id = passage.id
        reference = passage.reference
        self.collectionName = collectionName
        text = passage.texts.first?.text ?? ""
        translationName = passage.texts.first?.translation.name ?? ""
    }

    @MainActor
    static func entities(for passages: [ScripturePassage]) async -> [PassageEntity] {
        let collections = (try? await AppSession.shared.dependencies.library.fetchCollections()) ?? []
        let names = Dictionary(collections.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return passages.map { PassageEntity(passage: $0, collectionName: names[$0.collectionID] ?? "") }
    }
}

/// Resolves passages by ID, by spoken/typed text (via local search), and suggests today's passage.
struct PassageEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PassageEntity] {
        let library = AppSession.shared.dependencies.library
        var passages: [ScripturePassage] = []
        for id in identifiers {
            if let passage = try? await library.passage(id: id) { passages.append(passage) }
        }
        return await PassageEntity.entities(for: passages)
    }

    @MainActor
    func entities(matching string: String) async throws -> [PassageEntity] {
        let response = try await AppSession.shared.intentService.searchReferences(string)
        return await PassageEntity.entities(for: Array(response.passages.prefix(20)))
    }

    @MainActor
    func suggestedEntities() async throws -> [PassageEntity] {
        let response = try await AppSession.shared.intentService.dailyPassage(on: Date())
        return await PassageEntity.entities(for: response.passages)
    }
}

/// Topics Siri can recognise inside an App Shortcut phrase (free text cannot appear in a phrase).
enum ScriptureTopic: String, AppEnum {
    case peace, mercy, comfort, love, hatred, guidance, action, truth, fear, righteousness, forgiveness

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Topic")
    static let caseDisplayRepresentations: [ScriptureTopic: DisplayRepresentation] = [
        .peace: "Peace", .mercy: "Mercy", .comfort: "Comfort", .love: "Love", .hatred: "Hatred",
        .guidance: "Guidance", .action: "Action", .truth: "Truth", .fear: "Fear",
        .righteousness: "Righteousness", .forgiveness: "Forgiveness",
    ]

    var query: ScriptureTopicQuery { ScriptureTopicQuery(rawValue: rawValue) ?? .peace }
}
