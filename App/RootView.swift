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
                        .padding(.horizontal, 12)
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
struct EngineNoticeBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .lineLimit(text.count <= 64 ? 1 : 3)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("engineNoticeDismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("engineNotice")
    }
}

#Preview {
    RootView()
        .environment(ShellState())
        .modelContainer(for: [SavedArticle.self, RecentVisit.self], inMemory: true)
}
