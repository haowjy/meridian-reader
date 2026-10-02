import SwiftUI
import SwiftData

@main
struct ReaderApp: App {
    private let extractor: any ArticleExtracting = ReadabilityArticleExtractor()
    private let container: ModelContainer
    /// Composition root output (engine registry → SpeechController). See `AppComposition`.
    @State private var speechController = AppComposition.speechController
    @State private var shell = ShellState()

    init() {
        do {
            container = try ModelContainer(for: SavedArticle.self, RecentVisit.self)
        } catch {
            fatalError("Couldn't open the saved-article store: \(error)")
        }
        BackgroundAudioBakeScheduler.shared.register()
        // Foreground/background gate for Core ML synthesis (no model calls in the background).
        AppRunState.shared.observeApplication()
        AppComposition.runLaunchMaintenance()
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
