import SwiftUI

private struct SpeechControllerKey: @preconcurrency EnvironmentKey {
    /// Same instance the app injects (composition root). A separate default instance used to
    /// build a second SpeechController → second LocalTTSCoordinator, which warmed a second copy
    /// of the local model at launch (double download/compile + memory).
    @MainActor static var defaultValue: SpeechController { AppComposition.speechController }
}

extension EnvironmentValues {
    var speechController: SpeechController {
        get { self[SpeechControllerKey.self] }
        set { self[SpeechControllerKey.self] = newValue }
    }
}
