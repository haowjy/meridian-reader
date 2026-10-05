#if DEBUG
import Foundation
import os
import UIKit

/// `-probeLockedFetch` (Debug builds only): the owner's device check of two things web serials
/// count on while the phone is locked and audio plays.
///
/// 1. **A hidden fetch.** `fetchDelay` after the app goes to the background, `URLPageFetcher`
///    loads the offline page `reader-test://fetch/hidden-span`, then extracts it. The log says
///    whether WebKit finished loading (`did_finish`), what the snapshot held (also saved whole, as
///    `snapshot.html`) and whether extraction answered. A WebKit process suspended in the
///    background shows as a stage that timed out.
/// 2. **A silent wait between chapters.** Playback runs through a two-chapter series. Chapter 2
///    is a link chapter: when chapter 1 ends, playback waits for its fetch, silent, as it will for
///    a web serial (`SpeechController+Advance`), and the fetch holds `silentHold` before it
///    answers. The log says how long the hold really took (much longer means the app was
///    suspended) and whether chapter 2 then became audible.
///
/// It leaves the library alone. The series lives in memory (`ProbeSeries`, which playback asks
/// before the library); its text is the demo book's synthetic chapters (`DemoBook`); and its
/// chapters are started directly, not from an article, so the progress recorder finds no page to
/// write to. Their audio goes to the audio cache under two fixed keys, removed at the start of
/// each run, and is pruned later like other audio of unsaved pages. It doesn't start if something
/// already plays (a crash resume).
///
/// Log: `Application Support/LockedFetchProbe/probe.jsonl` (this run only; `snapshot.html`
/// beside it), and each line in the unified log, subsystem `com.jimmyyao.Reader`, category
/// `LockedFetchProbe`.
@MainActor
final class LockedFetchProbe {
    /// The fetch runs this long after the app goes to the background.
    static let fetchDelay: TimeInterval = 60
    /// Each fetch stage's time limit.
    static let fetchTimeout: TimeInterval = 15
    /// Chapter 2's fetch holds playback, silent, this long.
    static let silentHold: TimeInterval = 5
    /// How long after the hold chapter 2 has to become audible.
    static let resumeWatch: TimeInterval = 20

    /// The probe of this launch, kept while its observers and timers run.
    private static var current: LockedFetchProbe?

    private let speech: SpeechController
    private let series: ProbeSeries
    private let log: ProbeLog
    private var observers: [NSObjectProtocol] = []
    private var backgroundedAt: Date?
    private var fetchScheduled = false
    private var fetchInFlight = false

    private init(speech: SpeechController, log: ProbeLog) {
        self.speech = speech
        self.log = log
        series = ProbeSeries(library: speech.nextChapters)
    }

    /// Once launched: starts the series and arms the fetch.
    static func run(speech: SpeechController) async {
        let log = ProbeLog.startingRun()
        guard speech.activeSessionID == nil else {
            log("probe_skipped", ["why": "something already plays (a crash resume)"])
            return
        }
        let probe = LockedFetchProbe(speech: speech, log: log)
        current = probe
        await probe.start()
    }

