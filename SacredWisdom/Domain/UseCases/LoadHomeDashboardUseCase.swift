import Foundation

protocol LoadHomeDashboardUseCaseProtocol: Sendable {
    func execute(on date: Date) async throws(AppError) -> HomeDashboard
}

struct LoadHomeDashboardUseCase: LoadHomeDashboardUseCaseProtocol {
    static let recentLimit = 5

    let loadSummaries: any LoadReligionSummariesUseCaseProtocol
    let passageRepository: any PassageRepository
    let recentPassages: any LoadRecentPassagesUseCaseProtocol

    func execute(on date: Date) async throws(AppError) -> HomeDashboard {
        do {
            async let summaries = loadSummaries.execute()
            async let daily = passageRepository.dailyPassage(on: date)
            async let recent = recentPassages.execute(limit: Self.recentLimit)
            return HomeDashboard(
                religions: try await summaries,
                dailyPassage: try await daily,
                recentPassages: try await recent
            )
        } catch let error as AppError {
            throw error
        } catch {
            // `async let` erases typed throws; anything else is unexpected.
            throw .unexpected(String(describing: error))
        }
    }
}

protocol LoadRecentPassagesUseCaseProtocol: Sendable {
    func execute(limit: Int) async throws(AppError) -> [ScripturePassage]
}

/// Joins reading history (user data) with scripture. History is optional: if the user store fails,
/// the list is simply empty. Passages no longer installed are skipped.
struct LoadRecentPassagesUseCase: LoadRecentPassagesUseCaseProtocol {
    let history: any ReadingHistoryRepository
    let scripture: any ScriptureRepository

    func execute(limit: Int) async throws(AppError) -> [ScripturePassage] {
        guard limit > 0, let items = try? await history.recent(limit: limit * 2) else { return [] }
        var passages: [ScripturePassage] = []
        for item in items where passages.count < limit {
            do throws(AppError) {
                passages.append(try await scripture.passage(id: item.passageID))
            } catch .contentNotFound {
                continue
            }
        }
        return passages
    }
}
