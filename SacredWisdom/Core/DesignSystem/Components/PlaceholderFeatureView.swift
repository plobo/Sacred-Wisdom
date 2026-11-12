import SwiftUI

/// Temporary screen for features scheduled in later phases.
struct PlaceholderFeatureView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey
    let identifier: String

    var body: some View {
        ScrollView {
            EmptyStateView(systemImage: systemImage, title: title, message: message)
                .padding(.top, SWSpacing.xxl)
        }
        .swScreenBackground()
        .navigationTitle(Text(title))
        .accessibilityIdentifier(identifier)
    }
}
