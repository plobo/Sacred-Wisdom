import SwiftUI

struct LoadingStateView: View {
    var message: LocalizedStringKey = "Loading…"

    var body: some View {
        VStack(spacing: SWSpacing.m) {
            ProgressView()
            Text(message)
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("state.loading")
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: SWSpacing.s) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(SWColors.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(SWTypography.headline)
                .foregroundStyle(SWColors.textPrimary)
            Text(message)
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(SWSpacing.l)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("state.empty")
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: SWSpacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(SWColors.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(SWTypography.body)
                .foregroundStyle(SWColors.textPrimary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(SWColors.onPrimary)
                .tint(SWColors.primary)
                .accessibilityIdentifier("state.error.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(SWSpacing.l)
        .accessibilityIdentifier("state.error")
    }
}
