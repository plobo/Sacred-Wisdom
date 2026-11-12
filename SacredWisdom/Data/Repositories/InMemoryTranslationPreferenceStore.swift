import Foundation

/// Session-only translation preferences (UI tests and previews).
actor InMemoryTranslationPreferenceStore: TranslationPreferenceStore {
    private var preferred: [String: String] = [:]

    func preferredTranslationID(collectionID: String) -> String? {
        preferred[collectionID]
    }

    func setPreferredTranslationID(_ translationID: String, collectionID: String) {
        preferred[collectionID] = translationID
    }
}

/// Persisted translation preferences, one per collection. Small settings live in UserDefaults; user records
/// (bookmarks, notes, history) live in SwiftData.
struct UserDefaultsTranslationPreferenceStore: TranslationPreferenceStore {
    static let keyPrefix = "preferredTranslation."
    nonisolated(unsafe) let defaults: UserDefaults

    func preferredTranslationID(collectionID: String) async -> String? {
        defaults.string(forKey: Self.keyPrefix + collectionID)
    }

    func setPreferredTranslationID(_ translationID: String, collectionID: String) async {
        defaults.set(translationID, forKey: Self.keyPrefix + collectionID)
    }
}
