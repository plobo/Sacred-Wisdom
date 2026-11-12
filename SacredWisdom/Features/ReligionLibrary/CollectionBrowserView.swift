import SwiftUI

/// Table of contents for a collection: books (with optional division) and their sections.
struct CollectionBrowserView: View {
    @State var viewModel: CollectionBrowserViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView()
            case .failed(let message):
                ErrorStateView(message: message) { Task { await viewModel.load() } }
            case .loaded(let contents):
                loaded(contents)
            }
        }
        .swScreenBackground()
        .accessibilityIdentifier("screen.collectionBrowser")
        .task { if viewModel.state == .idle { await viewModel.load() } }
    }

    private func loaded(_ contents: CollectionContents) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: SWSpacing.xs) {
                    Text(contents.collection.structureDescription)
                        .font(SWTypography.body)
                        .foregroundStyle(SWColors.textPrimary)
                    if let summary = viewModel.languageSummary {
                        Text(summary)
                            .font(SWTypography.caption)
                            .foregroundStyle(SWColors.textSecondary)
                    }
                }
                .listRowBackground(SWColors.surface)
            }
            if contents.books.isEmpty {
                EmptyStateView(systemImage: "book", title: "No content yet", message: "This collection has no passages installed.")
                    .listRowBackground(Color.clear)
            }
            ForEach(contents.books) { entry in
                Section {
                    ForEach(entry.sections) { section in
                        NavigationLink(value: AppRoute.reader(.section(section.id))) {
                            Text(section.title)
                                .font(SWTypography.body)
                                .foregroundStyle(SWColors.textPrimary)
                        }
                        .accessibilityIdentifier("section.\(section.id)")
                        .listRowBackground(SWColors.surface)
                    }
                } header: {
                    BookHeader(book: entry.book)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(contents.collection.name)
    }
}

private struct BookHeader: View {
    let book: ScriptureBook

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let division = book.division {
                Text(division)
                    .font(SWTypography.caption)
                    .foregroundStyle(SWColors.secondary)
            }
            Text(book.title)
                .font(SWTypography.headline)
                .foregroundStyle(SWColors.textPrimary)
                .textCase(nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
