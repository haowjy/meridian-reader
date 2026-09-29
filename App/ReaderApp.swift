import SwiftUI
import SwiftData

@main
struct ReaderApp: App {
    private let extractor: any ArticleExtracting = ReadabilityArticleExtractor()
    /// Composition root output (engine registry → SpeechController). See `AppComposition`.
    @State private var speechController = AppComposition.speechController

    init() {
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
                .onAppear {
                    BackgroundAudioBakeScheduler.shared.coordinator = speechController.localTTS
                    EngineLatencyProbe.runIfRequested(coordinator: speechController.localTTS)
                }
        }
        .modelContainer(for: [SavedArticle.self, RecentVisit.self])
    }
}
