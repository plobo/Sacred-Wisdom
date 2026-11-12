import Foundation

/// Editorial themes and the cross-tradition links they create.
protocol RelatedPassageRepository: Sendable {
    /// The passage's themes, in package order.
    func themes(passageID: String) async throws(AppError) -> [PassageTheme]
    /// Passages from *other* religions sharing at least one theme. Ordered by number of shared themes
    /// (most first), then religion order, then reading order.
    func relatedPassages(to passageID: String, limit: Int) async throws(AppError) -> [RelatedPassage]
}
