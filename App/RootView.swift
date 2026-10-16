import SwiftUI
import SwiftData

/// App root: the browser is the whole app (no tab bar); the reader and the library are surfaces
/// over it (`ShellState`). Shows the local engine's crash notice on top.
struct RootView: View {
    @Environment(\.speechController) private var speech
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrowseStartView()
            .overlay(alignment: .top) {
                if let notice = speech.localTTS.engineCrashNotice {
                    EngineNoticeBanner(text: notice) { speech.localTTS.dismissCrashNotice() }
                        .padding(.horizontal, Spacing.s)
                        .transition(.slideAndFade(from: .top, reduceMotion: reduceMotion))
                }
            }
            .animation(Motion.snappy, value: speech.localTTS.engineCrashNotice)
            .environment(\.playingBarsMove, Self.playingBarsMove)
    }

    #if DEBUG
    /// UI tests (`-uiTesting`): still playing bars, so the app can go idle between test steps.
    private static let playingBarsMove = !LaunchOptions.current.uiTesting
    #else
    private static let playingBarsMove = true
    #endif
}

/// One-line, dismissible notice (e.g. "Kokoro stopped unexpectedly; resumed on the stable route.").
/// The ✕ fills a 44 pt square at the trailing end, so the banner is at least that tall.
struct EngineNoticeBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: Icons.warning)
                .foregroundStyle(.orange)
            Text(text)
                .typeStyle(.caption)
                .lineLimit(text.count <= 64 ? 1 : 3)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.xs)
            Button(action: onDismiss) {
                Image(systemName: Icons.close)
                    .typeStyle(.caption, weight: .semibold)
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("engineNoticeDismiss")
        }
        .padding(.leading, Spacing.s)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("engineNotice")
    }
}

#Preview {
    let container = try! LibraryStoreConfiguration.makeInMemoryContainer()
    let library = AppComposition.makeLibrary(context: container.mainContext)
    RootView()
        .environment(ShellState())
        .environment(library)
        .environment(AppComposition.makeDownloads(library: library))
        .modelContainer(container)
}
