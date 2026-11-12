import Foundation
import Observation

/// Screen 8: a conversation of questions, each answered with verified passages and, optionally, a
/// separately labeled AI explanation.
@Observable
@MainActor
final class AskQuestionViewModel {
    struct Exchange: Identifiable, Equatable {
        enum Status: Equatable {
            case answering
            case answered(QuestionAnswer)
            case failed(String)
        }

        let id: UUID
        let question: String
        var status: Status
    }

    static let maximumQuestionLength = 300

    var draft = ""
    private(set) var exchanges: [Exchange] = []

    private let answerQuestion: any AnswerQuestionUseCaseProtocol

    init(answerQuestion: any AnswerQuestionUseCaseProtocol) {
        self.answerQuestion = answerQuestion
    }

    var suggestedQuestions: [String] { SearchSuggestionProvider.suggestedQuestions }
    var isAnswering: Bool { exchanges.contains { $0.status == .answering } }
    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnswering }

    func send() async {
        guard canSend else { return }
        let question = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumQuestionLength))
        draft = ""
        await ask(question)
    }

    func ask(_ question: String) async {
        guard !isAnswering else { return }
        let exchange = Exchange(id: UUID(), question: question, status: .answering)
        exchanges.append(exchange)
        let status: Exchange.Status
        do {
            status = .answered(try await answerQuestion.execute(question))
        } catch {
            status = .failed(error.userMessage)
        }
        if let index = exchanges.firstIndex(where: { $0.id == exchange.id }) {
            exchanges[index].status = status
        }
    }

    func retry(_ exchange: Exchange) async {
        exchanges.removeAll { $0.id == exchange.id }
        await ask(exchange.question)
    }

    func clear() {
        guard !isAnswering else { return }
        exchanges = []
    }
}
