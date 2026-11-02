import SwiftUI

/// Now Playing's status notes (preparing the voice or the next paragraphs, the developer Debug
/// chip) for the integrated bottom band. The transport row is now built directly by the
/// band, not here.
struct NowPlayingControls: View {
    @Bindable var speech: SpeechController
    @Environment(ShellState.self) private var shell
    @Environment(DeveloperSettings.self) private var developer

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }
    private var isFinished: Bool { speech.nowPlaying?.isFinished == true }

    var body: some View {
        notes
    }

    static let bufferingLabel = String(localized: "Preparing next…")
    static let preparingVoiceLabel = String(localized: "Preparing the voice")

    /// The status line when there is one: preparing the voice or the next paragraphs; none once
    /// the page has finished. The compact card shows it under the title.
    static func note(of speech: SpeechController) -> String? {
        guard speech.nowPlaying?.isFinished != true else { return nil }
        if speech.isPreparingVoice { return preparingVoiceLabel }
        if speech.isBufferingNext { return bufferingLabel }
        return nil
    }

    /// The buffering note and the developer Debug chip.
    @ViewBuilder
    private var notes: some View {
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
            EmptyView()
        } else if speech.isBufferingNext {
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text(speech.isPreparingVoice ? Self.preparingVoiceLabel : Self.bufferingLabel)
                    .accessibilityIdentifier("listenBufferingLabel")
                Spacer(minLength: 0)
            }
            .typeStyle(.caption)
            .foregroundStyle(palette.secondaryInk)
            .padding(.horizontal, Spacing.xs)
            .accessibilityIdentifier("listenBuffering")
        }
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
