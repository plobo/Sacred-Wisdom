import SwiftUI

struct ReaderPassageContent: View {
    let page: ReaderPage
    let text: PassageText?
    let fontScale: Double
    let isOriginalRightToLeft: Bool
    let originalLanguageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.l) {
            VStack(alignment: .leading, spacing: SWSpacing.xs) {
                Text([page.book.division, page.book.title].compactMap { $0 }.joined(separator: " · "))
                    .font(SWTypography.caption)
                    .foregroundStyle(SWColors.secondary)
                Text(page.section.title)
                    .font(SWTypography.title)
                    .foregroundStyle(SWColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(page.passage.reference)
                    .font(SWTypography.reference)
                    .foregroundStyle(SWColors.primary)
                    .accessibilityIdentifier("reader.reference")
            }
            if let original = page.passage.originalText {
                OriginalTextBlock(
                    text: original,
                    languageName: originalLanguageName,
                    isRightToLeft: isOriginalRightToLeft,
                    fontScale: fontScale
                )
            }
            if let text {
                TranslationTextBlock(text: text, fontScale: fontScale)
            }
            AttributionFooter(originalSource: page.passage.originalSource, translation: text?.translation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Original-language text: larger, gold-accented, and laid out right-to-left where needed.
struct OriginalTextBlock: View {
    let text: String
    let languageName: String
    let isRightToLeft: Bool
    let fontScale: Double
    var identifier = "reader.originalText"

    @ScaledMetric(relativeTo: .title3) private var baseSize: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.s) {
            BlockLabel(title: "Original", detail: languageName, systemImage: "book.closed")
            Text(text)
                .font(.system(size: baseSize * fontScale, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(SWColors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, SWSpacing.xs) // room for Arabic and Hebrew marks above and below the line
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight) // own direction, not the UI's
                .textSelection(.enabled)
                .accessibilityIdentifier(identifier)
        }
        .padding(SWSpacing.l)
        .background(SWColors.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: SWRadius.card, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(SWColors.secondary).frame(width: 4).padding(.vertical, SWSpacing.m)
        }
    }
}

/// Translation text: body-size serif on a plain card, labeled with the translation name.
struct TranslationTextBlock: View {
    let text: PassageText
    let fontScale: Double
    var identifier = "reader.translationText"

    @ScaledMetric(relativeTo: .body) private var baseSize: CGFloat = 18

    var body: some View {
        SWCard {
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                BlockLabel(title: "Translation", detail: text.translation.name, systemImage: "text.quote")
                Text(text.text)
                    .font(.system(size: baseSize * fontScale, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(SWColors.textPrimary)
                    .textSelection(.enabled)
                    .scriptureDirection(text.translation.languageCode)
                    .accessibilityIdentifier(identifier)
            }
        }
    }
}

private struct BlockLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: LocalizedStringKey
    let detail: String
    let systemImage: String

    var body: some View {
        // Stacks at accessibility sizes so words are never hyphenated across a cramped row.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SWSpacing.xs))
            : AnyLayout(HStackLayout(spacing: SWSpacing.xs))
        layout {
            Image(systemName: systemImage).accessibilityHidden(true)
            Text(title).fontWeight(.semibold)
            Text(dynamicTypeSize.isAccessibilitySize ? detail : "· \(detail)")
        }
        .font(SWTypography.caption)
        .foregroundStyle(SWColors.textSecondary)
        .textCase(.uppercase)
    }
}

struct AttributionFooter: View {
    let originalSource: ContentSource?
    let translation: Translation?

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.xs) {
            if let translation {
                Text("\(translation.source.attribution) \(translation.source.license).")
            }
            if let originalSource, originalSource.id != translation?.source.id {
                Text("Original text: \(originalSource.attribution) \(originalSource.license).")
            }
        }
        .font(SWTypography.caption)
        .foregroundStyle(SWColors.textSecondary)
        .accessibilityIdentifier("reader.attribution")
    }
}

struct ReaderNavigationBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let reference: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!canGoPrevious)
            .accessibilityIdentifier("reader.previous")
            Spacer()
            Text(reference)
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onNext) {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(dynamicTypeSize.isAccessibilitySize ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(TrailingIconLabelStyle()))
            }
            .disabled(!canGoNext)
            .accessibilityIdentifier("reader.next")
        }
        .font(SWTypography.body.weight(.semibold))
        // At accessibility sizes the buttons show icons only (VoiceOver still reads "Previous"/"Next") and the
        // bar stops growing, so it never covers the passage.
        .labelStyle(dynamicTypeSize.isAccessibilitySize ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .tint(SWColors.primary)
        .padding(.horizontal, SWSpacing.l)
        .padding(.vertical, SWSpacing.m)
        .background(.bar)
    }
}

/// Type-erased label style so the bar can switch styles with Dynamic Type.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: SWSpacing.xs) {
            configuration.title
            configuration.icon
        }
    }
}

struct TranslationMenu: View {
    let translations: [Translation]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(translations) { translation in
                Button {
                    onSelect(translation.id)
                } label: {
                    if translation.id == selectedID {
                        Label(translation.name, systemImage: "checkmark")
                    } else {
                        Text(translation.name)
                    }
                }
                .accessibilityIdentifier("translation.\(translation.id)")
            }
        } label: {
            Image(systemName: "character.bubble")
        }
        .accessibilityLabel(Text("Translation"))
        .accessibilityIdentifier("reader.translationMenu")
    }
}

struct FontSizeMenu: View {
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        Menu {
            Button(action: onIncrease) { Label("Larger Text", systemImage: "textformat.size.larger") }
                .disabled(!canIncrease)
                .accessibilityIdentifier("reader.fontLarger")
            Button(action: onDecrease) { Label("Smaller Text", systemImage: "textformat.size.smaller") }
                .disabled(!canDecrease)
                .accessibilityIdentifier("reader.fontSmaller")
        } label: {
            Image(systemName: "textformat.size")
        }
        .accessibilityLabel(Text("Text Size"))
        .accessibilityIdentifier("reader.fontMenu")
    }
}
