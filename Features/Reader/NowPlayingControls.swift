import SwiftUI

/// Now Playing's bottom band (in the reading theme's colours): the status notes (buffering, the
/// Apple-fallback and language notes, the developer Debug chip) and the transport row (🔖 and ⋯ in
/// the Reader's slots). The scrub row is now in the player card above the band.
struct NowPlayingControls: View {
    @Bindable var speech: SpeechController
    @Environment(ShellState.self) private var shell
    @Environment(DeveloperSettings.self) private var developer
    let detectedLanguage: String?
    /// 🔖, transport slot 1.
    let save: AnyView
    /// ⋯, transport slot 5.
    let more: AnyView

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }
    private var isFinished: Bool { speech.nowPlaying?.isFinished == true }

    var body: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            notes
            ListenTransportView(leading: save, trailing: more, speech: speech)
        }
    }

    /// Buffering / Apple-fallback / language notes and the developer Debug chip.
    @ViewBuilder
    private var notes: some View {
        let languageNote = speech.languageResolution(detected: detectedLanguage).note
        if developer.showsListenDebugUI, developer.showBakeDebugOverlay {
            BakeDebugOverlay(speech: speech) {
                shell.present(.listenDebug)
            }
        }
        if developer.showsListenDebugUI {
            HStack {
                Spacer(minLength: 0)
                Button {
                    developer.showBakeDebugOverlay.toggle()
                } label: {
                    Text(developer.showBakeDebugOverlay ? "Debug ▾" : "Debug")
                        .typeStyle(.caption, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule().fill(developer.showBakeDebugOverlay ? palette.highlight : palette.card)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listenBakeDebugChip")
                .accessibilityLabel(developer.showBakeDebugOverlay ? "Hide bake debug" : "Show bake debug")
            }
            .padding(.horizontal, Spacing.xs)
        }
        if isFinished {
            // The title card says "● Finished"; no note under it.
            EmptyView()
        } else if speech.isBufferingNext {
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing next…")
                    .accessibilityIdentifier("listenBufferingLabel")
                Spacer(minLength: 0)
            }
            .typeStyle(.caption)
            .foregroundStyle(palette.secondaryInk)
            .padding(.horizontal, Spacing.xs)
            .accessibilityIdentifier("listenBuffering")
        } else if let renderNote = speech.renderNote {
            note(renderNote, id: "listenRenderNote")
        } else if let languageNote {
            note(languageNote, id: "listenLanguageNote")
        }
    }

    private func note(_ text: String, id: String) -> some View {
        Text(text)
            .typeStyle(.caption)
            .foregroundStyle(palette.secondaryInk)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .accessibilityIdentifier(id)
    }

}

/// A playhead position: paragraph + document UTF-16 offset inside it.
struct PlayheadSpot: Equatable {
    var paragraph: Int
    var utf16Offset: Int
}

/// Hands `content` the live playhead. The live offset moves several times a second while playing;
/// reading it here, in its own body, keeps those redraws to `content` instead of the view that
/// builds it.
struct PlayheadReader<Content: View>: View {
    let speech: SpeechController
    @ViewBuilder let content: (PlayheadSpot) -> Content

    var body: some View {
        content(PlayheadSpot(paragraph: speech.currentParagraphIndex, utf16Offset: speech.spokenUTF16Offset))
    }
}

/// A one-shot "scroll this paragraph into view" (token changes per request).
struct ReaderScrollRequest: Equatable {
    let index: Int
    let token: Int
}
