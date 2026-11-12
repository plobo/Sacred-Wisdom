import Foundation

/// A scripture collection (e.g. Bhagavad Gita, Quran) belonging to one religion.
struct ScriptureCollection: Identifiable, Hashable, Sendable {
    enum Availability: String, Hashable, Sendable, Codable {
        /// Sample content shipped inside the app bundle.
        case bundled
        /// Full package downloaded for offline use.
        case downloaded
        /// Available for download but not yet on device.
        case notDownloaded
    }

    let id: String
    let religionID: String
    let name: String
    /// Short description of how the collection is organized.
    let structureDescription: String
    let languages: [String]
    let availability: Availability
    let originalLanguage: String
    let originalSource: ContentSource?
    let defaultTranslationID: String

    var isAvailableOffline: Bool { availability != .notDownloaded }
}
