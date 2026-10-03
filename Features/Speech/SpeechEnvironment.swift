import SwiftUI

private struct SpeechControllerKey: @preconcurrency EnvironmentKey {
    /// Same instance the app injects (composition root). A separate default instance would build
    /// a second SpeechController and LocalTTSCoordinator, warming a second copy of the local
    /// model at launch (double download/compile and memory).
    @MainActor static var defaultValue: SpeechController { AppComposition.speechController }
}

extension EnvironmentValues {
    var speechController: SpeechController {
        get { self[SpeechControllerKey.self] }
        set { self[SpeechControllerKey.self] = newValue }
    }
}
