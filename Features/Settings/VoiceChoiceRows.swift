import SwiftUI

/// An on-device engine's voices as `VoiceRow`s, each with its sample and its download: the one
/// list Settings › Voice and an article's or a book's voice picker (C138) both show. A voice that
/// isn't on the device shows its size and ⤓; picking it downloads it (`VoiceDownloads`), its ring
/// stopping it. In Settings (`onRemove`) a downloaded voice is removed with a swipe, or with the
/// List's delete control in Edit.
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
    /// Bumped for a voice each time the List's delete control fires on its row. The voice stays
    /// listed (only its download goes), but the List may already have taken the row out, as it
    /// does for a delete; a new identity has the data agree, so UIKit never finds a row it deleted
    /// still there (AGENTS.md, "Swipe actions").
    @State private var deletions: [String: Int] = [:]

    private var localTTS: LocalTTSCoordinator { speech.localTTS }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    private struct RowID: Hashable {
        let voice: EngineVoice
        let deletions: Int
    }

    var body: some View {
        let downloads = localTTS.voiceDownloads
        ForEach(descriptor.voices.map { RowID(voice: $0, deletions: deletions[$0.id] ?? 0) }, id: \.self) { row in
            let voice = row.voice
            let selection = VoiceSelection(engine: descriptor.id, voice: voice.id)
            let removable = onRemove != nil && downloads.removal(of: selection) != nil
            VoiceRow(
                name: voice.label,
                download: Self.rowDownload(downloads.status(of: selection)),
                selected: current == voice.id,
                previewing: preview.playingID == voice.id,
                hasPreview: VoicePreviewPlayer.hasPreview(voice),
                accessibilityID: "voiceRow-\(voice.id)",
                onPick: { if !isEditing { onPick(voice) } },
                onPreview: {
                    if speech.isPlaying { speech.pause() }
                    preview.toggle(voice)
                },
                onStop: { downloads.cancel(selection) }
            )
            .deleteDisabled(!removable)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if removable, let onRemove {
                    Button(Verbs.remove) { onRemove(selection) }
                        .tint(Palette.destructive)
                        .accessibilityIdentifier("voiceRemove-\(voice.id)")
                }
            }
        }
        .onDelete(perform: onRemove.map { onRemove in
            { offsets in
                for index in offsets where descriptor.voices.indices.contains(index) {
                    let voice = descriptor.voices[index]
                    deletions[voice.id, default: 0] += 1
                    onRemove(VoiceSelection(engine: descriptor.id, voice: voice.id))
                }
            }
        })
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
