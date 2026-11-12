import SwiftUI

struct DetailHeader: View {
    let detail: PassageDetail

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.xs) {
            HStack(spacing: SWSpacing.xs) {
                Text(detail.religion.emblem + "\u{FE0E}")
                    .foregroundStyle(SWColors.tint(for: detail.religion.tintKey))
                    .accessibilityHidden(true)
                Text("\(detail.religion.name) · \(detail.collection.name)")
            }
            .font(SWTypography.caption)
            .foregroundStyle(SWColors.secondary)
            Text(detail.section.title)
                .font(SWTypography.title)
                .foregroundStyle(SWColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(detail.passage.reference)
                .font(SWTypography.headline)
                .foregroundStyle(SWColors.primary)
                .accessibilityIdentifier("detail.reference")
        }
    }
}

/// Credits every source shown on the screen, with its license.
struct DetailAttribution: View {
    let passage: ScripturePassage
    let texts: [PassageText]

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.xs) {
            ForEach(texts, id: \.translation.id) { text in
                Text("\(text.translation.source.attribution) \(text.translation.source.license).")
            }
            if passage.originalText != nil, let source = passage.originalSource,
               !texts.contains(where: { $0.translation.source.id == source.id }) {
                Text("Original text: \(source.attribution) \(source.license).")
            }
        }
        .font(SWTypography.caption)
        .foregroundStyle(SWColors.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.attribution")
    }
}

struct DetailNoteSection: View {
    let note: String?
    let isBookmarked: Bool
    let collectionName: String?
    let collections: [BookmarkCollection]
    let onEditNote: () -> Void
    let onMove: (UUID?) -> Void
    let onNewCollection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            SectionHeader(title: "My Note")
            SWCard {
                VStack(alignment: .leading, spacing: SWSpacing.m) {
                    if let note {
                        Text(note)
                            .font(SWTypography.body)
                            .foregroundStyle(SWColors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("detail.noteText")
                    } else {
                        Text("Add a private reflection on this passage.")
                            .font(SWTypography.caption)
                            .foregroundStyle(SWColors.textSecondary)
                    }
                    HStack {
                        Button(action: onEditNote) {
                            Label(note == nil ? "Add Note" : "Edit Note", systemImage: "square.and.pencil")
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("detail.editNote")
                        Spacer()
                        if isBookmarked {
                            Menu {
                                Button { onMove(nil) } label: {
                                    selectionLabel("Unfiled", selected: collectionName == nil)
                                }
                                ForEach(collections) { collection in
                                    Button { onMove(collection.id) } label: {
                                        selectionLabel(collection.name, selected: collectionName == collection.name)
                                    }
                                }
                                Divider()
                                Button("New Collection…", systemImage: "folder.badge.plus", action: onNewCollection)
                                    .accessibilityIdentifier("detail.newCollection")
                            } label: {
                                Label(collectionName ?? String(localized: "Unfiled"), systemImage: "folder")
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(Text("Collection: \(collectionName ?? String(localized: "Unfiled"))"))
                            .accessibilityIdentifier("detail.collectionMenu")
                        }
                    }
                    .font(SWTypography.caption.weight(.semibold))
                    .tint(SWColors.primary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.note")
    }

    @ViewBuilder
    private func selectionLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

/// Where the passage sits, from the collection's own structure. No commentary is generated.
struct DetailContextSection: View {
    let detail: PassageDetail
    let originalLanguageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            SectionHeader(title: "Context")
            SWCard {
                VStack(alignment: .leading, spacing: SWSpacing.s) {
                    row("Collection", detail.collection.name)
                    row("Book", [detail.book.title, detail.book.division].compactMap { $0 }.joined(separator: " · "))
                    row("Section", detail.section.title)
                    row("Position", String(localized: "Passage \(detail.positionInSection) of \(detail.sectionPassageCount)"))
                    if detail.passage.originalText != nil {
                        row("Original language", originalLanguageName)
                    }
                    if !detail.themes.isEmpty {
                        row("Themes", detail.themes.map(\.name).joined(separator: ", "))
                    }
                    Text("Context comes from the collection’s structure. Themes are editorial labels for what the passage itself mentions. No commentary is generated.")
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                        .padding(.top, SWSpacing.xs)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.context")
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(SWColors.textPrimary)
        } label: {
            Text(title).foregroundStyle(SWColors.textSecondary)
        }
        .font(SWTypography.caption)
    }
}

struct RelatedPassagesSection: View {
    let related: [RelatedPassage]

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.m) {
            SectionHeader(title: "Related Passages")
            Text("From other traditions, linked by shared editorial themes.")
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.textSecondary)
            if related.isEmpty {
                EmptyStateView(systemImage: "link", title: "No related passages yet",
                               message: "None of the installed passages from other traditions share a theme with this one.")
            } else {
                ForEach(related) { item in
                    NavigationLink(value: AppRoute.passageDetail(item.passage.id)) {
                        RelatedPassageCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("relatedPassage.\(item.passage.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.related")
    }
}

private struct RelatedPassageCard: View {
    let item: RelatedPassage

    var body: some View {
        SWCard {
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.religion.emblem + "\u{FE0E}")
                        .foregroundStyle(SWColors.tint(for: item.religion.tintKey))
                        .accessibilityHidden(true)
                    Text(item.passage.reference)
                        .font(SWTypography.reference)
                        .foregroundStyle(SWColors.primary)
                    Spacer()
                    Text(item.religion.name)
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(SWColors.textSecondary)
                        .accessibilityHidden(true)
                }
                if let text = item.passage.texts.first {
                    Text(text.text)
                        .font(SWTypography.scripture)
                        .foregroundStyle(SWColors.textPrimary)
                        .lineLimit(3)
                        .scriptureDirection(text.translation.languageCode)
                }
                Text("Shared theme: \(item.sharedThemes.map(\.name).joined(separator: ", "))")
                    .font(SWTypography.caption.weight(.semibold))
                    .foregroundStyle(SWColors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
