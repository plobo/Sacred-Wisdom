import SwiftUI

/// Card for one religious tradition. Every tradition uses the identical layout and size.
struct ReligionCard: View {
    let summary: ReligionSummary

    @ScaledMetric(relativeTo: .title) private var emblemSize: CGFloat = 30
    @ScaledMetric(relativeTo: .title) private var badgeSize: CGFloat = 44

    var body: some View {
        SWCard {
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                HStack {
                    // U+FE0E forces text presentation so no emblem renders as a color emoji.
                    Text(summary.religion.emblem + "\u{FE0E}")
                        .font(.system(size: emblemSize))
                        .foregroundStyle(SWColors.tint(for: summary.religion.tintKey))
                        .frame(width: badgeSize, height: badgeSize)
                        .background(
                            SWColors.tint(for: summary.religion.tintKey).opacity(0.12),
                            in: Circle()
                        )
                        .accessibilityHidden(true)
                    Spacer()
                    if summary.collection?.isAvailableOffline == true {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SWColors.secondary)
                            .accessibilityLabel(Text("Available offline"))
                    }
                }
                Text(summary.religion.name)
                    .font(SWTypography.headline)
                    .foregroundStyle(SWColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary.collection?.name ?? "")
                    .font(SWTypography.caption)
                    .foregroundStyle(SWColors.textSecondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("religionCard.\(summary.religion.id)")
    }
}
