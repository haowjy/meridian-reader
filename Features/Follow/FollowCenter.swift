import Foundation
import Observation

/// Follow: a story's table of contents read into a folder of chapter links (`LibraryStore.follow`),
/// the chapters' text fetched one at a time while the app is in front, and the table of contents read
/// again about once a day while the app is in use, new chapters going at the end of the folder.
/// No feeds, no notifications, nothing in the background: every fetch needs the app in front
/// (a hidden web view in its window), and every one goes through the one `FetchQueue`, strictly
/// one at a time and paced per site.
///
/// **Which chapter is fetched next** (`nextWaiting`): one you pressed ▶ on (it then plays), else
/// the one after the page playing, else the first waiting chapter of the oldest story. A chapter
/// whose site refuses or doesn't answer is tried again after the queue's back-off, a few times,
/// then left for the next launch (or ▶) with why (`failures`). Unfollowed stories' chapters are
/// still fetched: Unfollow stops only the daily check.
///
/// Downloads fetch a link page's text through here too (`fill`), so a page is never fetched twice
/// at once and nothing goes around the queue.
@MainActor
@Observable
final class FollowCenter {
    /// About once a day.
    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// A check that failed is tried again after this.
    static let checkRetry: TimeInterval = 60 * 60
    /// How often, while the app is in front, it looks for a check that is due.
    static let clockTick: Duration = .seconds(15 * 60)
    /// Tries at one chapter whose site refused or didn't answer before it is left for now.
    static let attemptsPerChapter = 4

    /// A failed check: why, and when it is tried again.
    struct CheckFailure: Equatable {
        var message: String
        var retryAt: Date
    }

    /// Where a followed story's chapter waiting for its text stands (`status(of:)`).
    enum ChapterStatus: Equatable {
        /// Its turn hasn't come.
        case waiting
        /// In the queue now: loading, or waiting for its turn and its site's pause.
        case fetching
        /// Its last try was refused or got no answer; tried again once its site's back-off ends.
        case retrying(until: Date)
        /// Couldn't be had this launch, with why.
        case failed(String)
    }

    /// A story's chapters as its header and the Following sheet count them: the ones that play
    /// (not skipped), how many have their text, and the number of the one being fetched.
    struct Progress: Equatable {
        var chapters = 0
        var withText = 0
        var fetching: Int?
        /// Chapters still to fetch this launch (waiting, or being fetched).
        var toFetch = 0
    }

    /// Pages being fetched now (loading, or waiting in the queue for their turn and their site's
    /// pause): the loop's chapter, ▶'s, and a download's link page.
    private var fetching: Set<UUID> = []
    /// Pages whose last try was refused or got no answer, tried again after the back-off.
    private var retrying: Set<UUID> = []
    /// Chapters whose text couldn't be had this launch, with why. Tried again at the next launch,
    /// or when ▶ asks for one.
    private var failures: [UUID: String] = [:]
    /// Stories whose table of contents is being read now.
    private(set) var checking: Set<UUID> = []
    /// Stories whose last check this launch failed.
    private(set) var checkFailures: [UUID: CheckFailure] = [:]
    /// ▶ on a waiting chapter: being fetched first, then played (unless something else started
    /// since). Its row shows ▶ preparing.
    private(set) var playWhenFetched: UUID?

    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored let queue: FetchQueue
    @ObservationIgnored private let runState: AppRunState
    /// The page bound to the playback session (the waiting chapter after it goes first).
    @ObservationIgnored private let playingKey: () -> UUID?
    /// Plays a page with its text in, from its spot.
    @ObservationIgnored private let startPlayback: (Page) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var inFlight: [UUID: Task<String?, Never>] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var runStateObserver: NSObjectProtocol?

    init(library: LibraryStore, queue: FetchQueue, runState: AppRunState = .shared,
         playingKey: @escaping () -> UUID?, startPlayback: @escaping (Page) -> Void, now: @escaping () -> Date = Date.init) {
        self.library = library
        self.queue = queue
        self.runState = runState
        self.playingKey = playingKey
        self.startPlayback = startPlayback
        self.now = now
    }

