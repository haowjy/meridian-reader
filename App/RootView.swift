import SwiftUI
import SwiftData

/// App root: the browser is the whole app (no tab bar); the reader and the library are surfaces
/// over it (`ShellState`). Shows playback's notices (`SpeechController.notice`) as the shell's
/// toast, once each.
struct RootView: View {
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @State private var showsWhatsNew = false
    @State private var whatsNewStore = WhatsNewStore()
    /// Cellular / Low Data Mode confirm before Phonon / Kokoro model downloads.
    @State private var cellularDownload = LargeModelDownloadConsent.shared

    var body: some View {
        BrowseStartView()
            .reportsChromeHome()
            .onChange(of: speech.notice, initial: true) { _, notice in
                guard let notice else { return }
                speech.noticeShown(notice.id)
                shell.showToast(ShellToast(
                    message: notice.message, systemImage: notice.offersRetry ? Icons.warning : Icons.listen,
                    actionTitle: notice.offersRetry ? Verbs.retry : nil,
                    action: notice.offersRetry ? { speech.retry() } : nil))
            }
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
                    set: { if !$0 { cellularDownload.decline() } }
                   )) {
                Button(Verbs.downloadAnyway) { cellularDownload.allow() }
                    .accessibilityIdentifier("cellularDownloadConfirm")
                Button(Verbs.notNow, role: .cancel) { cellularDownload.decline() }
                    .accessibilityIdentifier("cellularDownloadNotNow")
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
/// browser (`-browseTestPages`), the scrubber's frozen bubble (`-scrubBubbleDemo`), and the Voice
/// page in Edit or asking about a removal (`-editVoices`, `-removeVoice`).
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
            .environment(\.voicePageProbe, VoicePageProbe(editing: options.editsVoices, removing: options.removesVoice))
    }
}
#endif

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
