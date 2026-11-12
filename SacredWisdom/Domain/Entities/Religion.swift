import Foundation

/// A religious tradition represented in the library.
/// IDs are stable string identifiers shared with the content manifest.
struct Religion: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let summary: String
    /// Unicode glyph used as the tradition's emblem (rendered as text, not an image).
    let emblem: String
    /// Design-system tint key; resolved by `SWColors.tint(for:)`.
    let tintKey: String
    let sortOrder: Int
}
