import Foundation

protocol ReligionRepository: Sendable {
    func fetchReligions() async throws(AppError) -> [Religion]
    func fetchCollections() async throws(AppError) -> [ScriptureCollection]
}
