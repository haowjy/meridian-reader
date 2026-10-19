import Foundation
import Observation

/// Downloads (decision D16): a page, a folder, a book or a followed story made ready to play
/// offline, its text fetched (a link page gets its text in place, through Follow's one fetch
/// queue: `FollowCenter.fill`) and its whole audio rendered ahead in the download voice. The list
/// is kept on the device (`DownloadListStore`) and worked through in order, one page at a time. A
/// folder's download is its Download toggle: on, the pages added to the folder later join it
/// (`takeInNewPages`); off, nothing new joins and what is downloaded stays.
///
/// It renders nothing itself: each page's audio is an ordinary bake job in the one render queue
/// (`DownloadRendering.queueDownload`), so the article playing and the chapter staged after it
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
            /// Its bake job is queued, with the paragraphs it renders (never none).
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
        /// Nothing in it plays (a finished book): a page's download isn't made.
        case nothingToDownload
        /// A folder's switch is on, with nothing to download yet (a story you're caught up on):
        /// the pages added later download.
        case waitingForNew
    }

    private(set) var records: [DownloadRecord] {
        didSet { store.save(records) }
    }
    private(set) var active: Active?

    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored private let rendering: any DownloadRendering
    @ObservationIgnored private let store: DownloadListStore
    @ObservationIgnored private let runState: AppRunState
    /// A link page's text, fetched and stored in place (`FollowCenter.fill` in the app): why it
    /// couldn't be had, nil once it is in.
    @ObservationIgnored private let fill: (Page) async -> String?
    /// Listening needs a page's audio and its render job now: it is the page bound to the session
    /// (playing, paused or finished), or the chapter staged to play after it. Nothing Downloads
    /// does takes either away.
    @ObservationIgnored private let needsAudio: (UUID) -> Bool
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var checkScheduled = false
    /// Times a page's job went back into the queue after leaving it unfinished.
    @ObservationIgnored private var requeued: [UUID: Int] = [:]
    @ObservationIgnored private var runStateObserver: NSObjectProtocol?

    /// The composition tells it of each render-queue change (`scheduleCheck`) and each stored
    /// library edit (`followLibrary`); it acts on them once started.
    init(library: LibraryStore, rendering: any DownloadRendering, store: DownloadListStore = DownloadListStore(),
         runState: AppRunState = .shared, fill: @escaping (Page) async -> String?,
         needsAudio: @escaping (UUID) -> Bool) {
        self.library = library
        self.rendering = rendering
        self.store = store
        self.runState = runState
        self.fill = fill
        self.needsAudio = needsAudio
        records = store.load()
    }

    /// Once the launch's library maintenance is done (pages it merges or rebuilds are settled):
    /// downloads of things no longer in the Library go, folders with Download on take in their new
    /// pages, and the list carries on where it was. From then on, each stored library edit does
    /// the same (`followLibrary`).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        runStateObserver = NotificationCenter.default.addObserver(forName: AppRunState.didChange, object: runState,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }
        followLibrary()
    }

    // MARK: - What the list shows

    var overview: DownloadOverview {
        DownloadOverview(records: records, active: activeProgress, currentVoice: rendering.downloadVoice,
                         rendersDownloads: rendering.wantsLocalBake) { rendering.renderedVoice(of: $0) }
    }

    /// The progress line's value: nil while nothing runs (`DownloadOverview.progress`).
    var progress: Double? {
        DownloadOverview.progress(records: records, active: activeProgress, rendersDownloads: rendering.wantsLocalBake)
    }

    /// The page fetched or rendering now and how much of its audio is ready.
    private var activeProgress: DownloadOverview.Active? {
        guard let active else { return nil }
        guard case .rendering(let paragraphs) = active.phase else {
            return DownloadOverview.Active(recordID: active.recordID, key: active.key, fraction: 0, isFetching: true)
        }
        let missing = rendering.missingDownloadParagraphs(cacheKey: active.key, paragraphs: paragraphs)
        return DownloadOverview.Active(recordID: active.recordID, key: active.key,
                                       fraction: Double(paragraphs.count - missing) / Double(paragraphs.count))
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
        DownloadOverview.isDownloaded(keys, records: records, currentVoice: rendering.downloadVoice) {
            rendering.renderedVoice(of: $0)
        }
    }

    /// The folder's Download toggle is on: its pages download, and so do the ones added later.
    func isOn(_ folder: Folder) -> Bool {
        record(for: .folder(folder.id))?.followsFolder == true
    }

    // MARK: - Asking for downloads

    /// A page's own Download. A page whose downloads were deleted from its folder's download
    /// (P8) is taken back into it too.
    func download(_ page: Page) -> Request {
        if let folder = page.folder, let record = record(for: .folder(folder.id)), record.deleted.contains(page.listenKey) {
            withRecord(record.id) { $0.deleted.removeAll { $0 == page.listenKey } }
            takeInNewPages()
        }
        return request(.page(page.listenKey))
    }

    /// A folder's Download, its toggle turned on: every page it covers is queued (its deleted
    /// ones too), and the pages added later join.
    func download(_ folder: Folder) -> Request {
        request(.folder(folder.id))
    }

    /// The folder's Download toggle turned off: nothing new joins and what waits stops; what is
    /// downloaded stays, and the Downloads list keeps it.
    func turnOff(_ folder: Folder) {
        guard let record = record(for: .folder(folder.id)), record.followsFolder else { return }
        if active?.recordID == record.id { stopActive() }
        updateRecords { records in
            guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
            records[index].followsFolder = false
            records[index].entries.removeAll { $0.state == .queued }
            if records[index].entries.isEmpty { records.remove(at: index) }
        }
        advance()
    }

    private func request(_ target: DownloadRecord.Target) -> Request {
        let existing = record(for: target)
        if let existing, existing.hasQueuedPages {
            guard existing.isPaused else { return .alreadyQueued }
            withRecord(existing.id) { $0.isPaused = false }
            advance()
            return .resumed
        }
        guard let (title, keys) = pages(of: target) else { return .nothingToDownload }
        // A folder's switch turns on with nothing in it yet; a page's download needs the page.
        guard !keys.isEmpty || target.isFolder else { return .nothingToDownload }
        if let existing {
            withRecord(existing.id) {
                $0.title = title
                $0.requeue(keys)
            }
        } else {
            records.append(DownloadRecord(target: target, title: title, addedAt: Date(), entries: keys.map { .init(key: $0) }))
        }
        advance()
        return keys.isEmpty ? .waitingForNew : .added
    }

    /// The pages a download covers, in play order: a page itself; a book's or story's chapters
    /// that play and aren't finished; any other folder's own pages in its sort.
    private func pages(of target: DownloadRecord.Target) -> (String, [UUID])? {
        switch target {
        case .page(let key):
            guard let page = library.page(key: key) else { return nil }
            return (page.lineOne, [page.listenKey])
        case .folder(let id):
            guard let folder = library.folder(id: id) else { return nil }
            let pages = library.pages(in: folder).filter { Self.covers($0, in: folder) }
            return (folder.name, pages.map(\.listenKey))
        }
    }

    /// A folder's download covers its pages that play; a book's or story's only while unfinished
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

    /// After a library edit: downloads of what left the Library (a page removed, a page or folder
    /// deleted) leave the list, and the page rendering for one stops; so does a folder download's
    /// page that left the Library, whose entry then fails as no longer in it. Their audio is the
    /// library's to keep or delete (a removed page's is ephemeral already, a deleted one's is
    /// gone). Folders with Download on take in the pages added to them (`takeInNewPages`).
    func followLibrary() {
        guard isStarted else { return }
        let gone = Set(records.filter { !isInLibrary($0.target) }.map(\.id))
        if let active, gone.contains(active.recordID) || !isInLibrary(.page(active.key)) { stopActive() }
        updateRecords { records in records.removeAll { gone.contains($0.id) } }
        takeInNewPages()
        advance()
    }

    /// Each folder with Download on: its pages not in its download yet, and not deleted from it,
    /// join it at the end, queued.
    private func takeInNewPages() {
        let joining = records.compactMap { record -> (UUID, [UUID])? in
            guard record.followsFolder, case .folder(let id) = record.target, let folder = library.folder(id: id) else { return nil }
            let new = record.joining(library.pages(in: folder).filter { Self.covers($0, in: folder) }.map(\.listenKey))
            return new.isEmpty ? nil : (record.id, new)
        }
        guard !joining.isEmpty else { return }
        updateRecords { records in
            for (id, keys) in joining {
                guard let index = records.firstIndex(where: { $0.id == id }) else { continue }
                records[index].entries += keys.map { DownloadRecord.Entry(key: $0) }
            }
        }
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

    /// *Delete Downloads* on a page's row: the page leaves every download (`forget`) and its audio
    /// goes (unless listening needs it, `purgeAudio`). It stays deleted: a folder's download no
    /// longer lists it, so the folder shows as not all downloaded, and nothing renders it again
    /// until it is played or Download is tapped (the page's, or the folder's, which lists the
    /// folder's pages again).
    func deleteDownloads(of page: Page) {
        forget([page.listenKey])
        if let folder = page.folder, let record = record(for: .folder(folder.id)) {
            withRecord(record.id) { $0.deleted.append(page.listenKey) }
        }
        purgeAudio([page.listenKey])
        advance()
    }

    /// *Delete Downloads* on a folder: its download goes (its toggle off), its pages leave every
    /// other download (`forget`), and their audio goes (unless listening needs it, `purgeAudio`).
    func deleteDownloads(of folder: Folder) {
        if let record = record(for: .folder(folder.id)), active?.recordID == record.id { stopActive() }
        records.removeAll { $0.target == .folder(folder.id) }
        let keys = library.pages(in: folder).map(\.listenKey)
        forget(keys)
        purgeAudio(keys)
        advance()
    }

    /// `keys`' pages leave every download, whatever their turn (queued, done or failed): a download
    /// of just one of them goes, and a folder's download drops them from its list. One of them
    /// rendering for a download stops. So the Downloads list and the rows agree, and no download
    /// renders a page whose downloads were deleted.
    private func forget(_ keys: [UUID]) {
        let keys = Set(keys)
        if let active, keys.contains(active.key) { stopActive() }
        for key in keys { requeued[key] = nil }
        updateRecords { records in
            for index in records.indices { records[index].entries.removeAll { keys.contains($0.key) } }
            // A folder's switch stays on with nothing left in it: later pages still join.
            records.removeAll { $0.entries.isEmpty && !$0.followsFolder }
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

    /// Deletes the audio, pending render and queued renders of `keys`' pages, except what
    /// listening needs (`needsAudio`): that audio stays for the session, saved or ephemeral as
    /// the library keeps its page.
    private func purgeAudio(_ keys: [UUID]) {
        for key in keys where !needsAudio(key) {
            if let page = library.page(key: key) { library.deleteDownloads(page) }
        }
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
        while runState.phase != .background, rendering.wantsLocalBake, active == nil, let next = nextQueued() {
            let (recordID, key) = (next.recordID, next.key)
            guard let page = library.page(key: key), page.isInLibrary else {
                finish(recordID, key, .failed, String(localized: "It’s no longer in the Library"))
                continue
            }
            if page.isLink {
                active = Active(recordID: recordID, key: key, phase: .fetching)
                let failure = await fill(page)
                // Paused, removed or its downloads deleted while it loaded: it isn't rendered.
                guard active == Active(recordID: recordID, key: key, phase: .fetching) else { continue }
                active = nil
                if let failure {
                    finish(recordID, key, .failed, failure)
                    continue
                }
            }
            guard let page = library.page(key: key), page.isInLibrary, page.hasText else {
                finish(recordID, key, .failed, String(localized: "Couldn’t get its text"))
                continue
            }
            let paragraphs = page.listenDocument().paragraphs
            guard !paragraphs.isEmpty else {
                finish(recordID, key, .failed, String(localized: "Nothing to listen to"))
                continue
            }
            switch rendering.queueDownload(cacheKey: key, paragraphs: paragraphs) {
            case .ready:
                finish(recordID, key, .done)
            case .speaksLive:
                finish(recordID, key, .speaksLive)
            case .held:
                finish(recordID, key, .failed, String(localized: "Couldn’t render it now"))
            case .notRendering:
                return
            case .rendering:
                active = Active(recordID: recordID, key: key, phase: .rendering(paragraphs))
                ListenTimingLog.log("download_page", ["key": ListenTimingLog.shortKey(key), "paragraphs": paragraphs.count])
            }
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

    /// The page rendering now stops (paused, removed): its job leaves the queue, unless listening
    /// needs it (`needsAudio`). It stays queued in its download.
    private func stopActive() {
        if let active, case .rendering = active.phase, !needsAudio(active.key) { rendering.removeBakeJob(cacheKey: active.key) }
        active = nil
    }

    /// Looks at the page rendering now: done once every paragraph with words has audio in the
    /// download voice. A job that left the queue unfinished (paragraphs the voice and Apple's both
    /// failed on, or a job something else dropped) goes back once, then the page is marked failed.
    private func checkActive() {
        guard let active, case .rendering(let paragraphs) = active.phase else { return advance() }
        guard rendering.wantsLocalBake else {
            stopActive()
            return
        }
        let missing = rendering.missingDownloadParagraphs(cacheKey: active.key, paragraphs: paragraphs)
        if missing == 0 {
            finish(active.recordID, active.key, .done)
            return advance()
        }
        guard rendering.bakeJobEnded(cacheKey: active.key) else { return }
        if requeued[active.key, default: 0] < 1 {
            requeued[active.key, default: 0] += 1
            if rendering.queueDownload(cacheKey: active.key, paragraphs: paragraphs) == .rendering { return }
        }
        let message = missing == 1 ? String(localized: "1 paragraph couldn’t be rendered")
            : String(localized: "\(missing) paragraphs couldn’t be rendered")
        finish(active.recordID, active.key, .failed, message)
        advance()
    }

    /// The render queue or the app's phase may have moved: look at the page rendering once the
    /// caller's work is done (render-queue events arrive inside the queue's work).
    func scheduleCheck() {
        guard isStarted, !checkScheduled else { return }
        checkScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            checkScheduled = false
            checkActive()
        }
    }
}

/// What downloads ask of the render queue (`LocalTTSCoordinator+Downloads` answers).
@MainActor
protocol DownloadRendering {
    /// The voice downloads render in, as a cache voice key.
    var downloadVoice: String? { get }
    /// An on-device voice is selected, so downloads render.
    var wantsLocalBake: Bool { get }
    /// The voice most of `key`'s audio is in.
    func renderedVoice(of key: UUID) -> String?
    /// Queues `paragraphs` of `cacheKey` to render in full in the download voice.
    func queueDownload(cacheKey: UUID, paragraphs: [String]) -> DownloadQueueing
    /// Paragraphs that still need audio in the download voice; a view reading it follows the render.
    func missingDownloadParagraphs(cacheKey: UUID, paragraphs: [String]) -> Int
    /// `cacheKey`'s bake job has left the queue, done or not: it isn't queued, nor waiting for the
    /// engine to load or the launch's hold to end.
    func bakeJobEnded(cacheKey: UUID) -> Bool
    /// Takes `cacheKey`'s bake job out of the queue and the pending jobs; its audio stays.
    func removeBakeJob(cacheKey: UUID)
}

enum DownloadQueueing: Equatable {
    /// Its bake job is queued (or waits for the engine to load); its end is a render-queue change.
    case rendering
    /// Every paragraph that has words is rendered in the download voice already.
    case ready
    /// The engine doesn't speak its language: Apple's voice speaks it, live.
    case speaksLive
    /// Its audio waits for library work an earlier launch couldn't finish (`ArticleAudioCache.held`).
    case held
    /// No on-device voice that renders downloads is selected.
    case notRendering
}
