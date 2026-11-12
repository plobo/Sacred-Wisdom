import SwiftUI

/// Rounded surface container used by every card in the app.
struct SWCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(SWSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SWColors.surface, in: RoundedRectangle(cornerRadius: SWRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SWRadius.card, style: .continuous)
                    .strokeBorder(SWColors.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}
