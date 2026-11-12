import Foundation
import Observation

@Observable
@MainActor
final class LibraryViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded([ReligionSummary])
        case failed(String)
    }

    private(set) var state: State = .idle
    private let loadSummaries: any LoadReligionSummariesUseCaseProtocol
    private let changes: UserDataChanges?

    init(loadSummaries: any LoadReligionSummariesUseCaseProtocol, changes: UserDataChanges? = nil) {
        self.loadSummaries = loadSummaries
        self.changes = changes
    }

    /// Bumps when a package is downloaded or removed.
    var contentRevision: Int { changes?.content ?? 0 }

    /// Reloads without the loading state, keeping current content on failure.
    func refresh() async {
        guard case .loaded = state, let summaries = try? await loadSummaries.execute() else { return }
        state = .loaded(summaries)
    }

    func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            state = .loaded(try await loadSummaries.execute())
        } catch {
            state = .failed(error.userMessage)
        }
    }
}
