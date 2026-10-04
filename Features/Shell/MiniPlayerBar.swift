import SwiftUI

/// Slim now-playing bar above the browser toolbar while an article is loaded for playback and the
/// reader isn't on screen: title, progress, play/pause. Tap it to open the reader.
struct MiniPlayerBar: View {
    @Bindable var speech: SpeechController
    var onOpen: () -> Void
    /// Bar width (= the toolbar row's width): play/pause sits over the ⋯ slot.
    @State private var width: CGFloat = 0

    /// Play/pause button width.
    static let playSize: CGFloat = 40

    /// Trailing padding that centers play/pause on slot 5 of `BottomToolbarLayout`.
    static func trailingPadding(rowWidth: CGFloat) -> CGFloat {
        guard rowWidth > 0 else { return Spacing.xxs }
        return max(Spacing.xxs, BottomToolbarLayout.slotWidth(rowWidth: rowWidth) / 2 - playSize / 2)
    }

    var body: some View {
        if let id = speech.activeSessionID {
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(speech.nowPlayingTitle ?? "Now playing")
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .accessibilityIdentifier("miniPlayerTitle")
                    MiniPlayerProgress(speech: speech)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the reader")
                .accessibilityIdentifier("miniPlayerOpen")
                .accessibilityAction(.default, onOpen)

                let playing = speech.showsPauseIcon(for: id)
                Button {
                    if playing { speech.pause() } else { speech.resume() }
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.ink)
                        .frame(width: Self.playSize, height: Self.playSize)
                        .tapTarget(Self.playSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? "Pause" : "Play")
                .accessibilityIdentifier("miniPlayerPlayPause")
            }
            .padding(.leading, Spacing.m)
            .padding(.trailing, Self.trailingPadding(rowWidth: width))
            .padding(.vertical, Spacing.xxs)
            .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
            .contextMenu {
                Button("Stop listening", systemImage: "stop.fill") { speech.stop() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("miniPlayer")
        }
    }
}

/// The bar's fill, text-length weighted like the scrubber. Its own view: it reads the live offset,
/// which moves several times a second while playing, so only the fill redraws.
private struct MiniPlayerProgress: View {
    let speech: SpeechController

    var body: some View {
        ThinProgressBar(value: speech.document.progress(atUTF16Offset: speech.spokenUTF16Offset))
    }
}
