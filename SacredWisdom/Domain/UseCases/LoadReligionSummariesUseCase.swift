import Foundation

protocol LoadReligionSummariesUseCaseProtocol: Sendable {
    func execute() async throws(AppError) -> [ReligionSummary]
}

/// Joins religions with their primary collection, in display order.
struct LoadReligionSummariesUseCase: LoadReligionSummariesUseCaseProtocol {
    let religionRepository: any ReligionRepository

    func execute() async throws(AppError) -> [ReligionSummary] {
        let religions = try await religionRepository.fetchReligions()
        let collections = try await religionRepository.fetchCollections()
        let collectionsByReligion = Dictionary(
            collections.map { ($0.religionID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return religions
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ReligionSummary(religion: $0, collection: collectionsByReligion[$0.id]) }
    }
}
