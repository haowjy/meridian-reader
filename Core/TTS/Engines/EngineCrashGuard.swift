import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Containment for engines that can die *uncatchably* inside a model call (a Core ML call can
/// SIGSEGV in libBNNS on iOS 26.4+, FluidAudio #844/#817, reproduced on an iPhone 17 Pro; an ONNX
/// Runtime call can crash too).
///
/// Before every guarded call we durably write an "in flight" marker of its own
/// (`engine_inflight/<call id>.json`, `Data.write(.atomic)`, not UserDefaults, which may never
/// reach disk before the process dies), with the engine, route, article, paragraph, app phase and
/// memory footprint. It is removed when that call returns (success or Swift error), so it exists
/// only while the call is in flight. A process that is terminated (`willTerminateNotification`: a
/// swipe-kill of the running app) clears them all and writes no other. At launch a marker left
/// behind means the previous process died during a call, and `consumeCrashInfo` says whether the
/// engine killed it (`MarkerVerdict`); only then does the coordinator recover (`CrashRecovery`)
/// and tell the user. Two or more engine-crash markers can't say which call it was
/// (`ambiguous`). Which engines are guarded comes from `OnDeviceTraits.isCrashGuarded`.
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

    /// One marker per call in flight.
    private var inflightDirectory: URL { directory.appendingPathComponent("engine_inflight", isDirectory: true) }
    /// The single marker an earlier build wrote; read at launch as one more.
    private var legacyInflightURL: URL { directory.appendingPathComponent("engine_inflight.json") }
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
        /// Several calls were in flight when it died, each an engine crash by its own marker: it
        /// can't say which one did it (this is the latest). No provider recovers from it.
        var isAmbiguous = false

        /// Whether the engine killed the process. `lastActivity`: the latest time the previous
        /// process is known to have been playing (`ListenResumePointStore`).
        func verdict(lastActivity: Date?, currentBuild: String? = EngineCrashGuard.buildStamp) -> MarkerVerdict {
            // Installing a new build kills the running app; a call it cut off isn't a crash.
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
        /// Another build wrote it: an install replaced the app mid-call.
        case reinstalled
        /// Several markers each read as an engine crash: which call killed it is unknown, so it
        /// pauses for Retry.
        case ambiguous
    }

    /// Writes the call's marker; `endCall` with the returned id removes it.
    @discardableResult
    func beginCall(engine: SpeechEngineID, chars: Int, route: String? = nil, article: UUID? = nil,
                   paragraph: Int? = nil, phase: AppRunState.Phase = .active) -> UUID {
        let call = UUID()
        var obj: [String: Any] = [
            "t": Date().timeIntervalSince1970, "engine": engine.rawValue, "chars": chars, "phase": phase.rawValue,
            "mem_mb": ProcessMemory.footprintMB,
        ]
        if let build = Self.buildStamp { obj["build"] = build }
        if let route { obj["route"] = route }
        if let article { obj["article"] = article.uuidString }
        if let paragraph { obj["p"] = paragraph }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return call }
        lock.withLock {
            guard !terminating else { return }
            try? FileManager.default.createDirectory(at: inflightDirectory, withIntermediateDirectories: true)
            try? data.write(to: markerURL(call), options: .atomic)
        }
        return call
    }

    func endCall(_ call: UUID) {
        lock.withLock { try? FileManager.default.removeItem(at: markerURL(call)) }
    }

    private func markerURL(_ call: UUID) -> URL {
        inflightDirectory.appendingPathComponent("\(call.uuidString).json")
    }

    /// The process is being terminated (a swipe-kill while it runs): a call it ends isn't a
    /// crash, so the markers go, and no call writes another.
    func processWillTerminate() {
        lock.withLock {
            terminating = true
            for url in markerURLs() { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Every marker on disk: one per call in flight, and an earlier build's single one.
    private func markerURLs() -> [URL] {
        let fm = FileManager.default
        let calls = (try? fm.contentsOfDirectory(at: inflightDirectory, includingPropertiesForKeys: nil)) ?? []
        return calls.filter { $0.pathExtension == "json" } + (fm.fileExists(atPath: legacyInflightURL.path) ? [legacyInflightURL] : [])
    }

    /// Call once at launch: what the previous process was doing when the engine killed it
    /// inside a call (the engine, route, article and paragraph, for auto-recover), or nil. A
    /// marker the engine didn't cause (`MarkerVerdict`) is logged and dropped; two or more it did
    /// are one ambiguous crash (the latest marker's, `isAmbiguous`).
    func consumeCrashInfo(lastActivity: Date? = nil) -> CrashInfo? {
        let urls = lock.withLock { markerURLs() }
        var crashes: [(info: [String: Any], crash: CrashInfo, fields: [String: Any])] = []
        for url in urls {
            let info = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            try? FileManager.default.removeItem(at: url)
            let engine = (info["engine"] as? String).map(SpeechEngineID.init(rawValue:))
            let result = Self.crashInfo(from: info, engine: engine)
            var fields: [String: Any] = [
                "engine": engine?.rawValue ?? "?", "last_chars": info["chars"] ?? -1,
                "route": info["route"] ?? "legacy", "key": result.articleKey.map { String($0.prefix(8)) } ?? "",
                "p": result.paragraph ?? -1, "phase": result.phase ?? "?", "mem_mb": result.footprintMB ?? -1,
            ]
            let verdict = result.verdict(lastActivity: lastActivity)
            fields["verdict"] = verdict.rawValue
            if let lastActivity { fields["activity_after_s"] = Int(lastActivity.timeIntervalSince(result.at)) }
            guard verdict == .engineCrash else {
                ListenTimingLog.log("engine_marker_dismissed", fields)
                continue
            }
            crashes.append((info, result, fields))
        }
        guard var latest = crashes.max(by: { $0.crash.at < $1.crash.at }) else { return nil }
        if crashes.count > 1 {
            latest.crash.isAmbiguous = true
            latest.fields["verdict"] = MarkerVerdict.ambiguous.rawValue
            latest.fields["markers"] = crashes.count
        }
        let count = crashCount + 1
        latest.fields["count"] = count
        let record: [String: Any] = ["count": count, "last": latest.info, "at": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: record) {
            try? data.write(to: crashesURL, options: .atomic)
        }
        ListenTimingLog.log("engine_crash_detected", latest.fields)
        return latest.crash
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

    var crashCount: Int {
        guard let data = try? Data(contentsOf: crashesURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }
        return obj["count"] as? Int ?? 0
    }
}

/// What to do after the previous process died inside an engine's call (a provider's answer to
/// `SpeechEngineProvider.recover(from:playing:)`).
/// The engine and voice always stay (never another engine or voice).
enum CrashRecovery: Equatable {
    /// Go on as before, silently (the same voice and its cached audio, so nothing the user hears
    /// changes), and reopen `resume` when there is one.
    case stay(resume: ListenResumeTarget?)
    /// The render queue (downloads, render-ahead) waits for Retry; playback goes on through
    /// rendered audio and pauses where there is none, and the user is told then ("Kokoro
    /// stopped.", with Retry).
    case pauseForRetry(resume: ListenResumeTarget?)

    var resume: ListenResumeTarget? {
        switch self {
        case .stay(let resume), .pauseForRetry(let resume): return resume
        }
    }
}
