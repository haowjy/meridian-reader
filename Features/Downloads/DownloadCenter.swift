import Foundation
import Observation

/// Downloads (decision D16): a page, a folder, a book or a series made ready to play offline, its
/// text fetched (a link page is saved in place) and its whole audio rendered ahead in the download
/// voice. The list is kept on the device (`DownloadListStore`) and worked through in order, one
/// page at a time.
///
/// It renders nothing itself: each page's audio is an ordinary bake job in the one render queue
/// (`LocalTTSCoordinator.queueDownload`), so the article playing and the chapter staged after it
/// always go first, bake-ahead holds on a hot phone and in Low Power Mode apply, and in the
/// background a download's job parks (only the playing article renders there, in bursts,
/// `RenderAdmission`). The next page is handed over only while the app is in front: in the
/// background nothing new starts, and a fetch needs a window.
///
/// The voice each download's audio is in comes from the audio cache, not from here, so a voice
/// change shows at once (`DownloadOverview`'s *Different voice*), and *Re-download* or *Keep*
/// settles it.
@MainActor
@Observable
final class DownloadCenter {
    /// The page being fetched or rendered now.
    struct Active: Equatable {
        enum Phase: Equatable {
            case fetching
            /// Its bake job is queued, with the paragraphs it renders.
            case rendering([String])
        }

        var recordID: UUID
        var key: UUID
        var phase: Phase
    }

    enum Request: Equatable {
        /// A new download, or one asked for again (queued afresh).
        case added
        /// A paused download goes on.
        case resumed
        /// It is already downloading.
        case alreadyQueued
        /// Nothing in it plays (an empty folder, a finished book).
        case nothingToDownload
    }

    private(set) var records: [DownloadRecord] {
        didSet { store.save(records) }
    }
    private(set) var active: Active?

    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored let tts: LocalTTSCoordinator
    @ObservationIgnored private let store: DownloadListStore
    @ObservationIgnored private let runState: AppRunState
    /// A link page's text: loaded out of sight and extracted (`URLPageFetcher` in the app).
    @ObservationIgnored private let fetch: (URL) async throws -> PageContent
    /// The one save path (`ArticleSaveCoordinator`), returning the saved page's key.
    @ObservationIgnored private let save: (ReaderArticle) throws -> UUID
    /// Whether a page is bound to the playback session (playing, paused or finished).
    @ObservationIgnored private let isListening: (UUID) -> Bool
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var checkScheduled = false
    /// Times a page's job went back into the queue after leaving it unfinished.
    @ObservationIgnored private var requeued: [UUID: Int] = [:]
    @ObservationIgnored private var runStateObserver: NSObjectProtocol?

    init(library: LibraryStore, tts: LocalTTSCoordinator, store: DownloadListStore = DownloadListStore(),
         runState: AppRunState = .shared, fetch: @escaping (URL) async throws -> PageContent,
         save: @escaping (ReaderArticle) throws -> UUID, isListening: @escaping (UUID) -> Bool = { _ in false }) {
        self.library = library
        self.tts = tts
        self.store = store
        self.runState = runState
        self.fetch = fetch
        self.save = save
        self.isListening = isListening
        records = store.load()
    }

