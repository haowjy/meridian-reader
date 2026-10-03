import Foundation

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
