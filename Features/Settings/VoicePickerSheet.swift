import SwiftUI

/// *Voice: Heart* in an article's or a book's menu (C138, C138a): the voice it speaks in, from the
/// one voice switcher (`VoiceSelectionList`: engines as sections). Picking another asks first when it has audio, with how
/// much is made again, then downloads the voice if it isn't on the device (its row shows the
/// download; the ✓ stays until it is there) and changes it to that voice (`ArticleVoiceChange`).
/// Voices are removed in Settings › Voice, not here.
///
/// ```
///                  Voice                    Done
/// The Forgotten
///  Heart  ✓                               ▶
///  Bella                                  ▶
///  …
/// Every chapter speaks in this voice.
/// ```
struct VoicePickerSheet: View {
    let target: VoiceTarget

    @Environment(LibraryStore.self) private var library
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @State private var preview = VoicePreviewPlayer()
    @State private var pending: VoiceSelection?
    @State private var pendingCost = ArticleVoiceChange.Cost()
    @State private var error: String?


    private var change: ArticleVoiceChange? {
        ArticleVoiceChange(target: target, library: library, speech: speech, preparedAudio: preparedAudio)
    }

    var body: some View {
        NavigationStack {
            List {
                if let change {
                    VoiceSelectionList(
                        speech: speech, current: change.selection,
                        footer: change.isBook ? String(localized: "Every chapter uses this voice.")
                            : String(localized: "The whole article uses this voice."),
                        error: error, preview: preview
                    ) { pick($0, change: change) }
                }
            }
            .cardListStyle()
            .navigationTitle(Verbs.voice)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetBarButton(Verbs.done, placement: .confirmationAction, identifier: "voicePickerDone") {
                    shell.sheet = nil
                }
            }
            .alert(String(localized: "Change the Voice?"),
                   isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button(Verbs.changeVoice) {
                    if let voice = pending, let change { run(voice, change: change) }
                    pending = nil
                }
                .accessibilityIdentifier("voiceChangeConfirm")
                Button(Verbs.cancel, role: .cancel) { pending = nil }
            } message: {
                Text(Self.costMessage(pendingCost))
            }
        }
        .onDisappear { preview.stop() }
    }

    private func pick(_ selection: VoiceSelection, change: ArticleVoiceChange) {
        error = nil
        if selection == change.selection, change.ownSelection != nil {
            // Its own voice, removed since: download it again; nothing else changes.
            Task { _ = await speech.localTTS.voiceDownloads.download(selection) }
            return
        }
        let cost = change.cost()
        if cost.isEmpty {
            run(selection, change: change)
        } else {
            pendingCost = cost
            pending = selection
        }
    }

    /// Download first (the newest pick wins), then change it; a failed download says so on its row.
    private func run(_ selection: VoiceSelection, change: ArticleVoiceChange) {
        Task {
            guard await speech.localTTS.voiceDownloads.pick(selection, for: target.id) else { return }
            do {
                try change.apply(selection)
            } catch {
                self.error = String(localized: "Couldn’t change the voice. Nothing was changed.")
            }
        }
    }

    /// "Its 12 MB of prepared audio is made again in the new voice. … kept for 7 days …"
    static func costMessage(_ cost: ArticleVoiceChange.Cost) -> String {
        var parts: [String] = []
        if cost.prepared > 0 {
            parts.append(String(localized: "Its \(FileSizes.label(cost.prepared)) of prepared audio is made again in the new voice."))
        }
        if cost.listening > 0 {
            parts.append(String(localized: "Its \(FileSizes.label(cost.listening)) of audio from listening is made again as it plays."))
        }
        parts.append(String(localized: "Audio in the current voice is kept for 7 days, so changing back plays it at once. The two voices never mix."))
        return parts.joined(separator: " ")
    }
}
