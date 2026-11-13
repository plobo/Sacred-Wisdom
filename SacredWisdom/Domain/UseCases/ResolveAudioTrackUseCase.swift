import Foundation

/// Decides whether text-to-speech may be made from a translation, from its source's license (spec §11:
/// "Do not generate audio for copyrighted translations without appropriate permissions").
///
/// Permitted: public domain, CC0, and CC BY / CC BY-SA (which allow adaptations with attribution; the player
/// always shows the translation's name). Anything else, including no-derivatives and non-commercial licenses
/// or terms that are not recognized, is refused. Unknown means no.
enum AudioLicensePolicy {
    static func allowsSynthesizedSpeech(_ source: ContentSource) -> Bool {
        let license = source.license.lowercased()
        if license.hasPrefix("public domain") || license.contains("cc0") { return true }
        // Tokenize so "and" never reads as "nd".
        let tokens = license.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let cc = tokens.firstIndex(of: "cc"), tokens.indices.contains(cc + 1), tokens[cc + 1] == "by" else {
            return false
        }
        let modifiers = tokens[(cc + 2)...].prefix { ["sa", "nc", "nd"].contains($0) }
        return !modifiers.contains("nd") && !modifiers.contains("nc")
    }
}

protocol ResolveAudioTrackUseCaseProtocol: Sendable {
    /// What can be played for this passage in this translation (the default translation if nil or missing).
    func execute(passage: ScripturePassage, translationID: String?) async -> AudioAvailability
}

/// A licensed recording wins; otherwise text-to-speech of the translation, if its license permits.
///
/// Original-language text is never synthesized. Synthetic recitation of the Quran or Gurbani would misrepresent
/// how those texts are recited, the Tanzil terms forbid altering the text, and devices have no voices for
/// Sanskrit, Pali or Gurmukhi. Originals can be offered as licensed recordings through `RecordedAudioCatalog`.
struct ResolveAudioTrackUseCase: ResolveAudioTrackUseCaseProtocol {
    let recordings: any RecordedAudioCatalog

    init(recordings: any RecordedAudioCatalog = EmptyRecordedAudioCatalog()) {
        self.recordings = recordings
    }

    func execute(passage: ScripturePassage, translationID: String?) async -> AudioAvailability {
        guard let text = passage.text(preferring: translationID) else { return .unavailable(.noText) }
        let translation = text.translation
        if let url = await recordings.recordingURL(passageID: passage.id, translationID: translation.id) {
            return .available(AudioTrack(passageID: passage.id, reference: passage.reference, translationID: translation.id,
                                         title: translation.name, content: .recording(url)))
        }
        guard AudioLicensePolicy.allowsSynthesizedSpeech(translation.source) else {
            return .unavailable(.licenseNotPermitted(sourceName: translation.source.name))
        }
        let spoken = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return .unavailable(.noText) }
        return .available(AudioTrack(passageID: passage.id, reference: passage.reference, translationID: translation.id,
                                     title: translation.name,
                                     content: .speech(text: spoken, languageCode: translation.languageCode)))
    }
}
