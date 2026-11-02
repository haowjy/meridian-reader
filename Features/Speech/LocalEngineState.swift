import Foundation

/// Lifecycle of the on-device engine. `LocalSynthService` holds exactly one value and changes it
/// only in `setState(_:)`; the coordinator then tells the render queue.
enum LocalEngineState: Equatable {
    /// No engine is loaded or loading.
    case off
    /// Loading the engine (model download, compile, warm-up). `progress` is the download fraction
    /// when the host reports one. `task` is the one load in flight; cancelling it abandons the load.
    case warming(SpeechEngineID, progress: Double?, task: Task<Void, Never>)
    /// The engine's host is loaded: listening and bake-ahead use it.
    case ready(SpeechEngineID)
    /// The engine could not load. `message` is shown in Settings; the next play tries again.
    case failed(SpeechEngineID, message: String)

    /// The on-device engine Listen uses or is about to use (cache keys, chunk sizing, language).
    var activeEngineID: SpeechEngineID? {
        switch self {
        case .warming(let id, _, _), .ready(let id): return id
        case .off, .failed: return nil
        }
    }

    var readyEngineID: SpeechEngineID? {
        if case .ready(let id) = self { return id }
        return nil
    }

    var warmingEngineID: SpeechEngineID? {
        if case .warming(let id, _, _) = self { return id }
        return nil
    }

    /// Download fraction of the engine being loaded (nil: not loading, or no download reported).
    var warmingProgress: Double? {
        if case .warming(_, let progress, _) = self { return progress }
        return nil
    }
}