    private func start() async {
        for key in ProbeSeries.keys { try? speech.localTTS.audioCache.deleteAudio(for: key) }
        speech.nextChapters = series
        series.fetchLink = { [weak self] in await self?.holdSilently() ?? false }
        // The hold, not the background wait limit, decides: the limit is raised past it.
        speech.chapterFlow.waitLimits.background = Self.silentHold + 5
        observeAppState()
        // As the demo hooks do: wait (≤ 20 s) for the on-device engine so it doesn't start on Apple.
        var waited = 0
        while speech.localTTS.synth.state.warmingEngineID != nil, waited < 100 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 1
        }
        speech.start(series.sessions[0], fromParagraph: 0)
        log("probe_start", state().merging([
            "engine": speech.activeEngine?.name ?? "—", "rate": speech.rateMultiplier,
            "build": LocalTTSCoordinator.buildConfiguration, "fetch_delay_s": Self.fetchDelay,
            "silent_hold_s": Self.silentHold, "wait_limit_background_s": speech.chapterFlow.waitLimits.background,
            "page": TestPageSchemeHandler.hiddenSpanPage.absoluteString,
            "next": "lock the phone now",
        ]) { $1 })
        if UIApplication.shared.applicationState == .background { scheduleFetch() }
    }

    // MARK: - App state

    private func observeAppState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.log("probe_background", self.state())
                self.scheduleFetch()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.log("probe_foreground", self.state())
            }
        })
    }

    /// What every line carries: where the app and playback are.
    private func state() -> [String: Any] {
        var fields: [String: Any] = [
            "app_phase": AppRunState.shared.phase.rawValue,
            // false: locked (with a passcode), files protected until unlock
            "protected_data": UIApplication.shared.isProtectedDataAvailable,
            "playing": ListenTimingLog.shortKey(speech.activeSessionID),
            "phase": "\(speech.playbackPhase)",
            "awaiting_page": speech.playback.awaitingPage,
            "audible": speech.engineSnapshot().isAudible,
            "session_active": speech.audioSession.isActive,
            "deactivations": speech.audioSession.deactivationCount,
        ]
        if let backgroundedAt { fields["background_s"] = Int(Date().timeIntervalSince(backgroundedAt)) }
        return fields
    }

    // MARK: - 1. The hidden fetch

    private func scheduleFetch() {
        if backgroundedAt == nil { backgroundedAt = Date() }
        guard !fetchScheduled else { return }
        fetchScheduled = true
        log("probe_fetch_scheduled", ["in_s": Self.fetchDelay])
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fetchDelay))
            await self?.fetch()
        }
    }

    private func fetch() async {
        fetchInFlight = true
        defer { fetchInFlight = false }
        let fetcher = URLPageFetcher(timeout: Self.fetchTimeout)
        let url = TestPageSchemeHandler.hiddenSpanPage
        log("probe_fetch_start", state())
        let started = ListenTimingLog.now()
        let snapshot: URLPageFetcher.Snapshot
        do {
            snapshot = try await fetcher.snapshot(of: url)
        } catch {
            // A snapshot that timed out still means the load finished.
            let finished = (error as? URLPageFetcher.FetchError) == .timedOut(.snapshot)
            log("probe_fetch", state().merging(["did_finish": finished, "snapshot": false, "error": Self.describe(error),
                                                "ms": ListenTimingLog.ms(since: started)]) { $1 })
            return
        }
        log.save(snapshot.html, as: "snapshot.html")
        let hiddenKept = TestPageSchemeHandler.hiddenLines.filter { snapshot.html.contains($0) }
        log("probe_fetch", state().merging([
            "did_finish": true, "snapshot": true, "ms": ListenTimingLog.ms(since: started),
            "title": snapshot.title ?? "", "bytes": snapshot.html.utf8.count,
            "hidden_lines_dropped": hiddenKept.isEmpty, "saved_as": "snapshot.html",
        ]) { $1 })
        let extracting = ListenTimingLog.now()
        do {
            let content = try await fetcher.content(of: snapshot)
            log("probe_extract", state().merging([
                "ok": true, "ms": ListenTimingLog.ms(since: extracting), "title": content.title,
                "paragraphs": content.document.count,
                "hidden_lines_in_text": TestPageSchemeHandler.hiddenLines.filter { content.plainText.contains($0) }.count,
            ]) { $1 })
        } catch {
            log("probe_extract", state().merging(["ok": false, "error": Self.describe(error),
                                                  "ms": ListenTimingLog.ms(since: extracting)]) { $1 })
        }
    }

    // MARK: - 2. The silent wait

    /// Chapter 2's fetch: holds `silentHold`, then answers that the chapter is there.
    private func holdSilently() async -> Bool {
        log("probe_wait_start", state().merging(["hold_s": Self.silentHold, "fetch_in_flight": fetchInFlight]) { $1 })
        let started = ListenTimingLog.now()
        let deactivations = speech.audioSession.deactivationCount
        try? await Task.sleep(for: .seconds(Self.silentHold))
        log("probe_wait_end", state().merging(["held_ms": ListenTimingLog.ms(since: started)]) { $1 })
        series.linkFetched = true
        Task { [weak self] in await self?.watchForChapterTwo(silentSince: started, deactivations: deactivations) }
        return true
    }

    /// Whether chapter 2 becomes audible within `resumeWatch`, or playback ends first.
    private func watchForChapterTwo(silentSince started: CFAbsoluteTime, deactivations: Int) async {
        let chapterTwo = ProbeSeries.keys[1]
        let deadline = ListenTimingLog.now() + Self.resumeWatch
        func verdict(_ resumed: Bool, _ why: String) {
            log("probe_resumed", state().merging([
                "resumed": resumed, "why": why, "silence_ms": ListenTimingLog.ms(since: started),
                "deactivated": speech.audioSession.deactivationCount != deactivations,
                "engine": speech.activeEngine?.name ?? "—",
            ]) { $1 })
            log("probe_done", ["next": "unlock the phone and read the log back"])
        }
        while ListenTimingLog.now() < deadline {
            if speech.activeSessionID == chapterTwo, speech.engineSnapshot().isAudible {
                return verdict(true, "chapter 2 audible")
            }
            if speech.activeSessionID != chapterTwo, !speech.playback.awaitingPage {
                return verdict(false, "playback ended before chapter 2")
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        verdict(false, "chapter 2 not audible within \(Int(Self.resumeWatch)) s")
    }

    private static func describe(_ error: Error) -> String {
        if let fetchError = error as? URLPageFetcher.FetchError { return "\(fetchError)" }
        return error.localizedDescription
    }
}

/// The probe's series, in memory: chapter 1 saved, chapter 2 a link until its fetch answers.
/// Playback asks it first; a page that isn't one of its two goes to the library.
@MainActor
private final class ProbeSeries: NextChapterProviding {
    /// Fixed, so each run replaces the audio of the one before.
    static let keys = [UUID(uuidString: "596065A8-A114-4311-A72A-1B77FBB26BB9")!,
                       UUID(uuidString: "8D5CDA6E-764D-48C0-9A1C-12CED91A7BA6")!]
    static let folder = PlaybackFolder(id: UUID(uuidString: "B27C9A65-67F1-41B6-B116-EFDC26AA94F1")!,
                                       name: "Locked Fetch Probe")

    /// Chapter 1: the demo book's first two chapters (about three minutes at 1×); chapter 2: its
    /// third.
    let sessions: [SpeechSession]
    var linkFetched = false
    /// Chapter 2's fetch.
    var fetchLink: () async -> Bool = { false }
    private weak var library: (any NextChapterProviding)?

    init(library: (any NextChapterProviding)?) {
        self.library = library
        let texts = [DemoBook.chapters[1].paragraphs + DemoBook.chapters[2].paragraphs, DemoBook.chapters[3].paragraphs]
        sessions = zip(Self.keys, texts).enumerated().map { index, chapter in
            SpeechSession(id: chapter.0, document: ParagraphDocument(parts: chapter.1), detectedLanguage: "en",
                          title: "Probe Chapter \(index + 1)", site: DemoBook.author, folderID: Self.folder.id,
                          folderName: Self.folder.name)
        }
    }

    func folder(containing pageKey: UUID) -> PlaybackFolder? {
        Self.keys.contains(pageKey) ? Self.folder : library?.folder(containing: pageKey)
    }

    func chapters(of folderID: UUID) -> [ChapterAdvance.Chapter] {
        guard folderID == Self.folder.id else { return library?.chapters(of: folderID) ?? [] }
        return [ChapterAdvance.Chapter(key: Self.keys[0]), ChapterAdvance.Chapter(key: Self.keys[1], isLink: !linkFetched)]
    }

    func load(_ pageKey: UUID) -> SpeechSession? {
        guard let index = Self.keys.firstIndex(of: pageKey) else { return library?.load(pageKey) }
        return index == 1 && !linkFetched ? nil : sessions[index]
    }

    func fetch(_ pageKey: UUID) async -> Bool {
        guard pageKey == Self.keys[1] else { return await library?.fetch(pageKey) ?? false }
        return await fetchLink()
    }

    func pageFinished(key: UUID) {
        guard !Self.keys.contains(key) else { return }
        library?.pageFinished(key: key)
    }
}

/// One JSON object per line in `Application Support/LockedFetchProbe/probe.jsonl`, and in the
/// unified log.
private struct ProbeLog {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LockedFetchProbe", isDirectory: true)
    }()
    private static let console = Logger(subsystem: "com.jimmyyao.Reader", category: "LockedFetchProbe")

    /// A new run: the last run's files go.
    static func startingRun() -> ProbeLog {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ProbeLog()
    }

    func callAsFunction(_ event: String, _ fields: [String: Any] = [:]) {
        var line = fields
        line["t"] = (Date().timeIntervalSince1970 * 1000).rounded() / 1000
        line["ev"] = event
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        Self.console.notice("\(String(decoding: data, as: UTF8.self), privacy: .public)")
        let url = Self.directory.appendingPathComponent("probe.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
    }

    func save(_ text: String, as name: String) {
        try? Data(text.utf8).write(to: Self.directory.appendingPathComponent(name), options: .atomic)
    }
}
#endif
