import SwiftUI

/// An on-device engine's voices as choice rows, each with its sample: the one list Settings ›
/// Voice and an article's or a book's voice picker (C138) both show.
struct VoiceChoiceRows: View {
    let descriptor: EngineDescriptor
    /// The engine voice id with the checkmark ("af_heart").
    let current: String?
    /// The voice whose files are downloading (a spinner in its sample's slot).
    var preparingID: String?
    let preview: VoicePreviewPlayer
    let speech: SpeechController
    let onPick: (EngineVoice) -> Void

    var body: some View {
        ForEach(descriptor.voices) { voice in
            SettingsChoiceRow(
                title: voice.label,
                subtitle: DetailPart(voice.id == descriptor.defaultVoiceID ? VoicePage.defaultVoiceSubtitle(voice.detail) : voice.detail),
                selected: current == voice.id && preparingID == nil,
                accessibilityID: "voiceRow-\(voice.id)"
            ) {
                onPick(voice)
            } accessory: {
                if preparingID == voice.id {
                    // A voice downloading shows as every download does (its size is unknown, so
                    // the mark's spinner), in the slot the sample leaves while it prepares.
                    ModelDownloadMark(fraction: nil)
                        .accessibilityLabel("Downloading \(voice.label)")
                } else if VoicePreviewPlayer.hasPreview(voice) {
                    Button {
                        if speech.isPlaying { speech.pause() }
                        preview.toggle(voice)
                    } label: {
                        Image(systemName: preview.playingID == voice.id ? Icons.previewStop : Icons.previewPlay)
                            .tileSymbol()
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preview.playingID == voice.id ? "Stop preview" : "Preview \(voice.label)")
                    .accessibilityIdentifier("voicePreview-\(voice.id)")
                }
            }
        }
    }
}
