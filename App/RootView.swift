import SwiftUI
import SwiftData

/// App root: the browser is the whole app (no tab bar); the reader and the library are surfaces
/// over it (`ShellState`). Shows the local engine's crash notice on top.
struct RootView: View {
    @Environment(\.speechController) private var speech
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsWhatsNew = false
    @State private var whatsNewStore = WhatsNewStore()
    /// Cellular / Low Data Mode confirm before Phonon / Kokoro model downloads.
    @State private var cellularDownload = LargeModelDownloadConsent.shared

    var body: some View {
        BrowseStartView()
            .reportsChromeHome()
            .overlay(alignment: .top) {
                if let notice = speech.localTTS.engineCrashNotice {
                    EngineNoticeBanner(text: notice,
                                       onRetry: speech.localTTS.isPausedForRetry ? { speech.localTTS.retryAfterEngineStop(); speech.userPerform(.resume) } : nil) {
                        speech.localTTS.dismissCrashNotice()
                    }
                        .padding(.horizontal, Spacing.s)
                        .transition(.slideAndFade(from: .top, reduceMotion: reduceMotion))
                }
            }
            .animation(Motion.snappy, value: speech.localTTS.engineCrashNotice)
            // The app's colour for system controls (`Palette.accent` reads the theme, so this
            // follows a change in Settings), and its appearance on every window.
            .tint(Palette.accent)
            .onAppear {
                AppAppearance.shared.applyToWindows()
                if whatsNewStore.shouldShow && Self.whatsNewAllowed { showsWhatsNew = true }
            }
            .sheet(isPresented: $showsWhatsNew) {
                WhatsNewSheet(notes: whatsNewStore.notes) {
                    whatsNewStore.markSeen()
                    showsWhatsNew = false
                }
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
            }
            .alert(cellularDownload.prompt?.title ?? "",
                   isPresented: Binding(
                    get: { cellularDownload.prompt != nil },
                    set: { if !$0 { cellularDownload.deferUntilWiFi() } }
                   )) {
                Button(Verbs.downloadAnyway) { cellularDownload.allow() }
                    .accessibilityIdentifier("cellularDownloadConfirm")
                Button(Verbs.waitForWiFi, role: .cancel) { cellularDownload.deferUntilWiFi() }
                    .accessibilityIdentifier("cellularDownloadWait")
            } message: {
                if let prompt = cellularDownload.prompt {
                    Text(prompt.message)
                }
            }
            #if DEBUG
            .modifier(LaunchTestHooks(options: .current))
            #endif
    }

    private static var whatsNewAllowed: Bool {
        #if DEBUG
        let options = LaunchOptions.current
        return !options.uiTesting || options.showsWhatsNew
        #else
        return true
        #endif
    }
}

#if DEBUG
/// What the launch arguments ask of the views for probes and screenshot runs: still playing
/// bars (`-uiTesting`, so the app can go idle between probe steps), the ⋯ panel's focus marker and
/// no Google suggestions, the ⋯ morph slowed (`-slowMenuAnimation`), the offline test pages in the
/// browser (`-browseTestPages`), and the scrubber's frozen bubble (`-scrubBubbleDemo`).
private struct LaunchTestHooks: ViewModifier {
    let options: LaunchOptions

    func body(content: Content) -> some View {
        content
            .environment(\.playingBarsMove, !options.uiTesting)
            .environment(\.morphMenuMarksFocus, options.uiTesting)
            .environment(\.morphMenuAnimation, options.slowMenuAnimation ? .easeInOut(duration: 3) : Motion.standard)
            .environment(\.webViewSchemeHandlers, options.servesTestPages ? TestPageSchemeHandler.handlers : [:])
            .environment(\.searchSuggestionProvider, options.suggestionProvider)
            .environment(\.showsScrubBubbleDemo, options.scrubBubbleDemo)
    }
}
#endif

/// One-line, dismissible notice (e.g. "Kokoro stopped unexpectedly; resumed on the stable route.").
/// The ✕ fills a 44 pt square at the trailing end, so the banner is at least that tall.
struct EngineNoticeBanner: View {
    let text: String
    /// Shown as a Retry button when the engine is paused for retry (C129).
    var onRetry: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: Icons.warning)
                .foregroundStyle(Palette.caution)
            Text(text)
                .typeStyle(.caption)
                .lineLimit(text.count <= 64 ? 1 : 3)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.xs)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .typeStyle(.caption, weight: .semibold)
                    .frame(minHeight: BottomChrome.minTapTarget)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                    .accessibilityIdentifier("engineNoticeRetry")
            }
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
    let follow = AppComposition.makeFollow(library: library)
    RootView()
        .environment(ShellState())
        .environment(library)
        .environment(follow)
        .environment(AppComposition.makePreparedAudio(library: library, follow: follow))
        .modelContainer(container)
}
