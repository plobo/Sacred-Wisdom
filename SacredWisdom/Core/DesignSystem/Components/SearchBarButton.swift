import SwiftUI

/// A search-field lookalike that opens the Search tab when tapped.
struct SearchBarButton: View {
    let placeholder: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SWSpacing.s) {
                Image(systemName: "magnifyingglass")
                Text(placeholder)
                Spacer()
                Image(systemName: "mic.fill")
                    .foregroundStyle(SWColors.primary)
            }
            .font(SWTypography.body)
            .foregroundStyle(SWColors.textSecondary)
            .padding(.horizontal, SWSpacing.l)
            .padding(.vertical, SWSpacing.m)
            .background(SWColors.surface, in: RoundedRectangle(cornerRadius: SWRadius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SWRadius.field, style: .continuous)
                    .strokeBorder(SWColors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(placeholder))
        .accessibilityHint(Text("Opens universal search"))
    }
}
