import Foundation

/// Where to resume listening after a crash.
struct ListenResumeTarget: Equatable, Sendable {
    /// Full article/cache key, or an 8-char uppercase prefix from an older crash marker.
    var articleKey: String
    var paragraph: Int
    /// The text `paragraph` counts in: the fingerprint of the paragraphs the session was playing
    /// (`PlaybackSessionState.textFingerprint`). Crash resume applies the paragraph only to a
    /// page holding that text. nil from a crash marker (it names the paragraph being rendered,
    /// not its text) and from a resume file an older build wrote.
    var text: String? = nil
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
    /// paragraph), with the text it was in, if it was recorded shortly before the crash — the
    /// crash marker's paragraph is the one being *rendered*, which can be ahead or in another
    /// article; else the marker's, which names no text. Auto-play only if the user was listening
    /// and the crash was recent. Pure; unit-tested.
    static func forCrash(article: String?, paragraph: Int?, crashAt: Date,
                         playing point: ListenResumeTarget?, now: Date = Date(),
                         listeningWindow: TimeInterval = 10 * 60,
                         autoPlayWindow: TimeInterval = 20 * 60) -> ListenResumeTarget? {
        let recentCrash = now.timeIntervalSince(crashAt) < autoPlayWindow
        if let point {
            let lead = crashAt.timeIntervalSince(point.at)
            if lead >= -60, lead <= listeningWindow {
                return ListenResumeTarget(articleKey: point.articleKey, paragraph: point.paragraph, text: point.text,
                                          at: crashAt, autoPlay: recentCrash)
            }
        }
        guard let article, !article.isEmpty else { return nil }
        return ListenResumeTarget(articleKey: article, paragraph: max(0, paragraph ?? 0), at: crashAt, autoPlay: false)
    }
}

/// Durable "what is playing" point (atomic file write per paragraph), so a crash can resume at
/// the paragraph the user was hearing: the page's stored position may not have been saved when
/// the process died. It holds the key, the paragraph, the text it is a paragraph of and when it
/// was written; a file an older build wrote has no text.
struct ListenResumePointStore: Sendable {
    let url: URL

    static let shared = ListenResumePointStore(url: {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ListenTiming/listen_resume.json")
    }())

    func save(article: UUID, paragraph: Int, text: String? = nil, at date: Date = Date()) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var obj: [String: Any] = ["article": article.uuidString, "p": paragraph, "t": date.timeIntervalSince1970]
        if let text { obj["text"] = text }
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
        return ListenResumeTarget(articleKey: article, paragraph: p, text: obj["text"] as? String, at: t)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
}
