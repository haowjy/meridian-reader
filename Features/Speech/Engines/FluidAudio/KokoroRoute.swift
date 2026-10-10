import Foundation

/// How Kokoro renders. Both routes use the same voice packs, phonemes and article cache key
/// ("kokoro.<voice>"), so audio rendered on either route stays valid on the other.
///
/// - `onnxCPU` (default): ONNX Runtime on the CPU execution provider
///   (`KokoroCPUHost`). No Core ML / Espresso / BNNS anywhere in the call, so it neither hits the
///   iOS 26.4+ libBNNS SIGSEGV nor is it forbidden in the background (CPU work is allowed while
///   audio plays).
/// - `coreMLGPU` (debug opt-in): FluidAudio's 7-stage Core ML chain (`KokoroHost`,
///   gpuAneVocoder on iOS 26.4+). ~4× faster but crashes in libBNNS on device and can't
///   run in the background (no GPU there).
enum KokoroRoute: String, Sendable, Equatable {
    case onnxCPU = "onnx"
    case coreMLGPU = "coreml"

    /// Can this route start a model call while the app is in the background?
    var rendersInBackground: Bool { self == .onnxCPU }

    var label: String {
        switch self {
        case .onnxCPU: return "ONNX CPU"
        case .coreMLGPU: return "Core ML GPU"
        }
    }
}

/// Persisted Kokoro route knobs (UserDefaults; injectable for tests).
struct KokoroRouteSettings {
    static let fastGPURouteKey = "reader.tts.kokoro.fastGPURoute"
    static let cpuThreadsKey = "reader.tts.kokoro.cpuThreads"
    static let onnxCrashCountKey = "reader.tts.kokoro.onnxCrashCount"
    /// Default ONNX intra-op threads. 3 of the A19 Pro's 2P+4E cores: leaves a core for the UI and
    /// audio; ORT with 3 threads ran ≈4–5× real time on the M3 Mac. Debug-overridable.
    static let defaultThreads = 3
    static let threadRange = 1...6

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Debug toggle "Kokoro fast GPU route (may crash on iOS 26.4+)". Off by default.
    var fastGPURouteEnabled: Bool {
        get { defaults.bool(forKey: Self.fastGPURouteKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.fastGPURouteKey) }
    }

    /// ONNX threads (debug override; 0/unset = default).
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

    /// The route new Kokoro hosts use.
    var route: KokoroRoute { fastGPURouteEnabled ? .coreMLGPU : .onnxCPU }
}

/// Auto-recover after a crash inside a Kokoro call — a pure state machine (unit-tested) plus
/// `recover`, the policy `FluidAudioProvider` answers the coordinator's crash hook with.
///
/// - Core ML route crash (or a pre-route marker from an older build) → stay on Kokoro, turn the
///   fast GPU route off, resume the article on the ONNX route.
/// - ONNX route crash #1 → stay on Kokoro/ONNX, resume.
/// - ONNX route crash #2 (without a healthy stretch in between) → Apple, with a clear notice.
/// A healthy stretch (`healthyRendersToReset` ONNX calls in one session) or picking Kokoro again
/// in Settings resets the ONNX count.
enum KokoroCrashRecovery {
    static let onnxCrashLimit = 2
    static let healthyRendersToReset = 40

    enum Outcome: Equatable {
        /// Keep Kokoro selected on the ONNX route and resume where the crash happened.
        case resumeOnONNX(disableFastRoute: Bool)
        /// The ONNX route crashed `onnxCrashLimit` times: switch to Apple.
        case fallBackToApple
    }

    static let resumedNotice = "Kokoro stopped unexpectedly; resumed on the stable route."
    static let appleNotice = "Kokoro stopped unexpectedly twice on the stable route, so Meridian Reader switched to the Apple voice. Tap Kokoro in Settings to try again."

    /// `crashedRoute` nil = legacy marker (older builds only ran Core ML).
    static func onCrash(route crashedRoute: KokoroRoute?, onnxCrashCount: inout Int) -> Outcome {
        switch crashedRoute ?? .coreMLGPU {
        case .coreMLGPU:
            return .resumeOnONNX(disableFastRoute: true)
        case .onnxCPU:
            onnxCrashCount += 1
            if onnxCrashCount >= onnxCrashLimit {
                onnxCrashCount = 0 // a manual retry starts a fresh count
                return .fallBackToApple
            }
            return .resumeOnONNX(disableFastRoute: false)
        }
    }

    static func notice(for outcome: Outcome) -> String {
        switch outcome {
        case .resumeOnONNX: return resumedNotice
        case .fallBackToApple: return appleNotice
        }
    }

    /// The previous process died inside a Kokoro call: never silently leave the user on Apple.
    /// Updates the route settings (crash count, fast route off) and says where to resume.
    /// `playing` is the session's last resume point.
    static func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?,
                        settings: KokoroRouteSettings) -> CrashRecovery {
        var onnxCount = settings.onnxCrashCount
        let outcome = onCrash(route: crash.route.flatMap(KokoroRoute.init(rawValue:)), onnxCrashCount: &onnxCount)
        settings.onnxCrashCount = onnxCount
        let recovery: CrashRecovery
        switch outcome {
        case .resumeOnONNX(let disableFastRoute):
            if disableFastRoute { settings.fastGPURouteEnabled = false }
            recovery = .stay(notice: resumedNotice, resume: ListenResumeTarget.forCrash(
                article: crash.articleKey, paragraph: crash.paragraph, crashAt: crash.at, playing: playing))
        case .fallBackToApple:
            recovery = .switchAway(notice: appleNotice)
        }
        let resume = recovery.resume
        ListenTimingLog.log("kokoro_auto_recover", [
            "route": crash.route ?? "legacy", "outcome": String(describing: outcome),
            "onnx_crashes": onnxCount, "resume_key": resume?.articleKey.prefix(8) ?? "",
            "resume_p": resume?.paragraph ?? -1, "auto_play": resume?.autoPlay ?? false,
        ])
        print("[TTS] Kokoro crash (route \(crash.route ?? "legacy")) → \(outcome)")
        return recovery
    }
}
