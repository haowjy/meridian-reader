import Foundation

/// Containment for engines that can die *uncatchably* inside a model call (Kokoro: libBNNS
/// SIGSEGV on iOS 26.4+, FluidAudio #844/#817; reproduced on an iPhone 17 Pro).
///
/// Before every guarded call we durably write an "in flight" marker (`Data.write(.atomic)`, not
/// UserDefaults, which may never reach disk before the process dies). It is removed when the
/// call returns (success or Swift error). If the app launches and the marker is still there, the
/// previous process died inside that engine: the coordinator switches away and tells the user.
/// Which engines are guarded comes from `OnDeviceTraits.crashNotice`.
struct EngineCrashGuard: Sendable {
    let directory: URL

    static let shared = EngineCrashGuard(directory: {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ListenTiming", isDirectory: true)
    }())

    private var inflightURL: URL { directory.appendingPathComponent("engine_inflight.json") }
    private var crashesURL: URL { directory.appendingPathComponent("engine_crashes.json") }

    /// What the previous process was doing when it died.
    struct CrashInfo: Equatable {
        var engine: SpeechEngineID?
        /// "onnx" / "coreml"; nil for markers written before routes existed (Core ML only).
        var route: String?
        /// Full article key, or the 8-char prefix an older marker's `ctx` ("BA7D7639/p14") holds.
        var articleKey: String?
        var paragraph: Int?
        var phase: String?
        var at: Date
        /// Last Core ML model/stage breadcrumb written during the fatal call ("kokoro/vocoder",
        /// "g2p.bart/decoder"); nil on the ONNX route or when no breadcrumb postdates the marker.
        var coreMLStage: String? = nil
    }

    func beginCall(engine: SpeechEngineID, chars: Int, route: String? = nil, article: UUID? = nil,
                   paragraph: Int? = nil, phase: AppRunState.Phase = .active) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var obj: [String: Any] = [
            "t": Date().timeIntervalSince1970, "engine": engine.rawValue, "chars": chars, "phase": phase.rawValue,
        ]
        if let route { obj["route"] = route }
        if let article { obj["article"] = article.uuidString }
        if let paragraph { obj["p"] = paragraph }
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: inflightURL, options: .atomic)
        }
    }

    func endCall() {
        try? FileManager.default.removeItem(at: inflightURL)
    }

    /// Call once at launch: what the previous process was doing when it died inside an engine
    /// call (the engine, route, article and paragraph, for auto-recover), or nil.
    func consumeCrashInfo() -> CrashInfo? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: inflightURL.path) else { return nil }
        let info = (try? Data(contentsOf: inflightURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        try? fm.removeItem(at: inflightURL)
        let engine = (info?["engine"] as? String).map(SpeechEngineID.init(rawValue:))
        let count = crashCount + 1
        let obj: [String: Any] = ["count": count, "last": info ?? [:], "at": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: crashesURL, options: .atomic)
        }
        var result = Self.crashInfo(from: info ?? [:], engine: engine)
        var fields: [String: Any] = [
            "engine": engine?.rawValue ?? "?", "count": count, "last_chars": info?["chars"] ?? -1,
            "route": info?["route"] ?? "legacy", "key": result.articleKey.map { String($0.prefix(8)) } ?? "",
            "p": result.paragraph ?? -1,
        ]
        let crumbs = CoreMLBreadcrumbFile(url: directory.appendingPathComponent("coreml_breadcrumb.json"))
        if let crumb = crumbs.read(), let markerT = info?["t"] as? Double,
           crumb.at.timeIntervalSince1970 >= markerT - 0.001 {
            let stage = "\(crumb.model)/\(crumb.stage)"
            result.coreMLStage = stage
            fields["coreml_stage"] = stage
            fields["coreml_detail"] = crumb.detail ?? ""
            fields["coreml_ms_after_start"] = Int((crumb.at.timeIntervalSince1970 - markerT) * 1000)
            // Keep it next to engine_crashes.json for later inspection.
            if var obj = (try? Data(contentsOf: crashesURL)).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] {
                obj["coreml_stage"] = stage
                if let data = try? JSONSerialization.data(withJSONObject: obj) {
                    try? data.write(to: crashesURL, options: .atomic)
                }
            }
        }
        crumbs.clear()
        ListenTimingLog.log("engine_crash_detected", fields)
        return result
    }

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
                         paragraph: paragraph, phase: info["phase"] as? String, at: t)
    }

    /// Last recorded crash (from `engine_crashes.json`), e.g. for the one-time ONNX migration.
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
    /// Keep the engine selected, show `notice`, and reopen `resume` when there is one.
    case stay(notice: String, resume: ListenResumeTarget?)
    /// Switch to `EngineRegistry.crashFallback` and show `notice`; picking the crashed engine
    /// again is a fresh try.
    case switchAway(notice: String)

    var notice: String {
        switch self {
        case .stay(let notice, _), .switchAway(let notice): return notice
        }
    }

    var resume: ListenResumeTarget? {
        if case .stay(_, let resume) = self { return resume }
        return nil
    }
}
