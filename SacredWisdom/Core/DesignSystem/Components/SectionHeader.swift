import SwiftUI

struct SectionHeader: View {
    let title: LocalizedStringKey
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SWTypography.title)
                .foregroundStyle(SWColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(SWTypography.caption)
                    .foregroundStyle(SWColors.textSecondary)
            }
        }
    }
}
