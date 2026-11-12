import SwiftUI

/// Displays a verified scripture passage with its reference and attribution.
struct PassageCard: View {
    let passage: ScripturePassage
    var religionName: String?
    var lineLimit: Int?

    var body: some View {
        SWCard {
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                HStack {
                    Text(passage.reference)
                        .font(SWTypography.reference)
                        .foregroundStyle(SWColors.primary)
                    Spacer()
                    if let religionName {
                        Text(religionName)
                            .font(SWTypography.caption)
                            .foregroundStyle(SWColors.secondary)
                    }
                }
                if let original = passage.originalText {
                    Text(original)
                        .font(SWTypography.scripture)
                        .foregroundStyle(SWColors.textPrimary)
                        .lineLimit(lineLimit)
                        .scriptureDirection(passage.originalLanguage)
                }
                if let text = passage.texts.first {
                    Text(text.text)
                        .font(SWTypography.scripture.italic())
                        .foregroundStyle(SWColors.textPrimary)
                        .lineLimit(lineLimit)
                        .scriptureDirection(text.translation.languageCode)
                    Text(text.translation.name)
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("passageCard.\(passage.id)")
    }
}
