import SwiftUI

/// Toggleable capsule used for filters. Selected chips are filled with the primary color.
struct FilterChip: View {
    let title: String
    var emblem: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SWSpacing.xs) {
                if let emblem {
                    Text(emblem + "\u{FE0E}").accessibilityHidden(true)
                }
                Text(title)
            }
            .font(SWTypography.caption.weight(.semibold))
            .padding(.horizontal, SWSpacing.m)
            .padding(.vertical, SWSpacing.s)
            .foregroundStyle(isSelected ? SWColors.onPrimary : SWColors.textPrimary)
            .background(isSelected ? SWColors.primary : SWColors.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : SWColors.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
