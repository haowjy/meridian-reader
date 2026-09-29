import Foundation

/// How Kokoro renders. Both routes use the same voice packs, phonemes and article cache key
/// ("kokoro.<voice>"), so audio rendered on either route stays valid on the other.
///
/// - `onnxCPU` (default, 2026-09-24): ONNX Runtime on the CPU execution provider
///   (`KokoroCPUHost`). No Core ML / Espresso / BNNS anywhere in the call, so it neither hits the
///   iOS 26.4+ libBNNS SIGSEGV nor is it forbidden in the background (CPU work is allowed while
///   audio plays).
/// - `coreMLGPU` (debug opt-in): FluidAudio's 7-stage Core ML chain (`KokoroHost`,
///   gpuAneVocoder on iOS 26.4+). ~4× faster but crashed in libBNNS 5× on 2026-09-24 and can't
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
    var route: KokoroRoute { KokoroRoutePolicy.route(fastGPURouteEnabled: fastGPURouteEnabled) }
}

/// Pure route choice (unit-tested).
enum KokoroRoutePolicy {
    static func route(fastGPURouteEnabled: Bool) -> KokoroRoute {
        fastGPURouteEnabled ? .coreMLGPU : .onnxCPU
    }
}

/// (d) auto-recover after a crash inside a Kokoro call — pure state machine (unit-tested).
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
    static let appleNotice = "Kokoro stopped unexpectedly twice on the stable route, so Reader switched to the Apple voice. Tap Kokoro in Settings to try again."

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
}

/// Where to resume listening after a crash.
struct ListenResumeTarget: Equatable, Sendable {
    /// Full article/cache key, or an 8-char uppercase prefix from an older crash marker.
    var articleKey: String
    var paragraph: Int
    /// When the point was recorded (resume file) or the crash happened (marker).
    var at: Date
    /// Start playing right away (the crash interrupted listening moments ago), else open the
    /// article paused at the paragraph.
    var autoPlay: Bool = false

    func matches(_ id: UUID) -> Bool {
        let s = id.uuidString
        return articleKey.count >= 36 ? s == articleKey.uppercased() : s.hasPrefix(articleKey.uppercased())
    }

    /// Resume point for a crash: the paragraph that was *playing* (resume file, written per
    /// paragraph) if it was recorded shortly before the crash — the crash marker's paragraph is
    /// the one being *rendered*, which can be ahead or in another article; else the marker's.
    /// Auto-play only if the user was listening and the crash was recent. Pure; unit-tested.
    static func forCrash(article: String?, paragraph: Int?, crashAt: Date,
                         playing point: ListenResumeTarget?, now: Date = Date(),
                         listeningWindow: TimeInterval = 10 * 60,
                         autoPlayWindow: TimeInterval = 20 * 60) -> ListenResumeTarget? {
        let recentCrash = now.timeIntervalSince(crashAt) < autoPlayWindow
        if let point {
            let lead = crashAt.timeIntervalSince(point.at)
            if lead >= -60, lead <= listeningWindow {
                return ListenResumeTarget(articleKey: point.articleKey, paragraph: point.paragraph,
                                          at: crashAt, autoPlay: recentCrash)
            }
        }
        guard let article, !article.isEmpty else { return nil }
        return ListenResumeTarget(articleKey: article, paragraph: max(0, paragraph ?? 0), at: crashAt, autoPlay: false)
    }
}

/// Durable "what is playing" point (atomic file write per paragraph), so a crash can resume at
/// the paragraph the user was hearing — SwiftData's `playbackParagraphIndex` may not have been
/// saved when the process died (it lagged 10 paragraphs in the 23:45 crash).
struct ListenResumePointStore: Sendable {
    let url: URL

    static let shared = ListenResumePointStore(url: {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ListenTiming/listen_resume.json")
    }())

    func save(article: UUID, paragraph: Int, at date: Date = Date()) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let obj: [String: Any] = ["article": article.uuidString, "p": paragraph, "t": date.timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func load() -> ListenResumeTarget? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let article = obj["article"] as? String, let p = obj["p"] as? Int
        else { return nil }
        let t = (obj["t"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        return ListenResumeTarget(articleKey: article, paragraph: p, at: t)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
}
