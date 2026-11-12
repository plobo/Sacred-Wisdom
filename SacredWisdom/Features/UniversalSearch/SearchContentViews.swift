import SwiftUI

struct SearchIdleContent: View {
    let recent: [SearchHistoryItem]
    let suggestions: [String]
    let onSelect: (String) -> Void
    let onRemove: (UUID) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.xl) {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: SWSpacing.s) {
                    HStack {
                        SectionHeader(title: "Recent Searches")
                        Button("Clear", action: onClear)
                            .font(SWTypography.caption)
                            .tint(SWColors.primary)
                            .accessibilityIdentifier("search.clearRecent")
                    }
                    ForEach(recent) { item in
                        HStack {
                            Button { onSelect(item.query) } label: {
                                Label(item.query, systemImage: "clock.arrow.circlepath")
                                    .foregroundStyle(SWColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recentSearch.\(item.query)")
                            Button { onRemove(item.id) } label: {
                                Image(systemName: "xmark").foregroundStyle(SWColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove \(item.query)"))
                        }
                        .font(SWTypography.body)
                        .padding(.vertical, SWSpacing.xs)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("search.recent")
            }
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                SectionHeader(title: "Suggested Questions")
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
                    .accessibilityIdentifier("suggestion.\(index)")
                }
            }
        }
    }
}

struct SearchResultsContent: View {
    let results: SearchResults
    let isBookmarked: (String) -> Bool
    let onToggleBookmark: (String) -> Void

    private var includesPartialMatches: Bool {
        results.groups.contains { $0.results.contains { !$0.matchedAllTerms } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.xl) {
            VStack(alignment: .leading, spacing: SWSpacing.xs) {
                Text(SearchResultsSummary.text(passages: results.totalCount, traditions: results.groups.count))
                    .font(SWTypography.caption.weight(.semibold))
                    .foregroundStyle(SWColors.textSecondary)
                    .accessibilityIdentifier("search.summary")
                if includesPartialMatches {
                    Text("Includes passages that match some of your words.")
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                }
            }
            ForEach(results.groups) { group in
                SearchResultGroupView(group: group, highlightTerms: results.query.highlightTerms,
                                      isBookmarked: isBookmarked, onToggleBookmark: onToggleBookmark)
            }
        }
    }
}

private struct SearchResultGroupView: View {
    let group: SearchResultGroup
    let highlightTerms: [String]
    let isBookmarked: (String) -> Bool
    let onToggleBookmark: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            HStack(spacing: SWSpacing.s) {
                Text(group.religion.emblem + "\u{FE0E}")
                    .foregroundStyle(SWColors.tint(for: group.religion.tintKey))
                    .accessibilityHidden(true)
                Text(group.religion.name)
                    .font(SWTypography.headline)
                    .foregroundStyle(SWColors.textPrimary)
                Spacer()
                Text("\(group.results.count)")
                    .font(SWTypography.caption.weight(.semibold))
                    .foregroundStyle(SWColors.textSecondary)
                    .accessibilityLabel(Text(group.results.count == 1 ? String(localized: "1 result")
                                                                      : String(localized: "\(group.results.count) results")))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("searchGroup.\(group.religion.id)")
            ForEach(group.results) { result in
                // The bookmark button sits beside the link, not inside it, so each stays its own control.
                ZStack(alignment: .bottomTrailing) {
                    NavigationLink(value: AppRoute.passageDetail(result.passage.id, translationID: result.matchedTranslationID)) {
                        SearchResultCard(
                            result: result,
                            religion: group.religion,
                            collectionName: group.collectionNames[result.passage.collectionID] ?? "",
                            highlightTerms: highlightTerms
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("searchResult.\(result.passage.id)")
                    let saved = isBookmarked(result.passage.id)
                    Button { onToggleBookmark(result.passage.id) } label: {
                        Image(systemName: saved ? "bookmark.fill" : "bookmark")
                            .font(.body)
                            .foregroundStyle(SWColors.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(SWSpacing.xs)
                    .accessibilityLabel(saved ? Text("Remove Bookmark, \(result.passage.reference)")
                                              : Text("Bookmark \(result.passage.reference)"))
                    .accessibilityAddTraits(saved ? .isSelected : [])
                    .accessibilityIdentifier("searchResult.bookmark.\(result.passage.id)")
                }
            }
        }
    }
}

/// Screen 6 result card: religion, collection, reference, preview, translation, navigation indicator.
struct SearchResultCard: View {
    let result: ScriptureSearchResult
    let religion: Religion
    let collectionName: String
    let highlightTerms: [String]

    var body: some View {
        SWCard {
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.passage.reference)
                        .font(SWTypography.reference)
                        .foregroundStyle(SWColors.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(SWColors.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(collectionName)
                    .font(SWTypography.caption)
                    .foregroundStyle(SWColors.secondary)
                if let original = result.passage.originalText,
                   SearchHighlighter.matchesFolded(highlightTerms, in: original) {
                    // The query matched the original script: show it, verbatim, in its own direction.
                    Text(original)
                        .font(SWTypography.scripture)
                        .foregroundStyle(SWColors.textPrimary)
                        .lineLimit(3)
                        .scriptureDirection(result.passage.originalLanguage)
                }
                if let preview = result.previewText {
                    Text(SearchHighlighter.attributed(preview.text, terms: highlightTerms))
                        .font(SWTypography.scripture)
                        .foregroundStyle(SWColors.textPrimary)
                        .lineLimit(4)
                        .scriptureDirection(preview.translation.languageCode)
                    Text(preview.translation.name)
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum SearchResultsSummary {
    static func text(passages: Int, traditions: Int) -> String {
        let passageText = passages == 1 ? String(localized: "1 passage") : String(localized: "\(passages) passages")
        let traditionText = traditions == 1 ? String(localized: "1 tradition") : String(localized: "\(traditions) traditions")
        return String(localized: "\(passageText) in \(traditionText)")
    }
}
