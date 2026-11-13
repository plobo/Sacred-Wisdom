import SwiftUI

/// Compact player for passage audio: play/pause, progress, speed, voice and (in verse details) which
/// translation to hear. Shows why listening is unavailable instead, when it is.
struct AudioPlayerBar: View {
    struct TranslationChoice: Identifiable, Equatable {
        let id: String
        let name: String
    }

    let controller: AudioPlaybackController
    var translationChoices: [TranslationChoice] = []
    var selectedTranslationID: String?
    var onSelectTranslation: (String) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch controller.status {
        case .idle:
            EmptyView()
        case .unavailable(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "speaker.slash")
            }
            .font(SWTypography.caption)
            .foregroundStyle(SWColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("audio.unavailable")
        default:
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SWSpacing.s) {
                    HStack(spacing: SWSpacing.m) { playButton; progressColumn }
                    HStack(spacing: SWSpacing.l) { menus }
                }
            } else {
                HStack(spacing: SWSpacing.m) {
                    playButton
                    progressColumn
                    menus
                }
            }
        }
    }

    private var playButton: some View {
        Button(action: { controller.togglePlayPause() }) {
            Image(systemName: playSymbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(SWColors.primary, in: Circle())
                .foregroundStyle(SWColors.onPrimary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(playLabel))
        .accessibilityValue(Text(controller.accessibilityStatus))
        .accessibilityIdentifier("audio.playPause")
    }

    private var progressColumn: some View {
        VStack(alignment: .leading, spacing: SWSpacing.xs) {
            Text(caption)
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                // The progress bar is not interactive, so VoiceOver hears progress here, on the caption.
                .accessibilityValue(Text("\(Int((controller.progress * 100).rounded())) percent"))
                .accessibilityIdentifier("audio.status")
            ProgressView(value: controller.progress)
                .tint(SWColors.primary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var menus: some View {
        Menu {
            Picker("Playback Speed", selection: Binding(get: { controller.speed }, set: { controller.setSpeed($0) })) {
                ForEach(PlaybackSpeed.all, id: \.self) { Text(PlaybackSpeed.label($0)).tag($0) }
            }
        } label: {
            Text(PlaybackSpeed.label(controller.speed))
                .font(SWTypography.body.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("Playback Speed"))
        .accessibilityValue(Text(PlaybackSpeed.label(controller.speed)))
        .accessibilityIdentifier("audio.speed")
        if controller.voices.count > 1 {
            Menu {
                Picker("Voice", selection: Binding(get: { controller.selectedVoiceID ?? "" }, set: { controller.selectVoice($0) })) {
                    ForEach(controller.voices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
            } label: {
                Image(systemName: "person.wave.2")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Voice"))
            .accessibilityValue(Text(controller.voices.first { $0.id == controller.selectedVoiceID }?.displayName ?? ""))
            .accessibilityIdentifier("audio.voice")
        }
        if translationChoices.count > 1 {
            Menu {
                Picker("Listen To", selection: Binding(get: { selectedTranslationID ?? "" }, set: { onSelectTranslation($0) })) {
                    ForEach(translationChoices) { Text($0.name).tag($0.id) }
                }
            } label: {
                Image(systemName: "character.book.closed")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Listen To"))
            .accessibilityValue(Text(translationChoices.first { $0.id == selectedTranslationID }?.name ?? ""))
            .accessibilityIdentifier("audio.translation")
        }
    }

    private var playSymbol: String {
        switch controller.status {
        case .playing: "pause.fill"
        case .finished: "arrow.counterclockwise"
        default: "play.fill"
        }
    }

    private var playLabel: LocalizedStringKey {
        switch controller.status {
        case .playing: "Pause"
        case .paused: "Resume"
        case .finished: "Play Again"
        default: "Listen"
        }
    }

    private var caption: String {
        // Synthesized speech is labeled as such, so it is never mistaken for a recording.
        let title = controller.track.map { $0.isRecording ? $0.title : String(localized: "\($0.title), system voice") } ?? ""
        return switch controller.status {
        case .failed(let message): message
        case .playing: String(localized: "Playing · \(title)")
        case .paused: String(localized: "Paused · \(title)")
        case .finished: String(localized: "Finished · \(title)")
        default: String(localized: "Listen · \(title)")
        }
    }
}
