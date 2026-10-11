import SwiftUI
import SwiftData

@main
struct ReaderApp: App {
    private let extractor: any ArticleExtracting = ReadabilityArticleExtractor()
    private let container: ModelContainer
    /// Composition root output (engine registry → SpeechController). See `AppComposition`.
    @State private var speechController = AppComposition.speechController
    @State private var shell = AppComposition.shell
    @State private var library: LibraryStore
    @State private var downloads: DownloadCenter

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
                .task {
                    await AppLaunch.run(library: library, speech: speechController, shell: shell, downloads: downloads)
                }
        }
        .modelContainer(container)
    }
}
