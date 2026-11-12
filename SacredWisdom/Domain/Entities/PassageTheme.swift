import Foundation

/// An editorial label for something a passage explicitly speaks of (e.g. "Mercy").
/// Themes are curated metadata, not scripture, and are always presented as editorial.
struct PassageTheme: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// A passage from another tradition that shares at least one theme with the passage being viewed.
struct RelatedPassage: Identifiable, Hashable, Sendable {
    let passage: ScripturePassage
    let religion: Religion
    let sharedThemes: [PassageTheme]

    var id: String { passage.id }
}
