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
    private let extractor: any ArticleExtracting = ReadabilityArticleExtractor()
    private let container: ModelContainer
    /// Composition root output (engine registry → SpeechController). See `AppComposition`.
    @State private var speechController = AppComposition.speechController
    @State private var shell = AppComposition.shell
    @State private var library: LibraryStore
    @State private var downloads: DownloadCenter
    /// How pages read (Settings › Reading, the Aa panel): one store for both editors.
    @State private var readingAppearance = ReadingAppearance(defaults: .standard)
    @State private var developer = DeveloperSettings()

    init() {
        do {
            container = try LibraryStoreConfiguration.makeContainer()
        } catch {
            fatalError("Couldn't open the library stores: \(error)")
        }
        let library = AppComposition.makeLibrary(context: container.mainContext)
        _library = State(initialValue: library)
        _downloads = State(initialValue: AppComposition.makeDownloads(library: library))
        // Foreground/background gate for Core ML synthesis (no model calls in the background).
        AppRunState.shared.observeApplication()
        AppComposition.runLaunchMaintenance(library: library)
        AppComposition.attachLibrary(library)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.articleExtractor, extractor)
                .environment(\.speechController, speechController)
                .environment(shell)
                .environment(library)
                .environment(downloads)
                .environment(\.readingAppearance, readingAppearance)
                .environment(\.developerSettings, developer)
                .task {
                    await AppLaunch.run(library: library, speech: speechController, shell: shell, downloads: downloads)
                }
        }
        .modelContainer(container)
    }
}
