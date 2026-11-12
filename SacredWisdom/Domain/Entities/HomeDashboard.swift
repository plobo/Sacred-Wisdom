import Foundation

/// A religion paired with its primary collection, for display on cards.
struct ReligionSummary: Identifiable, Hashable, Sendable {
    let religion: Religion
    let collection: ScriptureCollection?

    var id: String { religion.id }
}

/// Everything the Home screen needs, assembled by `LoadHomeDashboardUseCase`.
struct HomeDashboard: Sendable, Equatable {
    let religions: [ReligionSummary]
    let dailyPassage: ScripturePassage?
    let recentPassages: [ScripturePassage]

    var offlineCollectionCount: Int {
        religions.filter { $0.collection?.isAvailableOffline == true }.count
    }
}
