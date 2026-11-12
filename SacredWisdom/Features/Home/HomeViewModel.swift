import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(HomeDashboard)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let loadDashboard: any LoadHomeDashboardUseCaseProtocol
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let changes: UserDataChanges?

    init(
        loadDashboard: any LoadHomeDashboardUseCaseProtocol,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        changes: UserDataChanges? = nil
    ) {
        self.loadDashboard = loadDashboard
        self.now = now
        self.calendar = calendar
        self.changes = changes
    }

    func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            state = .loaded(try await loadDashboard.execute(on: now()))
        } catch {
            state = .failed(error.userMessage)
        }
    }

    /// Reloads without showing the loading state (e.g. after reading something new). Keeps the current
    /// content if the reload fails.
    func refresh() async {
        guard case .loaded = state else { return }
        if let dashboard = try? await loadDashboard.execute(on: now()) {
            state = .loaded(dashboard)
        }
    }

    /// Bumps whenever reading history changes.
    var readingHistoryRevision: Int { changes?.readingHistory ?? 0 }
    /// Bumps when a package is downloaded or removed.
    var contentRevision: Int { changes?.content ?? 0 }

    var greeting: String {
        switch calendar.component(.hour, from: now()) {
        case 5..<12: String(localized: "Good morning")
        case 12..<17: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
    }

    /// e.g. "4 of 6 offline"
    var offlineSummary: String? {
        guard case .loaded(let dashboard) = state else { return nil }
        return String(localized: "\(dashboard.offlineCollectionCount) of \(dashboard.religions.count) offline")
    }

    func religionName(for id: String) -> String? {
        guard case .loaded(let dashboard) = state else { return nil }
        return dashboard.religions.first { $0.religion.id == id }?.religion.name
    }
}
