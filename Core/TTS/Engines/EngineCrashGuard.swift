import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Containment for engines that can die *uncatchably* inside a model call (Kokoro: libBNNS
/// SIGSEGV on iOS 26.4+, FluidAudio #844/#817; reproduced on an iPhone 17 Pro).
///
/// Before every guarded call we durably write an "in flight" marker (`Data.write(.atomic)`, not
/// UserDefaults, which may never reach disk before the process dies), with the engine, route,
/// article, paragraph, app phase and memory footprint. It is removed when the call returns
/// (success or Swift error), so it exists only while a call is in flight. A process that is
/// terminated (`willTerminateNotification`: a swipe-kill of the running app) clears it and writes
/// no other. At launch a marker left behind means the previous process died during a call, and
/// `consumeCrashInfo` says whether the engine killed it (`MarkerVerdict`); only then does the
/// coordinator switch away and tell the user. Which engines are guarded comes from
/// `OnDeviceTraits.crashNotice`.
final class EngineCrashGuard: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private var terminating = false
    private var terminateObserver: NSObjectProtocol?

    static let shared = EngineCrashGuard(directory: AppDirectories.listenTiming)

    /// A death this long after the marker was written, while the process was still active,
    /// didn't come from that call: no call takes a minute.
    static let callBound: TimeInterval = 60
    /// A death in the background with this footprint or more (MB) is taken for iOS reclaiming
    /// memory (jetsam), not the engine: about twice the ONNX route's footprint between calls.
    static let memoryKillFootprintMB = 1_000

    init(directory: URL) {
        self.directory = directory
        #if canImport(UIKit)
        terminateObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.processWillTerminate() }
        #endif
    }

    deinit {
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }

    private var inflightURL: URL { directory.appendingPathComponent("engine_inflight.json") }
    private var crashesURL: URL { directory.appendingPathComponent("engine_crashes.json") }

    /// What the previous process was doing when it died.
    struct CrashInfo: Equatable {
        var engine: SpeechEngineID?
        /// The host's `routeTag`; nil for markers written before routes existed.
        var route: String?
        /// Full article key, or the 8-char prefix an older marker's `ctx` ("BA7D7639/p14") holds.
        var articleKey: String?
        var paragraph: Int?
        /// `AppRunState.Phase` raw value when the call started.
        var phase: String?
        var at: Date
        /// `phys_footprint` when the call started, MB; nil in older markers.
        var footprintMB: Int? = nil
        /// `EngineCrashGuard.buildStamp` of the process that wrote the marker; nil in older ones.
        var build: String? = nil

        /// Whether the engine killed the process. `lastActivity`: the latest time the previous
        /// process is known to have been playing (`ListenResumePointStore`).
        func verdict(lastActivity: Date?, currentBuild: String? = EngineCrashGuard.buildStamp) -> MarkerVerdict {
            // C129: installing a new build kills the running app; a call it cut off isn't a crash.
            if let build, let currentBuild, build != currentBuild { return .reinstalled }
            if let lastActivity, lastActivity.timeIntervalSince(at) > EngineCrashGuard.callBound { return .stale }
            if phase == AppRunState.Phase.background.rawValue, let footprintMB,
               footprintMB >= EngineCrashGuard.memoryKillFootprintMB { return .memoryKill }
            return .engineCrash
        }
    }

    /// What a marker left at launch means.
    enum MarkerVerdict: String {
        /// The process died inside the call: the engine crashed.
        case engineCrash = "engine_crash"
        /// It died in the background with a large footprint: iOS reclaimed the memory.
        case memoryKill = "memory_kill"
        /// It went on long past the call's start: the call wasn't what ended it.
        case stale
        /// Another build wrote it: an install replaced the app mid-call (C129).
        case reinstalled
    }

    func beginCall(engine: SpeechEngineID, chars: Int, route: String? = nil, article: UUID? = nil,
                   paragraph: Int? = nil, phase: AppRunState.Phase = .active) {
        var obj: [String: Any] = [
            "t": Date().timeIntervalSince1970, "engine": engine.rawValue, "chars": chars, "phase": phase.rawValue,
            "mem_mb": ProcessMemory.footprintMB,
        ]
        if let build = Self.buildStamp { obj["build"] = build }
        if let route { obj["route"] = route }
        if let article { obj["article"] = article.uuidString }
        if let paragraph { obj["p"] = paragraph }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        lock.withLock {
            guard !terminating else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: inflightURL, options: .atomic)
        }
    }

    func endCall() {
        lock.withLock { try? FileManager.default.removeItem(at: inflightURL) }
    }

    /// The process is being terminated (a swipe-kill while it runs): a call it ends isn't a
    /// crash, so the marker goes, and no call writes another.
    func processWillTerminate() {
        lock.withLock {
            terminating = true
            try? FileManager.default.removeItem(at: inflightURL)
        }
    }

    /// Call once at launch: what the previous process was doing when the engine killed it
    /// inside a call (the engine, route, article and paragraph, for auto-recover), or nil. A
    /// marker the engine didn't cause (`MarkerVerdict`) is logged and dropped.
    func consumeCrashInfo(lastActivity: Date? = nil) -> CrashInfo? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: inflightURL.path) else { return nil }
        let info = (try? Data(contentsOf: inflightURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        try? fm.removeItem(at: inflightURL)
        let engine = (info?["engine"] as? String).map(SpeechEngineID.init(rawValue:))
        let result = Self.crashInfo(from: info ?? [:], engine: engine)
        var fields: [String: Any] = [
            "engine": engine?.rawValue ?? "?", "last_chars": info?["chars"] ?? -1,
            "route": info?["route"] ?? "legacy", "key": result.articleKey.map { String($0.prefix(8)) } ?? "",
            "p": result.paragraph ?? -1, "phase": result.phase ?? "?", "mem_mb": result.footprintMB ?? -1,
        ]
        let verdict = result.verdict(lastActivity: lastActivity)
        fields["verdict"] = verdict.rawValue
        if let lastActivity { fields["activity_after_s"] = Int(lastActivity.timeIntervalSince(result.at)) }
        guard verdict == .engineCrash else {
            ListenTimingLog.log("engine_marker_dismissed", fields)
            return nil
        }
        let count = crashCount + 1
        fields["count"] = count
        let record: [String: Any] = ["count": count, "last": info ?? [:], "at": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: record) {
            try? data.write(to: crashesURL, options: .atomic)
        }
        ListenTimingLog.log("engine_crash_detected", fields)
        return result
    }

    /// A marker's fields; an older marker names the article and paragraph in its `ctx`.
    static func crashInfo(from info: [String: Any], engine: SpeechEngineID?) -> CrashInfo {
        var key = info["article"] as? String
        var paragraph = info["p"] as? Int
        if let ctx = info["ctx"] as? String {
            // An older marker's "BA7D7639/p14".
            let parts = ctx.split(separator: "/")
            if key == nil, let k = parts.first, k.count >= 8, k != "?" { key = String(k) }
            if paragraph == nil, parts.count > 1, parts[1].hasPrefix("p") { paragraph = Int(parts[1].dropFirst()) }
        }
        if let p = paragraph, p < 0 { paragraph = nil }
        let t = (info["t"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        return CrashInfo(engine: engine, route: info["route"] as? String, articleKey: key,
                         paragraph: paragraph, phase: info["phase"] as? String, at: t,
                         footprintMB: info["mem_mb"] as? Int, build: info["build"] as? String)
    }

    /// Identifies the installed build: the executable's size and modification time, which every
    /// install (even of the same version number) changes. nil when unreadable.
    static let buildStamp: String? = {
        guard let path = Bundle.main.executablePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber, let date = attrs[.modificationDate] as? Date
        else { return nil }
        return "\(size.intValue)-\(Int(date.timeIntervalSince1970))"
    }()

    /// Last recorded crash (from `engine_crashes.json`), e.g. for a provider's launch step.
    var lastCrash: CrashInfo? {
        guard let data = try? Data(contentsOf: crashesURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let last = obj["last"] as? [String: Any], !last.isEmpty
        else { return nil }
        let engine = (last["engine"] as? String).map(SpeechEngineID.init(rawValue:))
        return Self.crashInfo(from: last, engine: engine)
    }

    var crashCount: Int {
        guard let data = try? Data(contentsOf: crashesURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }
        return obj["count"] as? Int ?? 0
    }
}

/// What to do after the previous process died inside an engine's call (a provider's answer to
/// `SpeechEngineProvider.recover(from:playing:)`).
enum CrashRecovery: Equatable {
    /// Keep the engine selected, show `notice` (nil: a silent same-voice recovery, C129), and
    /// reopen `resume` when there is one.
    case stay(notice: String?, resume: ListenResumeTarget?)
    /// Keep the engine and voice selected but pause playback and the render queue until the user
    /// taps Retry (C129: never fall to another engine or voice); show `notice`.
    case pauseForRetry(notice: String, resume: ListenResumeTarget?)
    /// Switch to `EngineRegistry.crashFallback` and show `notice`; picking the crashed engine
    /// again is a fresh try.
    case switchAway(notice: String)

    var notice: String? {
        switch self {
        case .stay(let notice, _): return notice
        case .pauseForRetry(let notice, _), .switchAway(let notice): return notice
        }
    }

    var resume: ListenResumeTarget? {
        switch self {
        case .stay(_, let resume), .pauseForRetry(_, let resume): return resume
        case .switchAway: return nil
        }
    }
}
