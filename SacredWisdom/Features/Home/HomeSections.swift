import SwiftUI

struct HomeHeader: View {
    let greeting: String

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.xs) {
            Text(greeting)
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.secondary)
                .textCase(.uppercase)
            Text("Welcome to Sacred Wisdom")
                .font(SWTypography.largeTitle)
                .foregroundStyle(SWColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Timeless Teachings, One Journey")
                .font(SWTypography.body)
                .foregroundStyle(SWColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.header")
    }
}

struct HomeCollectionsSection: View {
    let religions: [ReligionSummary]
    let offlineSummary: String?
    let onSelect: (ReligionSummary) -> Void

    private let columns = [GridItem(.flexible(), spacing: SWSpacing.m), GridItem(.flexible(), spacing: SWSpacing.m)]

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            SectionHeader(title: "Sacred Collections", trailing: offlineSummary)
                .accessibilityIdentifier("home.collections.header")
            if religions.isEmpty {
                EmptyStateView(systemImage: "books.vertical", title: "No collections", message: "Collections will appear here once content is installed.")
            } else {
                LazyVGrid(columns: columns, spacing: SWSpacing.m) {
                    ForEach(religions) { summary in
                        Button { onSelect(summary) } label: { ReligionCard(summary: summary) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct HomeDailyPassageSection: View {
    let passage: ScripturePassage?
    let religionName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            SectionHeader(title: "Daily Passage")
            if let passage {
                NavigationLink(value: AppRoute.reader(.passage(passage.id))) {
                    PassageCard(passage: passage, religionName: religionName)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.dailyPassage.open")
            } else {
                EmptyStateView(systemImage: "sun.horizon", title: "No passage today", message: "Install a collection to receive a daily passage.")
            }
        }
        // A container keeps its own identifier without overriding its children's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.dailyPassage")
    }
}

struct HomeAskCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SWCard {
                HStack(spacing: SWSpacing.m) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.title2)
                        .foregroundStyle(SWColors.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SWSpacing.xs) {
                        Text("Ask a Question")
                            .font(SWTypography.headline)
                            .foregroundStyle(SWColors.textPrimary)
                        Text("Or say “Hey Siri, ask Sacred Wisdom…”")
                            .font(SWTypography.caption)
                            .foregroundStyle(SWColors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(SWColors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.askQuestion")
    }
}

struct HomeRecentSection: View {
    let passages: [ScripturePassage]
    let religionName: (String) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            SectionHeader(title: "Recently Viewed")
            if passages.isEmpty {
                EmptyStateView(systemImage: "clock", title: "Nothing yet", message: "Passages you read will appear here.")
            } else {
                ForEach(passages) { passage in
                    NavigationLink(value: AppRoute.reader(.passage(passage.id))) {
                        PassageCard(passage: passage, religionName: religionName(passage.religionID), lineLimit: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // A container keeps its own identifier without overriding its children's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.recent")
    }
}
