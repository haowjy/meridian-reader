import SwiftUI

/// An on-device engine's voices as `VoiceRow`s, each with its sample and its download: the one
/// list Settings › Voice and an article's or a book's voice picker (C138) both show. A voice that
/// isn't on the device shows its size and ⤓; picking it downloads it (`VoiceDownloads`), its ring
/// stopping it. In Settings (`onRemove`) a downloaded voice is removed with a swipe, or in Edit
/// with its row's ⊖ and *Remove*. Either only asks: the voice stays listed (its download goes),
/// so its row keeps `voice.id` and the List is never told a row was deleted (AGENTS.md, "Swipe
/// actions").
struct VoiceChoiceRows: View {
    let descriptor: EngineDescriptor
    /// The engine voice id with the checkmark ("af_heart").
    let current: String?
    let preview: VoicePreviewPlayer
    let speech: SpeechController
    /// Removes a downloaded voice (asking first when it must); nil: this picker removes nothing.
    var onRemove: ((VoiceSelection) -> Void)?
    let onPick: (EngineVoice) -> Void

    @Environment(\.editMode) private var editMode
    /// The voice whose *Remove* shows in Edit (its ⊖ tapped): one at a time, gone with Edit.
    @State private var removeShown: String?
    #if DEBUG
    @Environment(\.voicePageProbe) private var probe
    #endif

    private var localTTS: LocalTTSCoordinator { speech.localTTS }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        let downloads = localTTS.voiceDownloads
        ForEach(descriptor.voices, id: \.id) { voice in
            let selection = VoiceSelection(engine: descriptor.id, voice: voice.id)
            let remove: (() -> Void)? = if let onRemove, downloads.removal(of: selection) != nil {
                { onRemove(selection) }
            } else {
                nil
            }
            VoiceRow(
                name: voice.label,
                download: Self.rowDownload(downloads.status(of: selection)),
                selected: current == voice.id,
                previewing: preview.playingID == voice.id,
                hasPreview: VoicePreviewPlayer.hasPreview(voice),
                accessibilityID: "voiceRow-\(voice.id)",
                editing: isEditing,
                onPick: { if !isEditing { onPick(voice) } },
                onPreview: {
                    if speech.isPlaying { speech.pause() }
                    preview.toggle(voice)
                },
                onStop: { downloads.cancel(selection) },
                onRemove: remove,
                removeShown: Binding(get: { isEditing && remove != nil && removeShown == voice.id },
                                     set: { removeShown = $0 ? voice.id : nil })
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let remove, !isEditing {
                    Button(Verbs.remove, action: remove)
                        .tint(Palette.destructive)
                        .accessibilityIdentifier("voiceRemove-\(voice.id)")
                }
            }
        }
        .onChange(of: isEditing) { if !isEditing { removeShown = nil } }
        #if DEBUG
        .onAppear { if let voice = probe.revealingRemove { removeShown = voice } }
        #endif
    }

    static func rowDownload(_ status: VoiceDownloads.Status) -> VoiceRow.Download {
        switch status {
        case .onDevice(let bytes): .onDevice(size: bytes.map(FileSizes.megabytes))
        case .notDownloaded(let bytes): .notDownloaded(size: FileSizes.megabytes(bytes))
        case .downloading(let fraction, let bytes): .downloading(fraction: fraction, size: FileSizes.megabytes(bytes))
        case .failed: .failed
        }
    }
}
