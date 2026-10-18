import Foundation

/// How Kokoro renders. Both routes use the same voice packs, phonemes and article cache key
/// ("kokoro.<voice>"), so audio rendered on either route stays valid on the other.
///
/// - `onnxCPU` (default): ONNX Runtime on the CPU execution provider
///   (`KokoroCPUHost`). No Core ML / Espresso / BNNS anywhere in the call, so it neither hits the
///   iOS 26.4+ libBNNS SIGSEGV nor is it forbidden in the background (CPU work is allowed while
///   audio plays).
/// - `coreMLGPU` (debug opt-in, `KokoroSplitHost`): in front, FluidAudio's 7-stage Core ML chain
///   (`KokoroHost`, `aneTailGpu`: RNN stages on the ANE, noise and the iSTFT tail on the GPU);
///   from the first call in the background to the end of the process, the ONNX CPU route. Faster
///   in front, but Core ML can crash in libBNNS on iOS 26.4+ (uncatchable).
enum KokoroRoute: String, Sendable, Equatable {
    case onnxCPU = "onnx"
    case coreMLGPU = "coreml"

    var label: String {
        switch self {
        case .onnxCPU: return "ONNX CPU"
        case .coreMLGPU: return "Core ML (ANE + GPU)"
        }
    }
}

/// Persisted Kokoro route knobs (UserDefaults; injectable for tests).
struct KokoroRouteSettings {
    static let fastGPURouteKey = "reader.tts.kokoro.fastGPURoute"
    static let cpuThreadsKey = "reader.tts.kokoro.cpuThreads"
    static let onnxCrashCountKey = "reader.tts.kokoro.onnxCrashCount"
    static let storedKeys = [fastGPURouteKey, cpuThreadsKey, onnxCrashCountKey]
    /// ONNX intra-op threads in front by default: every core but one (the UI, audio and the render
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
    /// ONNX intra-op threads while the app is in the background, whatever `cpuThreads` says: iOS
    /// kills a backgrounded app that keeps several cores busy (it died about a minute after the
    /// phone locked, rendering at 3 threads).
    static let backgroundThreads = 1

    /// Threads for a model call in `phase`: `configured` while the app is in front (inactive
    /// included), `backgroundThreads` in the background.
    static func onnxThreads(configured: Int, phase: AppRunState.Phase) -> Int {
        phase == .background ? backgroundThreads : configured
    }

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
/// - Any Kokoro crash turns the Core ML route off: it resumes on the ONNX route.
/// - Core ML crash (or a pre-route marker from an older build) → stay on Kokoro/ONNX, resume.
/// - ONNX route crash #1 → stay on Kokoro/ONNX, resume.
/// - ONNX route crash #2 (without a healthy stretch in between) → Apple, with a clear notice.
/// A healthy stretch (`healthyRendersToReset` ONNX calls in one session) or picking Kokoro again
/// in Settings resets the ONNX count.
enum KokoroCrashRecovery {
    static let onnxCrashLimit = 2
    static let healthyRendersToReset = 40

    enum Outcome: Equatable {
        /// Keep Kokoro selected on the ONNX route and resume where the crash happened.
        case resumeOnONNX
        /// The ONNX route crashed `onnxCrashLimit` times: switch to Apple.
        case fallBackToApple
    }

    static let resumedNotice = "Kokoro stopped unexpectedly; resumed on the stable route."
    static let appleNotice = "Kokoro stopped unexpectedly twice on the stable route, so Meridian Reader switched to the Apple voice. Tap Kokoro in Settings to try again."

    /// `crashedRoute` nil = legacy marker (older builds only ran Core ML).
    static func onCrash(route crashedRoute: KokoroRoute?, onnxCrashCount: inout Int) -> Outcome {
        switch crashedRoute ?? .coreMLGPU {
        case .coreMLGPU:
            return .resumeOnONNX
        case .onnxCPU:
            onnxCrashCount += 1
            if onnxCrashCount >= onnxCrashLimit {
                onnxCrashCount = 0 // a manual retry starts a fresh count
                return .fallBackToApple
            }
            return .resumeOnONNX
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
        settings.fastGPURouteEnabled = false
        let recovery: CrashRecovery
        switch outcome {
        case .resumeOnONNX:
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
        return recovery
    }
}
