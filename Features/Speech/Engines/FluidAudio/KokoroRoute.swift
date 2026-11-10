import Foundation

/// Persisted knobs of Kokoro's ONNX CPU route (UserDefaults; injectable for tests).
struct KokoroRouteSettings {
    static let cpuThreadsKey = "reader.tts.kokoro.cpuThreads"
    static let onnxCrashCountKey = "reader.tts.kokoro.onnxCrashCount"
    static let storedKeys = [cpuThreadsKey, onnxCrashCountKey]
    /// The ONNX route's tag in crash markers (`KokoroCPUHost.routeTag`). A Kokoro marker with
    /// another tag ("coreml") or none was written by an older build's Core ML route.
    static let onnxRouteTag = "onnx"
    /// The most ONNX intra-op threads a call may use (the route's cap) by default: every core but one (the UI, audio and the render
    /// queue's own work keep that one), at least 3, at most 6. 5 on an iPhone 17 Pro (2
    /// performance + 4 efficiency cores). ORT splits a matrix multiply into one piece per thread,
    /// so the piece on an efficiency core finishes last and the rest wait for it: at 3 threads the
    /// phone rendered ≈2.6× real time, below a Mac's 3 performance cores (≈3.5×) though its
    /// performance cores are faster. More, smaller pieces shorten that wait. Debug-overridable
    /// (`cpuThreads`); the CPU route benchmark measures 2–6.
    static var defaultThreads: Int { foregroundThreads(cores: ProcessInfo.processInfo.activeProcessorCount) }
    static let minimumForegroundThreads = 3
    static let threadRange = 1...6

    static func foregroundThreads(cores: Int) -> Int {
        min(max(cores - 1, minimumForegroundThreads), threadRange.upperBound)
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The route's thread cap (debug override, crash step-down; 0/unset = default). The render
    /// policy gives a call fewer in the background (`SingleCallPolicy.backgroundThreads`).
    var cpuThreads: Int {
        get {
            let v = defaults.integer(forKey: Self.cpuThreadsKey)
            return Self.threadRange.contains(v) ? v : Self.defaultThreads
        }
        nonmutating set {
            defaults.set(Self.threadRange.contains(newValue) ? newValue : 0, forKey: Self.cpuThreadsKey)
        }
    }

    var onnxCrashCount: Int {
        get { defaults.integer(forKey: Self.onnxCrashCountKey) }
        nonmutating set { defaults.set(max(0, newValue), forKey: Self.onnxCrashCountKey) }
    }
}

/// Auto-recover after a crash inside a Kokoro call — a pure state machine (unit-tested) plus
/// `recover`, the policy `FluidAudioProvider` answers the coordinator's crash hook with.
///
/// Kokoro never falls to another engine or voice on its own.
/// - A crash an older build's Core ML route left (tag "coreml" or none) → resume on ONNX, same
///   voice, no notice, not counted (the same voice and cached audio, so nothing heard changes).
/// - ONNX route crash #1 → the same, silently, on one thread fewer (a fresh session).
/// - ONNX route crash #2 (without a healthy stretch in between) → still Kokoro, one thread fewer
///   again; prepared audio and new rendering pause, while playback goes on through audio already
///   rendered. Only where playback reaches audio not rendered yet does it pause, with a plain
///   notice and Retry.
/// A healthy stretch (`healthyRendersToReset` ONNX calls in one session) or Retry resets the count.
enum KokoroCrashRecovery {
    static let onnxCrashLimit = 2
    static let healthyRendersToReset = 40
    /// Fewest ONNX threads a crash retry steps down to.
    static let minimumRetryThreads = 2

    enum Outcome: Equatable {
        /// Keep Kokoro selected on the ONNX route and resume where the crash happened, silently.
        case resumeOnONNX
        /// The ONNX route crashed `onnxCrashLimit` times: stay on Kokoro, pause until Retry.
        case pauseForRetry
    }

    /// `onONNX`: the marker carries the ONNX route's tag; false for an older build's Core ML route.
    static func onCrash(onONNX: Bool, onnxCrashCount: inout Int) -> Outcome {
        guard onONNX else { return .resumeOnONNX }
        onnxCrashCount += 1
        if onnxCrashCount >= onnxCrashLimit {
            onnxCrashCount = 0 // Retry starts a fresh count
            return .pauseForRetry
        }
        return .resumeOnONNX
    }

    /// Threads after an ONNX crash: one fewer than before, at least `minimumRetryThreads`
    /// (a crash under memory pressure is less likely with fewer per-thread buffers).
    static func retryThreads(after current: Int) -> Int {
        max(minimumRetryThreads, current - 1)
    }

    /// The previous process died inside a Kokoro call: stay on Kokoro and its voice.
    /// Updates the route settings (crash count, threads) and says where to resume.
    /// `playing` is the session's last resume point.
    static func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?,
                        settings: KokoroRouteSettings) -> CrashRecovery {
        var onnxCount = settings.onnxCrashCount
        let onONNX = crash.route == KokoroRouteSettings.onnxRouteTag
        let outcome = onCrash(onONNX: onONNX, onnxCrashCount: &onnxCount)
        settings.onnxCrashCount = onnxCount
        if onONNX { settings.cpuThreads = retryThreads(after: settings.cpuThreads) }
        let target = ListenResumeTarget.forCrash(article: crash.articleKey, paragraph: crash.paragraph,
                                                 crashAt: crash.at, playing: playing)
        let recovery: CrashRecovery
        switch outcome {
        case .resumeOnONNX:
            recovery = .stay(resume: target)
        case .pauseForRetry:
            // Playback carries on through rendered audio; the notice shows when it runs out.
            recovery = .pauseForRetry(resume: target)
        }
        let resume = recovery.resume
        ListenTimingLog.log("kokoro_auto_recover", [
            "route": crash.route ?? "legacy", "outcome": String(describing: outcome),
            "onnx_crashes": onnxCount, "threads": settings.cpuThreads,
            "resume_key": resume?.articleKey.prefix(8) ?? "",
            "resume_p": resume?.paragraph ?? -1, "auto_play": resume?.autoPlay ?? false,
        ])
        return recovery
    }
}
