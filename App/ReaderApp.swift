import SwiftUI
import SwiftData

/// The process's entry. A Debug build hosting the unit tests (XCTest runs inside this process)
/// is only their host: it builds no library or speech stack, runs no launch work and loads no
/// engine, so the tests share nothing with a live app and the Mac's memory isn't spent on a model.
@main
enum AppMain {
    static func main() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            UnitTestHostApp.main()
            return
        }
        // Before the composition reads any of them.
        if LaunchOptions.current.resetsLibrary { LaunchHooks.resetStoredSettings(engines: AppComposition.engineRegistry) }
        BookImportActions.importsTestBook = LaunchOptions.current.importsTestEPUB
        #endif
        ReaderApp.main()
    }
}

#if DEBUG
/// One empty window: tests that host a web view attach it to the app's window scene.
private struct UnitTestHostApp: App {
    var body: some Scene { WindowGroup { EmptyView() } }
}
#endif

struct ReaderApp: App {
    private let container: ModelContainer
    /// Composition root output (engine registry → SpeechController). See `AppComposition`.
    @State private var speechController = AppComposition.speechController
    @State private var shell = AppComposition.shell
    @State private var library: LibraryStore
    @State private var follow: FollowCenter
    @State private var downloads: DownloadCenter
    /// Block Ads: every web view's rule lists, and Settings › Browsing's switch.
    @State private var contentBlocker: ContentBlocker
    /// How pages read (Settings › Reading, the Aa panel): one store for both editors.
    @State private var readingAppearance = ReadingAppearance(defaults: .standard)
    @State private var developer = AppComposition.developer

    init() {
        // First: a web view made before it would load unblocked.
        _contentBlocker = State(initialValue: AppComposition.makeContentBlocker())
        do {
            container = try LibraryStoreConfiguration.makeContainer()
        } catch {
            fatalError("Couldn't open the library stores: \(error)")
        }
        let library = AppComposition.makeLibrary(context: container.mainContext)
        _library = State(initialValue: library)
        let follow = AppComposition.makeFollow(library: library)
        _follow = State(initialValue: follow)
        _downloads = State(initialValue: AppComposition.makeDownloads(library: library, follow: follow))
        // Foreground/background gate for Core ML synthesis (no model calls in the background).
        AppRunState.shared.observeApplication()
        AppComposition.runLaunchMaintenance(library: library)
        AppComposition.attachLibrary(library)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.articleExtractor, AppComposition.extractor)
                .environment(\.speechController, speechController)
                .environment(shell)
                .environment(library)
                .environment(downloads)
                .environment(follow)
                .environment(contentBlocker)
                .environment(\.readingAppearance, readingAppearance)
                .environment(developer)
                .task {
                    await AppLaunch.run(library: library, speech: speechController, shell: shell, downloads: downloads,
                                        follow: follow)
                }
        }
        .modelContainer(container)
    }
}
