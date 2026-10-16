import SwiftUI

/// Developer switches that last until the app quits (Settings › Developer). Stored ones live with
/// what they switch (`SpeechController.listenDebugEnabled`, `DeveloperOptions`).
@Observable
final class DeveloperSettings {
    /// The browser's Reader extracts with `FakeArticleExtractor(mode: .failure)`.
    var fakeExtractionFailure = false
}

extension EnvironmentValues {
    /// The app's developer switches (`AppComposition`).
    @Entry var developerSettings = DeveloperSettings()
}
