import Foundation

/// Durable "which Core ML model / stage is about to run" marker, written atomically before every
/// instrumented FluidAudio prediction (vendored `CoreMLBreadcrumb` patch). E5RT runs Core ML on its
/// own queue, so a libBNNS crash report never shows the calling model; after a Kokoro crash the next
/// launch logs it (`logStage(of:)`, from `FluidAudioProvider.recover`).
///
/// Only the Core ML Kokoro route (debug "fast GPU route") ever writes it — the ONNX CPU route has
/// no Core ML at all.
struct CoreMLBreadcrumbFile: Sendable {
    let url: URL

    static let shared = CoreMLBreadcrumbFile(
        url: EngineCrashGuard.shared.directory.appendingPathComponent("coreml_breadcrumb.json"))

    struct Entry: Equatable {
        var model: String
        var stage: String
        var detail: String?
        var at: Date
    }

    func write(model: String, stage: String, detail: String?, now: Date = Date()) {
        var obj: [String: Any] = ["model": model, "stage": stage, "t": now.timeIntervalSince1970]
        if let detail { obj["detail"] = String(detail.prefix(40)) }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        if (try? data.write(to: url, options: .atomic)) == nil {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    func read() -> Entry? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = obj["model"] as? String, let stage = obj["stage"] as? String,
              let t = obj["t"] as? Double
        else { return nil }
        return Entry(model: model, stage: stage, detail: obj["detail"] as? String,
                     at: Date(timeIntervalSince1970: t))
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// The model and stage `crash`'s call was running, logged as `engine_crash_coreml_stage`
    /// when the breadcrumb was written during that call; then the breadcrumb goes.
    func logStage(of crash: EngineCrashGuard.CrashInfo) {
        defer { clear() }
        guard let crumb = read(), crumb.at >= crash.at.addingTimeInterval(-0.001) else { return }
        ListenTimingLog.log("engine_crash_coreml_stage", [
            "coreml_stage": "\(crumb.model)/\(crumb.stage)", "coreml_detail": crumb.detail ?? "",
            "coreml_ms_after_start": Int(crumb.at.timeIntervalSince(crash.at) * 1000),
        ])
    }
}
