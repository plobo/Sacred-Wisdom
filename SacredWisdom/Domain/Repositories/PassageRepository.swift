import Foundation

protocol PassageRepository: Sendable {
    /// The passage of the day for the given date, or nil when no content is available.
    func dailyPassage(on date: Date) async throws(AppError) -> ScripturePassage?
}
