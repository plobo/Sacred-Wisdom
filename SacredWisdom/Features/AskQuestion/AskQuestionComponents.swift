import SwiftUI

struct AskIntro: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            Text("Ask what the traditions say")
                .font(SWTypography.title)
                .foregroundStyle(SWColors.textPrimary)
            Text("Answers are passages from the library, quoted exactly. Where available, a clearly labeled AI explanation summarizes them, citing each passage it relies on.")
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.textSecondary)
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, question in
                Button { onSelect(question) } label: {
                    SWCard {
                        HStack {
                            Image(systemName: "sparkle.magnifyingglass").foregroundStyle(SWColors.secondary)
                                .accessibilityHidden(true)
                            Text(question).foregroundStyle(SWColors.textPrimary)
                            Spacer()
                        }
                        .font(SWTypography.body)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.suggestion.\(index)")
            }
        }
    }
}

struct ExchangeView: View {
    let exchange: AskQuestionViewModel.Exchange
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            HStack {
                Spacer(minLength: SWSpacing.xxl)
                Text(exchange.question)
                    .font(SWTypography.body)
                    .foregroundStyle(SWColors.onPrimary)
                    .padding(SWSpacing.m)
                    .background(SWColors.primary, in: RoundedRectangle(cornerRadius: SWRadius.card, style: .continuous))
                    .accessibilityLabel(Text("You asked: \(exchange.question)"))
            }
            switch exchange.status {
            case .answering:
                LoadingStateView(message: "Finding passages…")
            case .failed(let message):
                ErrorStateView(message: message, retry: onRetry)
            case .answered(let answer):
                AnswerView(answer: answer)
            }
        }
    }
}

private struct AnswerView: View {
    let answer: QuestionAnswer

    private var citedNumbers: [String: Int] {
        guard case .explanation(let explanation) = answer.explanation else { return [:] }
        return Dictionary(explanation.citations.map { ($0.passageID, $0.number) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.l) {
            if answer.results.isEmpty {
                EmptyStateView(systemImage: "text.magnifyingglass", title: "No passages found",
                               message: "The installed library has no passages matching this question. Try other words.")
            } else {
                ExplanationSection(outcome: answer.explanation)
                Text(SearchResultsSummary.text(passages: answer.results.totalCount, traditions: answer.results.groups.count))
                    .font(SWTypography.caption.weight(.semibold))
                    .foregroundStyle(SWColors.textSecondary)
                ForEach(answer.results.groups) { group in
                    TraditionPassages(group: group, citedNumbers: citedNumbers)
                }
            }
        }
    }
}

/// The AI explanation, visibly separate from scripture and always labeled.
private struct ExplanationSection: View {
    let outcome: AIExplanationOutcome

    var body: some View {
        switch outcome {
        case .explanation(let explanation):
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                Label("AI-generated explanation · \(explanation.providerName)", systemImage: "sparkles")
                    .font(SWTypography.caption.weight(.semibold))
                    .foregroundStyle(SWColors.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ask.aiLabel")
                Text(explanation.text)
                    .font(SWTypography.body)
                    .foregroundStyle(SWColors.textPrimary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("ask.aiExplanation")
                FlowCitations(citations: explanation.citations)
                if explanation.removedSentenceCount > 0 {
                    Text(explanation.removedSentenceCount == 1
                         ? String(localized: "1 sentence was removed because it couldn’t be verified against the passages.")
                         : String(localized: "\(explanation.removedSentenceCount) sentences were removed because they couldn’t be verified against the passages."))
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                        .accessibilityIdentifier("ask.aiRemoved")
                }
                Text("AI can be wrong. Read the passages themselves; interpretations differ within and across traditions.")
                    .font(SWTypography.caption)
                    .foregroundStyle(SWColors.textSecondary)
            }
            .padding(SWSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SWColors.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: SWRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SWRadius.card, style: .continuous)
                .strokeBorder(SWColors.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ask.ai")
        case .disabled:
            note("AI explanations are off. Turn them on in Settings.", icon: "sparkles")
        case .unavailable(let reason):
            note(String(localized: "Showing passages only. \(reason)"), icon: "sparkles")
        case .failed(let message):
            note(message, icon: "exclamationmark.triangle")
        case .notAttempted:
            EmptyView()
        }
    }

    private func note(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(SWTypography.caption)
            .foregroundStyle(SWColors.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ask.aiNote")
    }
}

private struct FlowCitations: View {
    let citations: [AICitation]

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.xs) {
            Text("Sources").font(SWTypography.caption.weight(.semibold)).foregroundStyle(SWColors.textSecondary)
            ForEach(citations) { citation in
                NavigationLink(value: AppRoute.passageDetail(citation.passageID)) {
                    Text("[\(citation.number)] \(citation.reference)")
                        .font(SWTypography.caption.weight(.semibold))
                        .foregroundStyle(SWColors.primary)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("ask.citation.\(citation.number)")
            }
        }
    }
}

private struct TraditionPassages: View {
    static let previewLimit = 3

    let group: SearchResultGroup
    let citedNumbers: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.s) {
            HStack(spacing: SWSpacing.s) {
                Text(group.religion.emblem + "\u{FE0E}")
                    .foregroundStyle(SWColors.tint(for: group.religion.tintKey))
                    .accessibilityHidden(true)
                Text(group.religion.name).font(SWTypography.headline).foregroundStyle(SWColors.textPrimary)
            }
            .accessibilityAddTraits(.isHeader)
            ForEach(group.results.prefix(Self.previewLimit)) { result in
                SWCard {
                    VStack(alignment: .leading, spacing: SWSpacing.s) {
                        HStack {
                            if let number = citedNumbers[result.passage.id] {
                                Text("[\(number)]").font(SWTypography.caption.weight(.bold)).foregroundStyle(SWColors.secondary)
                            }
                            Text(result.passage.reference).font(SWTypography.reference).foregroundStyle(SWColors.primary)
                            Spacer()
                            Text(group.collectionNames[result.passage.collectionID] ?? "")
                                .font(SWTypography.caption).foregroundStyle(SWColors.secondary)
                        }
                        if let preview = result.previewText {
                            Text(preview.text)
                                .font(SWTypography.scripture)
                                .foregroundStyle(SWColors.textPrimary)
                                .lineLimit(4)
                                .scriptureDirection(preview.translation.languageCode)
                            Text(preview.translation.name).font(SWTypography.caption).foregroundStyle(SWColors.textSecondary)
                        }
                        NavigationLink(value: AppRoute.passageDetail(result.passage.id, translationID: result.matchedTranslationID)) {
                            Label("View Full Passage", systemImage: "arrow.right.circle")
                                .font(SWTypography.caption.weight(.semibold))
                                .frame(minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .tint(SWColors.primary)
                        .accessibilityIdentifier("ask.viewPassage.\(result.passage.id)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ask.passage.\(result.passage.id)")
            }
        }
    }
}
