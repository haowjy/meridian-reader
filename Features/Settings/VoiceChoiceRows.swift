import SwiftUI

/// An on-device engine's voices as choice rows, each with its sample: the one list Settings ›
/// Voice and an article's or a book's voice picker (C138) both show. A downloaded pack can be
/// removed with a trailing swipe (*Remove Download*); Heart stays while it is the only curated
/// pack on disk so the picker never empties.
struct VoiceChoiceRows: View {
    let descriptor: EngineDescriptor
    /// The engine voice id with the checkmark ("af_heart").
    let current: String?
    /// The voice whose files are downloading (a spinner in its sample's slot).
    var preparingID: String?
    let preview: VoicePreviewPlayer
    let speech: SpeechController
    let onPick: (EngineVoice) -> Void

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        let _ = localTTS.voicePacksRevision
        ForEach(descriptor.voices) { voice in
            let installed = localTTS.isVoicePackInstalled(voice.id, for: descriptor.id)
            let detail = voice.id == descriptor.defaultVoiceID
                ? VoicePage.defaultVoiceSubtitle(voice.detail) : voice.detail
            let subtitle: DetailPart? = detail.isEmpty ? nil
                : (installed ? DetailPart.prepared(detail) : DetailPart(detail))
            SettingsChoiceRow(
                title: voice.label,
                subtitle: subtitle,
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if localTTS.canDeleteVoicePack(voice.id, for: descriptor.id) {
                    Button(Verbs.removeModelDownload, role: .destructive) {
                        try? localTTS.deleteVoicePack(voice.id, for: descriptor.id)
                    }
                    .accessibilityIdentifier("voiceRemoveDownload-\(voice.id)")
                }
            }
        }
    }
}
