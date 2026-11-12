import Foundation

/// Everything the Verse Details screen shows for one passage.
struct PassageDetail: Equatable, Sendable {
    let religion: Religion
    let collection: ScriptureCollection
    let book: ScriptureBook
    let section: ScriptureSection
    let passage: ScripturePassage
    /// 1-based position of the passage within its section, and the section's passage count.
    let positionInSection: Int
    let sectionPassageCount: Int
    let themes: [PassageTheme]
    let related: [RelatedPassage]
}
