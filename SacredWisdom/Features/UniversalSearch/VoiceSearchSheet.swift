import SwiftUI

/// Listens and shows the live transcript; hands the final text to the search.
struct VoiceSearchSheet: View {
    @State var viewModel: VoiceSearchViewModel
    let onResult: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    var body: some View {
        VStack(spacing: SWSpacing.l) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(viewModel.isListening ? SWColors.primary : SWColors.secondary)
                .symbolEffect(.pulse, isActive: viewModel.isListening)
                .accessibilityHidden(true)
            Text(caption)
                .font(SWTypography.caption.weight(.semibold))
                .foregroundStyle(SWColors.textSecondary)
                .textCase(.uppercase)
            Text(message)
                .font(SWTypography.headline)
                .foregroundStyle(SWColors.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityIdentifier("voice.transcript")
            HStack(spacing: SWSpacing.m) {
                Button("Cancel") {
                    Task { await viewModel.cancel() }
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("voice.cancel")
                if case .failed = viewModel.state {
                    Button("Try Again") { Task { await viewModel.start() } }
                        .buttonStyle(.borderedProminent)
                .foregroundStyle(SWColors.onPrimary)
                        .accessibilityIdentifier("voice.retry")
                } else {
                    Button("Done") { Task { await viewModel.stop() } }
                        .buttonStyle(.borderedProminent)
                .foregroundStyle(SWColors.onPrimary)
                        .disabled(!viewModel.isListening)
                        .accessibilityIdentifier("voice.done")
                }
            }
            .tint(SWColors.primary)
            Text("Voice input is processed on this device.")
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.textSecondary)
        }
        .padding(SWSpacing.xl)
        .presentationDetents([.height(340)])
        .swScreenBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.voiceSearch")
        .task { await viewModel.start() }
        .onChange(of: viewModel.state) { _, state in
            if case .finished(let text) = state {
                onResult(text)
                viewModel.reset()
                dismiss()
            }
        }
    }

    private var icon: String {
        if case .failed = viewModel.state { return "mic.slash" }
        return "mic.fill"
    }

    private var caption: LocalizedStringKey {
        switch viewModel.state {
        case .idle, .preparing: "Getting ready"
        case .listening: "Listening"
        case .finished: "Searching"
        case .failed: "Voice input unavailable"
        }
    }

    private var message: String {
        switch viewModel.state {
        case .failed(let message): message
        case .listening(let text) where text.isEmpty: String(localized: "Say what you’re looking for…")
        default: viewModel.transcript
        }
    }
}
