import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    private(set) var statusMessage: String?
    private(set) var isAIEnabled = true
    private(set) var aiAvailability: AIAvailability?
    private(set) var aiProviderName = ""

    /// Collections offering more than one translation, with the current choice.
    private(set) var translationChoices: [TranslationChoice] = []

    struct TranslationChoice: Identifiable, Equatable {
        let collection: ScriptureCollection
        let translations: [Translation]
        var selectedID: String
        var id: String { collection.id }
    }

    let display: AppPreferences
    private let userData: UserDataContext
    private let aiPreferences: any AIPreferenceStore
    private let ai: any ScriptureAIService
    private let scripture: (any ScriptureRepository & ReligionRepository)?
    private let translationPreferences: any TranslationPreferenceStore

    init(
        userData: UserDataContext,
        aiPreferences: any AIPreferenceStore = InMemoryAIPreferenceStore(),
        ai: any ScriptureAIService = UnavailableScriptureAIService(reason: ""),
        display: AppPreferences = AppPreferences(defaults: UserDefaults(suiteName: "settings-preview") ?? .standard),
        scripture: (any ScriptureRepository & ReligionRepository)? = nil,
        translationPreferences: any TranslationPreferenceStore = InMemoryTranslationPreferenceStore()
    ) {
        self.userData = userData
        self.aiPreferences = aiPreferences
        self.ai = ai
        self.display = display
        self.scripture = scripture
        self.translationPreferences = translationPreferences
    }

    func load() async {
        isAIEnabled = await aiPreferences.isEnabled()
        aiAvailability = await ai.availability()
        aiProviderName = ai.providerName
        await loadTranslationChoices()
    }

    private func loadTranslationChoices() async {
        guard let scripture, let collections = try? await scripture.fetchCollections() else { return }
        var choices: [TranslationChoice] = []
        for collection in collections {
            guard let translations = try? await scripture.translations(collectionID: collection.id), translations.count > 1 else { continue }
            let stored = await translationPreferences.preferredTranslationID(collectionID: collection.id)
            let selected = stored.flatMap { id in translations.first { $0.id == id }?.id } ?? collection.defaultTranslationID
            choices.append(TranslationChoice(collection: collection, translations: translations, selectedID: selected))
        }
        translationChoices = choices
    }

    func selectTranslation(_ translationID: String, for collectionID: String) async {
        guard let index = translationChoices.firstIndex(where: { $0.id == collectionID }),
              translationChoices[index].translations.contains(where: { $0.id == translationID }) else { return }
        translationChoices[index].selectedID = translationID
        await translationPreferences.setPreferredTranslationID(translationID, collectionID: collectionID)
    }

    // MARK: Reader text size

    var textScalePercent: Int { Int((display.readerTextScale * 100).rounded()) }
    var canIncreaseTextScale: Bool { display.readerTextScale < ReaderViewModel.fontScaleRange.upperBound - 0.001 }
    var canDecreaseTextScale: Bool { display.readerTextScale > ReaderViewModel.fontScaleRange.lowerBound + 0.001 }

    func changeTextScale(by steps: Int) {
        let next = display.readerTextScale + Double(steps) * ReaderViewModel.fontScaleStep
        display.readerTextScale = (min(max(next, ReaderViewModel.fontScaleRange.lowerBound),
                                       ReaderViewModel.fontScaleRange.upperBound) * 10).rounded() / 10
    }

    func setAIEnabled(_ enabled: Bool) async {
        isAIEnabled = enabled
        await aiPreferences.setEnabled(enabled)
    }

    var aiStatusText: String {
        switch aiAvailability {
        case .available: String(localized: "Uses \(aiProviderName). Explanations are labeled and cite their passages.")
        case .unavailable(let reason): reason
        case nil: ""
        }
    }

    func clearReadingHistory() async {
        do {
            try await userData.history.clear()
            userData.changes.readingHistoryChanged()
            statusMessage = String(localized: "Reading history cleared.")
        } catch {
            statusMessage = error.userMessage
        }
    }
}
