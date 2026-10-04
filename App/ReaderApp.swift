import SwiftUI
import SwiftData

@main
struct ReaderApp: App {
    private let extractor: any ArticleExtracting = ReadabilityArticleExtractor()
    private let container: ModelContainer
    /// Composition root output (engine registry → SpeechController). See `AppComposition`.
    @State private var speechController = AppComposition.speechController
    @State private var shell = AppComposition.shell

    init() {
        do {
            container = try LibraryStoreConfiguration.makeContainer()
        } catch {
            fatalError("Couldn't open the library stores: \(error)")
        }
        // Foreground/background gate for Core ML synthesis (no model calls in the background).
        AppRunState.shared.observeApplication()
        AppComposition.runLaunchMaintenance()
        AppComposition.attachLibrary(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.articleExtractor, extractor)
                .environment(\.speechController, speechController)
                .environment(shell)
                .task {
                    await AppLaunch.run(context: container.mainContext, speech: speechController, shell: shell)
                }
        }
        .modelContainer(container)
    }
}
