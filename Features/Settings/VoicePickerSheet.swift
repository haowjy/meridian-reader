import SwiftUI

/// *Voice: Heart* in an article's or a book's menu (C138, C138a): the voice it speaks in, from the
/// one voice switcher (`VoiceSelectionList`: engines as sections). Picking another asks first when it has audio, with how
/// much is remade, then remakes it in that voice (`ArticleVoiceChange`).
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
    @State private var preparingID: String?
    @State private var error: String?

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    private var change: ArticleVoiceChange? {
        ArticleVoiceChange(target: target, library: library, speech: speech, preparedAudio: preparedAudio)
    }

    var body: some View {
        NavigationStack {
            List {
                if let change {
                    VoiceSelectionList(
                        speech: speech, current: change.selection, preparingID: preparingID,
                        footer: change.isBook ? String(localized: "Every chapter speaks in this voice.")
                            : String(localized: "All of this article speaks in this voice."),
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
            .alert(pending.map { String(localized: "Change to \(localTTS.voiceName(of: $0))?") } ?? "",
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
        guard selection != change.selection || change.ownSelection == nil, preparingID == nil else { return }
        error = nil
        let cost = change.cost()
        if cost.isEmpty {
            run(selection, change: change)
        } else {
            pendingCost = cost
            pending = selection
        }
    }

    private func run(_ selection: VoiceSelection, change: ArticleVoiceChange) {
        preparingID = selection.isApple ? nil : selection.voice
        Task {
            do {
                try await change.apply(selection)
            } catch {
                self.error = String(localized: "Couldn’t download \(localTTS.voiceName(of: selection)). Check your connection and try again.")
            }
            preparingID = nil
        }
    }

    /// "Remakes 12 MB of prepared audio and clears 3 MB of audio from listening."
    static func costMessage(_ cost: ArticleVoiceChange.Cost) -> String {
        var parts: [String] = []
        if cost.prepared > 0 {
            parts.append(String(localized: "Its \(FileSizes.label(cost.prepared)) of prepared audio is made again in the new voice."))
        }
        if cost.listening > 0 {
            parts.append(String(localized: "Its \(FileSizes.label(cost.listening)) of audio from listening is cleared and made again as it plays."))
        }
        parts.append(String(localized: "Old audio is deleted once replaced, and the two voices never mix."))
        return parts.joined(separator: " ")
    }
}
