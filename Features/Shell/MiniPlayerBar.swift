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
        guard rowWidth > 0 else { return 4 }
        return max(4, BottomToolbarLayout.slotWidth(rowWidth: rowWidth) / 2 - playSize / 2)
    }

    var body: some View {
        if let id = speech.activeSessionID {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(speech.nowPlayingTitle ?? "Now playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("miniPlayerTitle")
                    ThinProgressBar(value: progress)
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
                        .foregroundStyle(.primary)
                        .frame(width: Self.playSize, height: Self.playSize)
                        .tapTarget(Self.playSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? "Pause" : "Play")
                .accessibilityIdentifier("miniPlayerPlayPause")
            }
            .padding(.leading, 14)
            .padding(.trailing, Self.trailingPadding(rowWidth: width))
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
            .contextMenu {
                Button("Stop listening", systemImage: "stop.fill") { speech.stop() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("miniPlayer")
        }
    }

    /// Text-length weighted, like the scrubber.
    private var progress: Double {
        let total = (speech.document.joinedText as NSString).length
        guard total > 0 else { return 0 }
        return min(1, Double(speech.spokenUTF16Offset) / Double(total))
    }
}
