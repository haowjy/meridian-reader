import Foundation
import Observation

/// Downloads (decision D16): a page, a folder, a book or a followed story made ready to play
/// offline, its text fetched (a link page gets its text in place, through Follow's one fetch
/// queue: `FollowCenter.fill`) and its whole audio rendered ahead in the download voice. The list
/// is kept on the device (`DownloadListStore`) and worked through in order, one page at a time. A
/// folder's download is its Download toggle: on, the pages added to the folder later join it
/// (`takeInNewArticles`); off, nothing new joins and what is downloaded stays.
///
/// It renders nothing itself: each page's audio is an ordinary bake job in the one render queue
/// (`DownloadRendering.queueDownload`), so the article playing and the chapter staged after it
/// always go first, bake-ahead holds on a hot phone and in Low Power Mode apply, and in the
/// background the playing article renders first, in bursts (`RenderAdmission`); while it is
/// safely ahead and audio plays on the CPU route, a download's job takes the same one-thread
/// worker, and the next page is handed over then too (C94; a link page's fetch waits for the
/// foreground). Paused or stopped in the background, nothing goes on (iOS suspends the app).
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
        /// A folder's toggle is on, with nothing to download yet (a story you're caught up on):
        /// the pages added later download.
        case waitingForNew
    }

    private(set) var records: [DownloadRecord] {
        didSet { store.save(records); audioKnown = [:] }
    }
    private(set) var active: Active? { didSet { audioKnown = [:] } }
    /// Pages known to have audio on disk (`hasDownloads`), so a menu asks the disk once per page
    /// until a download changes (C98).
    @ObservationIgnored private var audioKnown: [UUID: Bool] = [:]

    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored private let rendering: any DownloadRendering
    @ObservationIgnored private let store: DownloadListStore
    @ObservationIgnored private let runState: AppRunState
    /// A link page's text, fetched and stored in place (`FollowCenter.fill` in the app): why it
    /// couldn't be had, nil once it is in.
    @ObservationIgnored private let fill: (Article) async -> String?
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
         runState: AppRunState = .shared, fill: @escaping (Article) async -> String?,
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

    /// The Downloads list by page (C110).
    var pageOverview: DownloadArticles {
        DownloadArticles(records: records, active: activeProgress, currentVoice: rendering.downloadVoice,
                      rendersDownloads: rendering.wantsLocalBake) { rendering.renderedVoice(of: $0) }
    }

    func record(for target: DownloadRecord.Target) -> DownloadRecord? {
        records.first { $0.target == target }
    }

    /// `id`'s download has the page being fetched or rendered now.
    func isActive(_ id: UUID) -> Bool { active?.recordID == id }

    /// The download covering `target` is still to finish.
    func isQueued(_ target: DownloadRecord.Target) -> Bool {
        record(for: target)?.hasQueuedArticles == true
    }

    /// Where `article`'s download stands, the one answer its row's mark and the *Download* /
    /// *Remove Download* rows (its row's menu, the Reader's and Now Playing's ⋯) read: while any
    /// download (its own or its folder's) has it queued, downloading with its real progress
    /// (paragraphs rendered of its total) when it is the page rendering now, waiting its turn
    /// (`queued`) otherwise, paused when every download holding it is (C90); that wins over
    /// downloaded (a re-download in flight). Downloaded by the Downloads list's own rule
    /// (`DownloadOverview.isDownloaded`), which audio rendered only by listening never meets. A
    /// page out of the Library has no download.
    func state(of article: Article) -> DownloadState {
        guard article.isInLibrary else { return .notDownloaded }
        let key = article.listenKey
        let holding = records.filter { $0.entries.contains { $0.key == key && $0.state == .queued } }
        if !holding.isEmpty {
            if holding.allSatisfy(\.isPaused) { return .paused(fraction: 0) }
            if let progress = activeProgress, progress.key == key { return .downloading(fraction: progress.fraction) }
            return .queued(fraction: 0)
        }
        return isDownloaded([key]) ? .downloaded : .notDownloaded
    }

    /// Where `folder`'s download stands, for its row and its header: downloading while its
    /// download has pages queued (paused included), by the Downloads list's figure
    /// (`DownloadOverview.fraction`); downloaded when every page it covers is (`covers`; with none
    /// to cover, while its toggle is on). `articles`: its pages in play order (a row passes what it
    /// already holds, so this fetches nothing; the cache's indexes are in memory).
    func state(of folder: Folder, articles: [Article]) -> DownloadState {
        let record = record(for: .folder(folder.id))
        if let record, record.hasQueuedArticles {
            let fraction = DownloadOverview.fraction(of: record, active: activeProgress)
            if record.isPaused { return .paused(fraction: fraction) }
            return active?.recordID == record.id ? .downloading(fraction: fraction) : .queued(fraction: fraction)
        }
        let keys = articles.filter { Self.covers($0, in: folder) }.map(\.listenKey)
        if keys.isEmpty { return record?.followsFolder == true ? .downloaded : .notDownloaded }
        return isDownloaded(keys) ? .downloaded : .notDownloaded
    }

    private func isDownloaded(_ keys: [UUID]) -> Bool {
        DownloadOverview.isDownloaded(keys, records: records, currentVoice: rendering.downloadVoice) {
            rendering.renderedVoice(of: $0)
        }
    }

    /// Something of `folder` is downloading or has audio kept: its *Remove Downloads* can run.
    /// Cached per page (`audioKnown`), cleared whenever a download changes.
    func hasDownloads(_ folder: Folder, articles: [Article]) -> Bool {
        if isQueued(.folder(folder.id)) { return true }
        return articles.contains { article in
            let key = article.listenKey
            if let known = audioKnown[key] { return known }
            let has = library.hasDownloads(article)
            audioKnown[key] = has
            return has
        }
    }

    /// The folder's Download toggle is on: its pages download, and so do the ones added later.
    func isOn(_ folder: Folder) -> Bool {
        record(for: .folder(folder.id))?.followsFolder == true
    }

    // MARK: - Time left (C91)

    /// Words the download voice renders per second while the app is open, measured as pages
    /// render (`sampleRate`) and kept across launches. Starts from the iPhone 17 Pro's Kokoro
    /// figure (about 10 paragraphs, 600 words, a minute).
    @ObservationIgnored private var wordsPerSecond: Double = {
        let stored = UserDefaults.standard.double(forKey: DownloadCenter.rateKey)
        return stored > 0 ? stored : 10
    }()
    @ObservationIgnored private var lastSample: (key: UUID, missing: Int, at: Date)?
    nonisolated static let rateKey = "downloads.wordsPerSecond"

    /// Folds the paragraphs rendered since the last look into the measured rate. Only gaps the
    /// app spent rendering count: a gap over a minute (the app was away) starts a new sample.
    private func sampleRate(key: UUID, paragraphs: [String], missing: Int) {
        let now = Date()
        defer { lastSample = (key, missing, now) }
        guard let last = lastSample, last.key == key, missing < last.missing else { return }
        let seconds = now.timeIntervalSince(last.at)
        guard seconds > 0.2, seconds < 60, let article = library.article(key: key), article.wordCount > 0 else { return }
        let words = Double(last.missing - missing) * Double(article.wordCount) / Double(max(paragraphs.count, 1))
        let measured = min(max(words / seconds, 0.5), 500)
        wordsPerSecond = wordsPerSecond * 0.8 + measured * 0.2
        UserDefaults.standard.set(wordsPerSecond, forKey: Self.rateKey)
    }

    /// Words still to render in `record`: its queued pages', less what the page rendering now has.
    private func wordsLeft(in record: DownloadRecord) -> Double {
        var words = 0.0
        for entry in record.entries where entry.state == .queued {
            let count = Double(library.article(key: entry.key)?.wordCount ?? 0)
            if let progress = activeProgress, progress.recordID == record.id, progress.key == entry.key {
                words += count * (1 - progress.fraction)
            } else {
                words += count
            }
        }
        return words
    }

    /// Seconds of rendering (with the app open) `record` still needs; nil when it has nothing
    /// queued.
    func renderSecondsLeft(_ record: DownloadRecord) -> TimeInterval? {
        guard record.hasQueuedArticles else { return nil }
        return wordsLeft(in: record) / wordsPerSecond
    }

    /// Seconds of rendering before `record` starts: the downloads ahead of it that aren't paused.
    func renderSecondsBefore(_ record: DownloadRecord) -> TimeInterval {
        var seconds = 0.0
        for other in records {
            if other.id == record.id { break }
            if !other.isPaused { seconds += renderSecondsLeft(other) ?? 0 }
        }
        return seconds
    }

    /// "~2 h 45 min" for a number of seconds (at least a minute).
    nonisolated static func estimate(_ seconds: TimeInterval) -> String {
        String(localized: "~\(ListeningTime.label(minutes: max(1, Int((seconds / 60).rounded()))))")
    }

    // MARK: - Asking for downloads

    /// A page's own Download. A page whose downloads were deleted from its folder's download
    /// (P8) is taken back into it too.
    func download(_ article: Article) -> Request {
        if let folder = article.folder, let record = record(for: .folder(folder.id)), record.deleted.contains(article.listenKey) {
            withRecord(record.id) { $0.deleted.removeAll { $0 == article.listenKey } }
            takeInNewArticles()
        }
        return request(.article(article.listenKey))
    }

    /// A folder's Download, its toggle turned on: every page it covers is queued (its deleted
    /// ones too, P8), and the pages added later join. With the toggle off and every page it
    /// covers downloaded already (its header's filled ↓), the toggle only goes back on (`turnOn`).
    func download(_ folder: Folder) -> Request {
        if !isOn(folder), state(of: folder, articles: library.articles(in: folder)) == .downloaded { return turnOn(folder) }
        return request(.folder(folder.id))
    }

    /// The toggle back on over a folder that is all downloaded: its download follows the folder
    /// again, unpaused, its finished pages and its *Keep* as they were, so nothing is checked or
    /// rendered again. Pages it doesn't list yet join, queued (`takeInNewArticles`; with no download
    /// of the folder's own, every page, each already downloaded by its own download, so its turn
    /// is over at once).
    private func turnOn(_ folder: Folder) -> Request {
        if let record = record(for: .folder(folder.id)) {
            withRecord(record.id) {
                $0.title = folder.name
                $0.followsFolder = true
                $0.isPaused = false
            }
        } else {
            records.append(DownloadRecord(target: .folder(folder.id), title: folder.name, addedAt: Date(), entries: []))
        }
        takeInNewArticles()
        advance()
        return isQueued(.folder(folder.id)) ? .added : .waitingForNew
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
        if let existing, existing.hasQueuedArticles {
            guard existing.isPaused else { return .alreadyQueued }
            withRecord(existing.id) { $0.isPaused = false }
            advance()
            return .resumed
        }
        guard let (title, keys) = articles(of: target) else { return .nothingToDownload }
        // A folder's toggle turns on with nothing in it yet; a page's download needs the page.
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
    private func articles(of target: DownloadRecord.Target) -> (String, [UUID])? {
        switch target {
        case .article(let key):
            guard let article = library.article(key: key) else { return nil }
            return (article.lineOne, [article.listenKey])
        case .folder(let id):
            guard let folder = library.folder(id: id) else { return nil }
            let articles = library.articles(in: folder).filter { Self.covers($0, in: folder) }
            return (folder.name, articles.map(\.listenKey))
        }
    }

    /// A folder's download covers its pages that play; a book's or story's only while unfinished
    /// (D7 trims finished chapters' audio).
    static func covers(_ article: Article, in folder: Folder) -> Bool {
        !article.skipsInPlayback && !(folder.kind.isBookOrSeries && article.finishedAt != nil)
    }

    /// The list's line, the Library's (`LibraryQueries`): a download is listed while what it
    /// downloads is in the Library. A page removed from it (still kept for what plays) isn't.
    private func isInLibrary(_ target: DownloadRecord.Target) -> Bool {
        switch target {
        case .article(let key): library.article(key: key)?.isInLibrary == true
        case .folder(let id): library.folder(id: id) != nil
        }
    }

    /// After a library edit: downloads of what left the Library (a page removed, a page or folder
    /// deleted) leave the list, and the page rendering for one stops; so does a folder download's
    /// page that left the Library, whose entry then fails as no longer in it. Their audio is the
    /// library's to keep or delete (a removed page's is ephemeral already, a deleted one's is
    /// gone). Folders with Download on take in the pages added to them (`takeInNewArticles`).
    func followLibrary() {
        guard isStarted else { return }
        let gone = Set(records.filter { !isInLibrary($0.target) }.map(\.id))
        if let active, gone.contains(active.recordID) || !isInLibrary(.article(active.key)) { stopActive() }
        updateRecords { records in records.removeAll { gone.contains($0.id) } }
        takeInNewArticles()
        advance()
    }

    /// Each folder with Download on: its pages not in its download yet, and not deleted from it,
    /// join it at the end, queued.
    private func takeInNewArticles() {
        let joining = records.compactMap { record -> (UUID, [UUID])? in
            guard record.followsFolder, case .folder(let id) = record.target, let folder = library.folder(id: id) else { return nil }
            let new = record.joining(library.articles(in: folder).filter { Self.covers($0, in: folder) }.map(\.listenKey))
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
            for index in records.indices where records[index].hasQueuedArticles { records[index].isPaused = paused }
        }
        if paused, active != nil { stopActive() }
        advance()
    }

    /// The Downloads list's *Remove Download* / *Remove Downloads*: the page's or folder's own
    /// action, the one its menu runs (`deleteDownloads(of:)`). When what was downloaded has left
    /// the library, only the download goes, with the audio no other download holds (except what
    /// listening needs, `purgeAudio`).
    func remove(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        switch records[index].target {
        case .article(let key):
            if let article = library.article(key: key) { return deleteDownloads(of: article) }
        case .folder(let folderID):
            if let folder = library.folder(id: folderID) { return deleteDownloads(of: folder) }
        }
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
              let (title, keys) = articles(of: record.target), !keys.isEmpty else { return }
        if active?.recordID == id { stopActive() }
        withRecord(id) {
            $0.title = title
            $0.requeue(keys)
        }
        advance()
    }

    /// *Re-download* on one page of the list (C110): its turn comes again in every download that
    /// holds it, rendered in the download voice.
    func redownload(article key: UUID) {
        updateRecords { records in
            for r in records.indices {
                for e in records[r].entries.indices where records[r].entries[e].key == key {
                    records[r].entries[e].state = .queued
                    records[r].entries[e].failure = nil
                }
            }
        }
        advance()
    }

    /// *Keep*: audio in `voice` counts as done for this download.
    func keep(_ id: UUID, voice: String) {
        withRecord(id) { $0.keptVoice = voice }
    }

    /// *Remove Download* in a page's menu: the page leaves every download (`forget`) and its audio
    /// goes (unless listening needs it, `purgeAudio`). It stays deleted: a folder's download no
    /// longer lists it, so the folder shows as not all downloaded, and nothing renders it again
    /// until it is played or Download is tapped (the page's, or the folder's, which lists the
    /// folder's pages again).
    func deleteDownloads(of article: Article) {
        forget([article.listenKey])
        if let folder = article.folder, let record = record(for: .folder(folder.id)) {
            withRecord(record.id) { $0.deleted.append(article.listenKey) }
        }
        purgeAudio([article.listenKey])
        advance()
    }

    /// *Remove Downloads* on a folder: its download goes (its toggle off), its pages leave every
    /// other download (`forget`), and their audio goes (unless listening needs it, `purgeAudio`).
    func deleteDownloads(of folder: Folder) {
        if let record = record(for: .folder(folder.id)), active?.recordID == record.id { stopActive() }
        records.removeAll { $0.target == .folder(folder.id) }
        let keys = library.articles(in: folder).map(\.listenKey)
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
            // A folder's toggle stays on with nothing left in it: later pages still join.
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
            if let article = library.article(key: key) { library.deleteDownloads(article) }
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

    /// The next page may be handed to the render queue: in front, or in the background while
    /// audio plays on a route that renders there (C94; the render queue still puts the playing
    /// article first and yields to it).
    private var mayHandOver: Bool { runState.phase != .background || rendering.rendersDownloadsInBackground }

    private func advance() {
        guard isStarted, runner == nil, active == nil, mayHandOver else { return }
        runner = Task { [weak self] in
            await self?.runQueue()
            self?.runner = nil
        }
    }

    /// Hands pages to the render queue until one is rendering (its `bakeCompleted` brings the
    /// next), the list is done, or no voice renders downloads.
    private func runQueue() async {
        while mayHandOver, rendering.wantsLocalBake, active == nil, let next = nextQueued() {
            let (recordID, key) = (next.recordID, next.key)
            guard let article = library.article(key: key), article.isInLibrary else {
                finish(recordID, key, .failed, String(localized: "It’s no longer in the Library"))
                continue
            }
            // A fetch needs a window: a link page waits for the foreground.
            if article.isLink, runState.phase == .background { return }
            if article.isLink {
                active = Active(recordID: recordID, key: key, phase: .fetching)
                let failure = await fill(article)
                // Paused, removed or its downloads deleted while it loaded: it isn't rendered.
                guard active == Active(recordID: recordID, key: key, phase: .fetching) else { continue }
                active = nil
                if let failure {
                    finish(recordID, key, .failed, failure)
                    continue
                }
            }
            guard let article = library.article(key: key), article.isInLibrary, article.hasText else {
                finish(recordID, key, .failed, String(localized: "Couldn’t get its text"))
                continue
            }
            let paragraphs = article.listenDocument().paragraphs
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

    private func finish(_ recordID: UUID, _ key: UUID, _ state: DownloadRecord.ArticleState, _ failure: String? = nil) {
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
        sampleRate(key: active.key, paragraphs: paragraphs, missing: missing)
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
    /// Downloads may go on in the background now: audio plays on a route that renders there (C94).
    var rendersDownloadsInBackground: Bool { get }
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
