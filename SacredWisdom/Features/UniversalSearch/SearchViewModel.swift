import Foundation
import Observation

@Observable
@MainActor
final class SearchViewModel {
    enum Phase: Equatable {
        case idle
        case searching
        case results(SearchResults)
        case empty
        case failed(String)
    }

    static let recentLimit = 8

    private(set) var queryText = ""
    private(set) var phase: Phase = .idle
    private(set) var filters = SearchFilters()
    private(set) var filterOptions: SearchFilterOptions?
    private(set) var recent: [SearchHistoryItem] = []
    private(set) var completions: [String] = []
    private(set) var bookmarkedIDs: Set<String> = []
    /// A bookmarked passage whose removal would delete a note; the view asks for confirmation.
    private(set) var pendingRemovalID: String?
    var actionError: String?

    private let search: any SearchScriptureUseCaseProtocol
    private let history: any SearchHistoryRepository
    private let loadOptions: any LoadSearchFilterOptionsUseCaseProtocol
    private let suggestions = SearchSuggestionProvider()
    private let debounce: Duration
    private let now: @Sendable () -> Date
    private let userData: UserDataContext
    private var pending: Task<Void, Never>?
    private var generation = 0

    init(
        search: any SearchScriptureUseCaseProtocol,
        history: any SearchHistoryRepository,
        loadOptions: any LoadSearchFilterOptionsUseCaseProtocol,
        debounce: Duration = .milliseconds(300),
        now: @escaping @Sendable () -> Date = { Date() },
        userData: UserDataContext = .unavailable()
    ) {
        self.search = search
        self.history = history
        self.loadOptions = loadOptions
        self.debounce = debounce
        self.now = now
        self.userData = userData
    }

    var suggestedQuestions: [String] { SearchSuggestionProvider.suggestedQuestions }
    var hasQuery: Bool { !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Lifecycle

    func onAppear() async {
        if filterOptions == nil { filterOptions = try? await loadOptions.execute() }
        await reloadRecent()
        await refreshBookmarks()
    }

    // MARK: Query

    /// Live search while typing, debounced. Typing does not record history.
    func queryChanged(_ text: String) {
        guard text != queryText else { return }
        queryText = text
        completions = suggestions.completions(for: text, recent: recent)
        pending?.cancel()
        guard hasQuery else {
            generation += 1
            phase = .idle
            return
        }
        let delay = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.runSearch()
        }
    }

    /// Explicit search (keyboard Search key, suggestion, or recent query): runs now and records history.
    func submit() async {
        pending?.cancel()
        completions = []
        guard hasQuery else { return }
        try? await history.record(queryText, at: now())
        await reloadRecent()
        await runSearch()
    }

    func select(_ suggestion: String) async {
        queryText = suggestion
        await submit()
    }

    /// Awaits an in-flight debounced search. Used by tests.
    func waitForPendingSearch() async {
        await pending?.value
    }

    // MARK: Filters

    func isReligionSelected(_ id: String) -> Bool { filters.religionIDs.contains(id) }

    func toggleReligion(_ id: String) async {
        filters.religionIDs.formSymmetricDifference([id])
        await refreshAfterFilterChange()
    }

    func toggleLanguage(_ code: String) async {
        filters.languageCodes.formSymmetricDifference([code])
        await refreshAfterFilterChange()
    }

    func toggleTranslation(_ id: String) async {
        filters.translationIDs.formSymmetricDifference([id])
        await refreshAfterFilterChange()
    }

    func clearFilters() async {
        filters = SearchFilters()
        await refreshAfterFilterChange()
    }

    // MARK: History

    func removeRecent(_ id: UUID) async {
        do { try await history.remove(id: id) } catch { actionError = error.userMessage }
        await reloadRecent()
    }

    func clearRecent() async {
        do { try await history.clear() } catch { actionError = error.userMessage }
        await reloadRecent()
    }

    // MARK: Bookmarks

    /// Bumps whenever bookmarks change anywhere in the app.
    var bookmarksRevision: Int { userData.changes.bookmarks }

    func isBookmarked(_ passageID: String) -> Bool { bookmarkedIDs.contains(passageID) }

    func refreshBookmarks() async {
        bookmarkedIDs = (try? await userData.bookmarks.bookmarkedPassageIDs()) ?? []
    }

    func toggleBookmark(_ passageID: String) async {
        if bookmarkedIDs.contains(passageID) {
            if (try? await userData.bookmarks.bookmark(passageID: passageID))??.note != nil {
                pendingRemovalID = passageID
                return
            }
            await writeBookmark { [userData] () async throws(AppError) in
                try await userData.bookmarks.removeBookmark(passageID: passageID)
            }
        } else {
            await writeBookmark { [userData] () async throws(AppError) in
                try await userData.bookmarks.addBookmark(passageID: passageID, at: userData.now())
            }
        }
    }

    func confirmRemoval() async {
        guard let passageID = pendingRemovalID else { return }
        pendingRemovalID = nil
        await writeBookmark { [userData] () async throws(AppError) in
            try await userData.bookmarks.removeBookmark(passageID: passageID)
        }
    }

    func cancelRemoval() {
        pendingRemovalID = nil
    }

    private func writeBookmark(_ write: @MainActor () async throws(AppError) -> Void) async {
        do {
            try await write()
        } catch {
            actionError = error.userMessage
        }
        await refreshBookmarks()
        userData.changes.bookmarksChanged()
    }

    // MARK: Private

    private func refreshAfterFilterChange() async {
        guard hasQuery else { return }
        pending?.cancel()
        await runSearch()
    }

    private func reloadRecent() async {
        recent = (try? await history.recent(limit: Self.recentLimit)) ?? []
    }

    private func runSearch() async {
        generation += 1
        let current = generation
        let text = queryText
        phase = .searching
        do {
            let results = try await search.execute(text, filters: filters)
            guard current == generation else { return } // a newer search superseded this one
            phase = results.isEmpty ? .empty : .results(results)
        } catch {
            guard current == generation else { return }
            phase = .failed(error.userMessage)
        }
    }
}
