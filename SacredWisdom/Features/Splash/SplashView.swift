import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: SWSpacing.l) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 64))
                .foregroundStyle(SWColors.secondary)
                .accessibilityHidden(true)
            Text("Sacred Wisdom")
                .font(SWTypography.largeTitle)
                .foregroundStyle(SWColors.primary)
            Text("Timeless Teachings, One Journey")
                .font(SWTypography.body)
                .foregroundStyle(SWColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .swScreenBackground()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("screen.splash")
    }
}