    /// Once the launch's library maintenance is done (pages it merges or rebuilds are settled):
    /// downloads of things no longer in the Library go, and the list carries on where it was.
    /// From then on, each stored library edit drops the downloads it took out of the Library.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        tts.renderObserver = self
        library.editStored = { [weak self] in self?.dropWhatLeftTheLibrary() }
        runStateObserver = NotificationCenter.default.addObserver(forName: AppRunState.didChange, object: runState,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }
        dropWhatLeftTheLibrary()
        advance()
    }

    // MARK: - What the list shows

    var overview: DownloadOverview {
        let cache = tts.audioCache
        return DownloadOverview(records: records, active: activeProgress, currentVoice: tts.downloadVoice,
                                rendersDownloads: tts.wantsLocalBake) { cache.renderedVoice(articleID: $0) }
    }

    /// The progress line's value: nil while nothing runs (`DownloadOverview.progress`).
    var progress: Double? {
        DownloadOverview.progress(records: records, active: activeProgress, rendersDownloads: tts.wantsLocalBake)
    }

    /// The page fetched or rendering now and how much of its audio is ready.
    private var activeProgress: DownloadOverview.Active? {
        active.map { active in
            switch active.phase {
            case .fetching:
                DownloadOverview.Active(recordID: active.recordID, key: active.key, fraction: 0, isFetching: true)
            case .rendering(let paragraphs):
                DownloadOverview.Active(recordID: active.recordID, key: active.key,
                                        fraction: tts.downloadFraction(cacheKey: active.key, paragraphs: paragraphs))
            }
        }
    }

    func record(for target: DownloadRecord.Target) -> DownloadRecord? {
        records.first { $0.target == target }
    }

    /// The download covering `target` is still to finish (row menus offer no second *Download*).
    func isQueued(_ target: DownloadRecord.Target) -> Bool {
        record(for: target)?.hasQueuedPages == true
    }

    /// What a Download button for `target` shows: ready to ask, how far while queued, or
    /// downloaded (`isDownloaded`, which the caller has from `isDownloaded(_:)`).
    func state(of target: DownloadRecord.Target, isDownloaded: Bool) -> DownloadState {
        if let record = record(for: target), record.hasQueuedPages {
            return .downloading(fraction: DownloadOverview.fraction(of: record, active: activeProgress))
        }
        return isDownloaded ? .downloaded : .available
    }

    /// The page's audio is downloaded (its rows' mark): `DownloadOverview.isDownloaded`, the
    /// Downloads list's own rule.
    func isDownloaded(_ page: Page) -> Bool {
        isDownloaded([page.listenKey])
    }

    /// Every page a download of `folder` covers is downloaded; `pages`: its pages in play order
    /// (a row passes what it already holds, so this fetches nothing).
    func isDownloaded(_ folder: Folder, pages: [Page]) -> Bool {
        isDownloaded(pages.filter { Self.covers($0, in: folder) }.map(\.listenKey))
    }

    private func isDownloaded(_ keys: [UUID]) -> Bool {
        let cache = tts.audioCache
        return DownloadOverview.isDownloaded(keys, records: records, currentVoice: tts.downloadVoice) {
            cache.renderedVoice(articleID: $0)
        }
    }

    // MARK: - Asking for downloads

    func download(_ page: Page) -> Request {
        request(.page(page.listenKey))
    }

    func download(_ folder: Folder) -> Request {
        request(.folder(folder.id))
    }

    private func request(_ target: DownloadRecord.Target) -> Request {
        let existing = record(for: target)
        if let existing, existing.hasQueuedPages {
            guard existing.isPaused else { return .alreadyQueued }
            withRecord(existing.id) { $0.isPaused = false }
            advance()
            return .resumed
        }
        guard let (title, keys) = pages(of: target), !keys.isEmpty else { return .nothingToDownload }
        if let existing {
            withRecord(existing.id) {
                $0.title = title
                $0.requeue(keys)
            }
        } else {
            records.append(DownloadRecord(target: target, title: title, addedAt: Date(), entries: keys.map { .init(key: $0) }))
        }
        advance()
        return .added
    }

    /// The pages a download covers, in play order: a page itself; a book's or series' chapters
    /// that play and aren't finished; any other folder's own pages in its sort.
    private func pages(of target: DownloadRecord.Target) -> (String, [UUID])? {
        switch target {
        case .page(let key):
            guard let page = library.page(key: key) else { return nil }
            return (page.title, [page.listenKey])
        case .folder(let id):
            guard let folder = library.folder(id: id) else { return nil }
            let pages = library.pages(in: folder).filter { Self.covers($0, in: folder) }
            return (folder.name, pages.map(\.listenKey))
        }
    }

    /// A folder's download covers its pages that play; a book's or series' only while unfinished
    /// (D7 trims finished chapters' audio).
    static func covers(_ page: Page, in folder: Folder) -> Bool {
        !page.skipsInPlayback && !(folder.kind.isBookOrSeries && page.finishedAt != nil)
    }

    /// The list's line, the Library's (`LibraryQueries`): a download is listed while what it
    /// downloads is in the Library. A page removed from it (still kept for what plays) isn't.
    private func isInLibrary(_ target: DownloadRecord.Target) -> Bool {
        switch target {
        case .page(let key): library.page(key: key)?.isInLibrary == true
        case .folder(let id): library.folder(id: id) != nil
        }
    }

    /// Downloads of what left the Library (a page removed, a page or folder deleted) leave the
    /// list, and the page rendering for one stops. Their audio is the library's to keep or
    /// delete: a removed page's is ephemeral already, a deleted one's is gone.
    private func dropWhatLeftTheLibrary() {
        let gone = Set(records.filter { !isInLibrary($0.target) }.map(\.id))
        guard !gone.isEmpty else { return }
        if let active, gone.contains(active.recordID) { stopActive() }
        records.removeAll { gone.contains($0.id) }
        advance()
    }

    // MARK: - The list's actions

    func setPaused(_ id: UUID, _ paused: Bool) {
        guard records.contains(where: { $0.id == id && $0.isPaused != paused }) else { return }
        withRecord(id) { $0.isPaused = paused }
        if paused, active?.recordID == id { stopActive() }
        advance()
    }

    /// Pause or resume everything still queued.
    func setAllPaused(_ paused: Bool) {
        updateRecords { records in
            for index in records.indices where records[index].hasQueuedPages { records[index].isPaused = paused }
        }
        if paused, active != nil { stopActive() }
        advance()
    }

    /// Takes the download off the list, and its pages' audio off the phone (*Remove*), except the
    /// audio listening needs (`purgeAudio`) and that of pages another download covers.
    func remove(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        if active?.recordID == id { stopActive() }
        let record = records.remove(at: index)
        let kept = Set(records.flatMap { $0.entries.map(\.key) })
        purgeAudio(record.entries.map(\.key).filter { !kept.contains($0) })
        advance()
    }

    /// *Re-download*: every page renders again in the download voice (the older voice's audio
    /// plays until each paragraph is replaced).
    func redownload(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }),
              let (title, keys) = pages(of: record.target), !keys.isEmpty else { return }
        if active?.recordID == id { stopActive() }
        withRecord(id) {
            $0.title = title
            $0.requeue(keys)
        }
        advance()
    }

    /// *Keep*: audio in `voice` counts as done for this download.
    func keep(_ id: UUID, voice: String) {
        withRecord(id) { $0.keptVoice = voice }
    }

    /// *Delete Downloads* on a page's row: its audio goes (unless listening needs it,
    /// `purgeAudio`), and so does a download of just that page; a folder's download covering it
    /// no longer counts it as done (`forgetDone`).
    func deleteDownloads(of page: Page) {
        records.removeAll { $0.target == .page(page.listenKey) }
        if active?.key == page.listenKey { stopActive() }
        forgetDone(purgeAudio([page.listenKey]))
        advance()
    }

    /// *Delete Downloads* on a folder: its pages' audio (unless listening needs it, `purgeAudio`),
    /// and its download; downloads of one of those pages no longer count it as done.
    func deleteDownloads(of folder: Folder) {
        if let record = record(for: .folder(folder.id)), active?.recordID == record.id { stopActive() }
        records.removeAll { $0.target == .folder(folder.id) }
        forgetDone(purgeAudio(library.pages(in: folder).map(\.listenKey)))
        advance()
    }

    /// After *Delete Downloads* took `purged`'s audio, no download counts those pages as done: a
    /// download of just one of them goes, and a folder's download puts one back in its queue
    /// while it still covers the page (`covers`), else takes it off its list. So the Downloads
    /// list and the rows agree that the folder isn't downloaded.
    private func forgetDone(_ purged: [UUID]) {
        let purged = Set(purged)
        guard !purged.isEmpty else { return }
        updateRecords { records in
            records.removeAll { if case .page(let key) = $0.target { purged.contains(key) } else { false } }
            for index in records.indices {
                guard case .folder(let id) = records[index].target else { continue }
                let folder = library.folder(id: id)
                records[index].entries = records[index].entries.compactMap { entry in
                    guard entry.state == .done, purged.contains(entry.key) else { return entry }
                    guard let folder, let page = library.page(key: entry.key), page.folder === folder,
                          Self.covers(page, in: folder) else { return nil }
                    return DownloadRecord.Entry(key: entry.key)
                }
            }
            records.removeAll { $0.entries.isEmpty }
        }
    }

    // MARK: - Changing the list

    /// Changes the list through a copy assigned once, so `Downloads.json` is written once per
    /// change (and not at all when nothing changed).
    private func updateRecords(_ change: (inout [DownloadRecord]) -> Void) {
        var copy = records
        change(&copy)
        if copy != records { records = copy }
    }

    /// Changes the download `id` (`updateRecords`) and returns what `change` does; nil when it
    /// isn't on the list.
    @discardableResult
    private func withRecord<Result>(_ id: UUID, _ change: (inout DownloadRecord) -> Result) -> Result? {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        var result: Result?
        updateRecords { result = change(&$0[index]) }
        return result
    }

    // MARK: - What listening needs

    /// Listening needs `key`'s audio and its render job now: it is the page bound to the session
    /// (playing, paused or finished), or the chapter staged to play after it. Nothing Downloads
    /// does takes either away.
    private func needsAudio(_ key: UUID) -> Bool {
        isListening(key) || tts.synthQueue.stagedCacheKey == key
    }

    /// Deletes the audio, pending render and queued renders of `keys`' pages, except what
    /// listening needs (`needsAudio`): that audio stays for the session, saved or ephemeral as
    /// the library keeps its page. Returns the keys whose audio went.
    @discardableResult
    private func purgeAudio(_ keys: [UUID]) -> [UUID] {
        var purged: [UUID] = []
        for key in keys where !needsAudio(key) {
            guard let page = library.page(key: key) else { continue }
            library.deleteDownloads(page)
            purged.append(key)
        }
        return purged
    }

    // MARK: - Working through the list

    /// The page whose turn it is: the first queued page of the first download not paused.
    private func nextQueued() -> (recordID: UUID, key: UUID)? {
        for record in records where !record.isPaused {
            if let entry = record.entries.first(where: { $0.state == .queued }) { return (record.id, entry.key) }
        }
        return nil
    }

    private func advance() {
        guard isStarted, runner == nil, active == nil, runState.phase != .background else { return }
        runner = Task { [weak self] in
            await self?.runQueue()
            self?.runner = nil
        }
    }

    /// Hands pages to the render queue until one is rendering (its `bakeCompleted` brings the
    /// next), the list is done, or no voice renders downloads.
    private func runQueue() async {
        while runState.phase != .background, tts.wantsLocalBake, active == nil, let next = nextQueued() {
            let (recordID, key) = (next.recordID, next.key)
            guard let page = library.page(key: key), page.isInLibrary else {
                finish(recordID, key, .failed, String(localized: "It’s no longer in the Library"))
                continue
            }
            var pageKey = key
            if page.isLink {
                active = Active(recordID: recordID, key: key, phase: .fetching)
                let saved = await fetchAndSave(page)
                // Paused or removed while it loaded: what it fetched isn't saved.
                guard active == Active(recordID: recordID, key: key, phase: .fetching) else { continue }
                active = nil
                switch saved {
                case .failure(let failure):
                    finish(recordID, key, .failed, failure.message)
                    continue
                case .success(let newKey):
                    pageKey = newKey
                    if newKey != key { rekeyEntry(recordID, from: key, to: newKey) }
                }
            }
            guard let page = library.page(key: pageKey), page.hasText else {
                finish(recordID, pageKey, .failed, String(localized: "Couldn’t get its text"))
                continue
            }
            let paragraphs = page.listenDocument().paragraphs
            guard !paragraphs.isEmpty else {
                finish(recordID, pageKey, .failed, String(localized: "Nothing to listen to"))
                continue
            }
            switch tts.queueDownload(cacheKey: pageKey, paragraphs: paragraphs) {
            case .ready:
                finish(recordID, pageKey, .done)
            case .speaksLive:
                finish(recordID, pageKey, .speaksLive)
            case .held:
                finish(recordID, pageKey, .failed, String(localized: "Couldn’t render it now"))
            case .notRendering:
                return
            case .rendering:
                active = Active(recordID: recordID, key: pageKey, phase: .rendering(paragraphs))
                ListenTimingLog.log("download_page", ["key": ListenTimingLog.shortKey(pageKey), "paragraphs": paragraphs.count])
            }
        }
    }

    private struct FetchFailure: Error {
        var message: String
    }

    /// A link page's text, fetched and saved in place (the one save path, which also queues its
    /// bake). Returns the saved page's key.
    private func fetchAndSave(_ page: Page) async -> Result<UUID, FetchFailure> {
        guard let url = page.url else { return .failure(FetchFailure(message: String(localized: "It has no address"))) }
        // Read before the fetch: the page may be deleted while it loads.
        let title = page.title
        let key = page.listenKey
        let article: ReaderArticle
        if page.hasText {
            // Played before: the text it was played from.
            var cached = ReaderArticle(page: page)
            if cached.document.isEmpty { cached.document = page.listenDocument() }
            article = cached
        } else {
            do {
                let content = try await fetch(url)
                let extracted = ExtractedArticle(title: content.title.isEmpty ? title : content.title,
                                                 siteName: content.siteName, cleanedHTML: content.bodyHTML,
                                                 plainText: content.plainText, excerpt: content.excerpt)
                article = library.readerArticle(url: url, extracted: extracted, document: content.document)
            } catch {
                ListenTimingLog.log("download_fetch_failed", ["key": ListenTimingLog.shortKey(key),
                                                              "err": error.localizedDescription])
                return .failure(FetchFailure(message: String(localized: "Couldn’t get the page")))
            }
        }
        guard !article.document.paragraphs.isEmpty else {
            return .failure(FetchFailure(message: String(localized: "Nothing to listen to")))
        }
        do {
            return .success(try save(article))
        } catch {
            return .failure(FetchFailure(message: String(localized: "Couldn’t save it")))
        }
    }

    private func finish(_ recordID: UUID, _ key: UUID, _ state: DownloadRecord.PageState, _ failure: String? = nil) {
        let finished = withRecord(recordID) { record -> Bool in
            guard let e = record.entries.firstIndex(where: { $0.key == key && $0.state == .queued }) else { return false }
            record.entries[e].state = state
            record.entries[e].failure = failure
            return true
        }
        guard finished == true else { return }
        requeued[key] = nil
        if active?.recordID == recordID, active?.key == key { active = nil }
    }

    private func rekeyEntry(_ recordID: UUID, from old: UUID, to new: UUID) {
        withRecord(recordID) { record in
            guard let e = record.entries.firstIndex(where: { $0.key == old }) else { return }
            record.entries[e].key = new
            if case .page(old) = record.target { record.target = .page(new) }
        }
    }

    /// The page rendering now stops (paused, removed): its job leaves the queue, unless listening
    /// needs it (`needsAudio`). It stays queued in its download.
    private func stopActive() {
        if let active, case .rendering = active.phase, !needsAudio(active.key) { tts.cancelDownload(cacheKey: active.key) }
        active = nil
    }

    /// Looks at the page rendering now: done once every paragraph with words has audio in the
    /// download voice. A job that left the queue unfinished (paragraphs the voice and Apple's both
    /// failed on, or a job something else dropped) goes back once, then the page is marked failed.
    private func checkActive() {
        guard let active, case .rendering(let paragraphs) = active.phase else { return advance() }
        guard tts.wantsLocalBake else {
            stopActive()
            return
        }
        let missing = tts.missingDownloadParagraphs(cacheKey: active.key, paragraphs: paragraphs)
        if missing == 0 {
            finish(active.recordID, active.key, .done)
            return advance()
        }
        guard tts.usesLocalEngine, !tts.isHeldForLaunch, !tts.hasDownloadJob(cacheKey: active.key) else { return }
        if requeued[active.key, default: 0] < 1 {
            requeued[active.key, default: 0] += 1
            if tts.queueDownload(cacheKey: active.key, paragraphs: paragraphs) == .rendering { return }
        }
        let message = missing == 1 ? String(localized: "1 paragraph couldn’t be rendered")
            : String(localized: "\(missing) paragraphs couldn’t be rendered")
        finish(active.recordID, active.key, .failed, message)
        advance()
    }

    /// Render queue events arrive inside the queue's work: look once it is done.
    private func scheduleCheck() {
        guard isStarted, !checkScheduled else { return }
        checkScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            checkScheduled = false
            checkActive()
        }
    }
}

extension DownloadCenter: RenderQueueObserver {
    func bakeCompleted(cacheKey: UUID) { scheduleCheck() }
    func renderStateChanged() { scheduleCheck() }
}