    /// Once the launch's library maintenance is done: fetching starts, and the daily checks.
    func start() {
        guard clock == nil else { return }
        runStateObserver = NotificationCenter.default.addObserver(forName: AppRunState.didChange, object: runState,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameToFront() }
        }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkDueStories()
                try? await Task.sleep(for: Self.clockTick)
            }
        }
        kick()
    }

    private var isInFront: Bool { runState.phase != .background }

    private func cameToFront() {
        guard isInFront else { return }
        kick()
        Task { await checkDueStories() }
    }

    // MARK: - Following

    /// The story `url` belongs to, read from its table of contents (`TableOfContents.contentsURL`):
    /// one request, ahead of background work.
    func readContents(of url: URL) async throws -> TableOfContents {
        let page = try await queue.links(of: TableOfContents.contentsURL(for: url), priority: .user)
        guard let contents = TableOfContents.read(page) else { throw FollowError.noChapters }
        return contents
    }

    /// Follows `contents` in `parent` (nil: the top level) with the chapters `kept`, and starts
    /// fetching them.
    func follow(_ contents: TableOfContents, keeping kept: [TableOfContents.Chapter], in parent: Folder?) throws -> Folder {
        let folder = try library.follow(contents, keeping: kept, in: parent)
        kick()
        return folder
    }

    /// *Check Now*, and the daily check: reads the story's table of contents again and adds the
    /// chapters it hasn't listed before at the end.
    func check(_ folder: Folder, priority: FetchQueue.Priority = .user) async {
        let id = folder.id
        guard let url = folder.contentsURL, !checking.contains(id) else { return }
        checking.insert(id)
        defer { checking.remove(id) }
        do {
            guard let contents = TableOfContents.read(try await queue.links(of: url, priority: priority)) else {
                throw FollowError.noChapters
            }
            guard let folder = library.folder(id: id) else { return }
            if try library.addNewChapters(from: contents, to: folder) > 0 { kick() }
            checkFailures[id] = nil
        } catch is CancellationError {
            return
        } catch {
            checkFailures[id] = CheckFailure(message: Self.message(for: error), retryAt: now().addingTimeInterval(Self.checkRetry))
        }
    }

    /// When a followed story's next daily check is due.
    func nextCheck(of folder: Folder) -> Date? {
        guard let state = folder.followState, state.isFollowing else { return nil }
        let due = (state.lastCheckedAt ?? .distantPast).addingTimeInterval(Self.checkInterval)
        return max(due, checkFailures[folder.id]?.retryAt ?? .distantPast)
    }

    /// Followed stories whose check is due, one at a time.
    private func checkDueStories() async {
        guard isInFront else { return }
        // By id: a story deleted during an earlier check is gone, not read after its delete.
        for id in library.stories().map(\.id) {
            guard isInFront, let folder = library.folder(id: id), let due = nextCheck(of: folder), due <= now() else { continue }
            await check(folder, priority: .background)
        }
    }

    // MARK: - Fetching chapters

    /// ▶ on a chapter waiting for its text: it is fetched now, ahead of background work (a failure
    /// this launch is forgotten), then plays, unless something else has started by then.
    func play(_ page: Page) {
        let key = page.listenKey
        let playingWhenAsked = playingKey()
        failures[key] = nil
        playWhenFetched = key
        Task {
            let failure = await fill(page, priority: .user)
            if let failure { failures[key] = failure }
            guard playWhenFetched == key else { return }
            playWhenFetched = nil
            if failure == nil, playingKey() == playingWhenAsked, let page = library.page(key: key), page.hasText {
                startPlayback(page)
            }
        }
    }

    /// Fetches the link page's text and stores it in place (`LibraryStore.storeFetchedText`),
    /// trying again after the site's back-off when it refuses or doesn't answer, up to
    /// `attemptsPerChapter` times. Returns why it failed, nil once the text is in. A page being
    /// fetched already is waited for, not fetched again.
    func fill(_ page: Page, priority: FetchQueue.Priority) async -> String? {
        let key = page.listenKey
        if let running = inFlight[key] { return await running.value }
        if page.hasText {
            // Played before (from the browser): the text it was played from is its own now.
            do { try library.keepCachedText(page) } catch { return String(localized: "Couldn’t save it") }
            return nil
        }
        guard let url = page.url else { return String(localized: "It has no address") }
        let task = Task { await self.fetchText(key: key, url: url, priority: priority) }
        inFlight[key] = task
        let failure = await task.value
        inFlight[key] = nil
        return failure
    }

    private func fetchText(key: UUID, url: URL, priority: FetchQueue.Priority) async -> String? {
        fetching.insert(key)
        defer {
            fetching.remove(key)
            retrying.remove(key)
        }
        var attempt = 0
        while true {
            attempt += 1
            do {
                let content = try await queue.content(of: url, priority: priority)
                guard !content.document.isEmpty else { return String(localized: "Nothing to listen to") }
                // Deleted, or filled some other way (played from the browser), while it loaded.
                guard let page = library.page(key: key), page.isLink, !page.hasText else { return nil }
                try library.storeFetchedText(content, in: page)
                return nil
            } catch LibraryStoreError.saveFailed {
                return String(localized: "Couldn’t save it")
            } catch {
                if Self.isTransient(error), attempt < Self.attemptsPerChapter {
                    retrying.insert(key)
                    continue
                }
                ListenTimingLog.log("follow_fetch_failed", ["key": ListenTimingLog.shortKey(key), "err": "\(error)"])
                return Self.message(for: error)
            }
        }
    }

    /// Fetches the waiting chapters while the app is in front, one at a time, until none waits.
    private func kick() {
        guard loop == nil, isInFront else { return }
        loop = Task { [weak self] in
            await self?.runLoop()
            self?.loop = nil
        }
    }

    private func runLoop() async {
        while isInFront, let page = nextWaiting() {
            let key = page.listenKey
            if let failure = await fill(page, priority: .background) { failures[key] = failure }
        }
    }

    /// The chapter to fetch next: the waiting chapter after the page playing, else the first
    /// waiting chapter of the oldest story (▶'s goes at once, `play`).
    private func nextWaiting() -> Page? {
        if let playing = playingKey(), let folder = library.page(key: playing)?.folder, folder.kind == .series,
           case .waiting(let key) = ChapterAdvance.after(playing, in: library.chapterSnapshot(of: folder)),
           let page = library.page(key: key), isToFetch(page) {
            return page
        }
        for folder in library.stories() {
            if let page = library.pages(in: folder).first(where: isToFetch) { return page }
        }
        return nil
    }

    // MARK: - Where a chapter stands

    /// A story's chapter in the Library still to fetch this launch: waiting for its text, not
    /// skipped, not failed.
    private func isToFetch(_ page: Page) -> Bool {
        page.isWaitingChapter && page.isInLibrary && !page.skipsInPlayback && failures[page.listenKey] == nil
    }

    /// Where `page` stands when it is a followed story's chapter waiting for its text, not skipped;
    /// nil for any other page. The one rule rows, headers and the Following sheet read.
    func status(of page: Page) -> ChapterStatus? {
        guard page.isWaitingChapter, !page.skipsInPlayback else { return nil }
        let key = page.listenKey
        if fetching.contains(key) {
            if retrying.contains(key), let url = page.url, let backOff = queue.backOff(of: FetchQueue.site(of: url)) {
                return .retrying(until: backOff.until)
            }
            return .fetching
        }
        if let failure = failures[key] { return .failed(failure) }
        return .waiting
    }

    /// `pages` (a story's, in its order) counted: skipped chapters left out.
    func progress(of pages: [Page]) -> Progress {
        var progress = Progress()
        for page in pages where !page.skipsInPlayback {
            progress.chapters += 1
            switch status(of: page) {
            case nil: progress.withText += 1
            case .fetching?, .retrying?:
                progress.toFetch += 1
                if progress.fetching == nil { progress.fetching = progress.chapters }
            case .waiting?: progress.toFetch += 1
            case .failed?: break
            }
        }
        return progress
    }

    // MARK: - Messages

    /// The site refused (429, 5xx) or didn't answer: worth trying again after its back-off.
    private static func isTransient(_ error: Error) -> Bool {
        switch FetchQueue.outcome(of: error, after: 0) {
        case .refused, .noAnswer: true
        case .answered, nil: false
        }
    }

    enum FollowError: LocalizedError {
        case noChapters

        var errorDescription: String? {
            String(localized: "No list of chapters on this page")
        }
    }

    /// What a failed fetch or check says.
    static func message(for error: Error) -> String {
        switch error {
        case FollowError.noChapters:
            return FollowError.noChapters.localizedDescription
        case URLPageFetcher.FetchError.status(let code, _):
            return code == 429 ? String(localized: "The site asked to slow down")
                : code == 404 || code == 410 ? String(localized: "The page isn’t there")
                : code == 401 || code == 403 ? String(localized: "The site refused (sign in in the browser?)")
                : String(localized: "The site answered with an error (\(code))")
        case URLPageFetcher.FetchError.noWindow:
            return String(localized: "The app wasn’t in front")
        case is NavigationWait.Failure, URLPageFetcher.FetchError.timedOut:
            return String(localized: "The site didn’t answer")
        default:
            return String(localized: "Couldn’t get the text")
        }
    }
}
