import SwiftUI

/// Screen 3 (Religion Library): collection metadata and the Browse action.
struct ReligionLibraryView: View {
    let summary: ReligionSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SWSpacing.l) {
                Text(summary.religion.summary)
                    .font(SWTypography.body)
                    .foregroundStyle(SWColors.textSecondary)
                if let collection = summary.collection {
                    SWCard {
                        VStack(alignment: .leading, spacing: SWSpacing.s) {
                            Text(collection.name)
                                .font(SWTypography.title)
                                .foregroundStyle(SWColors.textPrimary)
                            Text(collection.structureDescription)
                                .font(SWTypography.body)
                                .foregroundStyle(SWColors.textSecondary)
                            LabeledContent("Languages", value: collection.languages.map(Self.languageName).joined(separator: ", "))
                            LabeledContent("Status", value: Self.statusText(collection.availability))
                        }
                        .font(SWTypography.caption)
                    }
                    .accessibilityIdentifier("religionLibrary.collection")
                    NavigationLink(value: AppRoute.collection(collection.id)) {
                        Label("Browse \(collection.name)", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                .foregroundStyle(SWColors.onPrimary)
                    .controlSize(.large)
                    .tint(SWColors.primary)
                    .accessibilityIdentifier("religionLibrary.browse")
                } else {
                    EmptyStateView(systemImage: "books.vertical", title: "No collection", message: "No collection is installed for this tradition yet.")
                }
            }
            .padding(SWSpacing.l)
        }
        .swScreenBackground()
        .navigationTitle(summary.religion.name)
        .accessibilityIdentifier("screen.religionLibrary")
    }

    private static func languageName(_ code: String) -> String {
        LanguageInfo.displayName(code)
    }

    private static func statusText(_ availability: ScriptureCollection.Availability) -> String {
        switch availability {
        case .bundled: String(localized: "Sample included")
        case .downloaded: String(localized: "Downloaded")
        case .notDownloaded: String(localized: "Not downloaded")
        }
    }
}
