import Foundation
import AVFoundation
import Observation

/// Something playback has to tell the user, shown once as the shell's toast
/// (`RootView`, `ShellToast`): an article that can't be read ("Can't read French yet."), or the
/// engine pausing where its audio ran out ("Kokoro stopped.", with Retry).
struct ListenNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    /// Retry (`SpeechController.retry`) plays on from where it paused.
    var offersRetry = false
}

/// Listen façade for UI. Phase / playhead live in `playback` (PlaybackSessionState); views read
/// the published copies below it. Each utterance plays in its article's own voice
/// (`VoiceSelection`) on the on-device engine (`LocalListenEngine`), which reports events;
/// engines never clear the session themselves. Playback never changes the voice it reads in:
/// where the voice can't go on it pauses and says so (`notice`). A book or series carries on
/// from chapter to chapter (`SpeechController+Advance`). See docs/LISTEN_PLAYBACK.md.
@MainActor
@Observable
final class SpeechController {
    // Exactly one instance per process: built by `AppComposition` (composition root) and
    // injected via ReaderApp + the environment default. A second instance would warm a second
    // copy of the local model.
    static let rateDefaultsKey = "reader.rateMultiplier"
    /// The settings it stores, for `-resetLibrary` to clear.
    static let storedKeys = [rateDefaultsKey]

    /// Single source of truth for Listen phase + position. Not observed directly: every change is
    /// copied into the published properties below, each assigned only when its value changes.
    @ObservationIgnored private(set) var playback = PlaybackSessionState() {
        didSet {
            if playback.resumePoint != oldValue.resumePoint { saveResumePoint() }
            publishPlayback()
        }
    }

    // MARK: Published playback (what views observe)
    //
    // Observation tracks stored properties one by one. The in-paragraph offset moves several
    // times a second while playing; keeping it apart means a view that reads only the article,
    // phase or paragraph is not redrawn for it. Read `spokenUTF16Offset` only in small leaf views
    // (scrubber thumb, mini-player fill, progress reporter).

    private(set) var activeSessionID: UUID?
    /// The text the bound page plays (`PlaybackSessionState.textFingerprint`). Not observed: it
    /// changes only with the page, and nothing draws it.
    var activeTextFingerprint: String? { playback.textFingerprint }
    /// The folder the bound page is in, which playback carries on through
    /// (`PlaybackSessionState.folderID`).
    private(set) var activeFolderID: UUID?
    private(set) var document: ParagraphDocument = .empty
    private(set) var playbackPhase: PlaybackPhase = .idle
    private(set) var currentParagraphIndex = 0
    private(set) var spokenUTF16Offset = 0

    /// What the listen bar shows from the engine. Engine state isn't observable, so
    /// `sampleListenStatus` takes this on every playback change and every engine
    /// `statusChanged`, and bumps `listenStatusRevision` only when it differs: views that show it
    /// (`playState(of:)`, `isBufferingNext`, `isPreparingVoice`) redraw exactly when it changes.
    private struct ListenStatus: Equatable {
        var showsPause = false
        var bufferingNext = false
        var preparingVoice = false
    }
    @ObservationIgnored private var listenStatus = ListenStatus()
    private var listenStatusRevision = 0

    // MARK: Background listening (audio session, lock screen, interruptions)

    /// `.playback` / `.spokenAudio`; activated on play/resume, deactivated on stop/finish.
    let audioSession: ListenAudioSession
    /// Lock screen / Control Center info + remote commands (→ `handleRemoteCommand` → Session).
    let lockScreen: NowPlayingController
    @ObservationIgnored private var interruptionPolicy = ListenInterruptionPolicy()

    /// What the bound page is (title, site, artwork, canonical URL), from the `SpeechSession` it
    /// was prepared with. Observed: the bar and 🎧 read it through `nowPlaying` / `playState`.
    struct SessionMeta: Equatable {
        var id: UUID
        var title: String?
        var site: String?
        var artwork: Data?
        var canonicalURL: String?
        var sourceLabel: String?
        /// The folder the page is in: "Playing from", the lock screen's album, and for a chapter
        /// the bar's source.
        var folder: PlaybackFolder?
    }
    private(set) var sessionMeta: SessionMeta?
    /// The one request making a page ready to play before it is bound (🎧 extracting its page).
    /// A newer request, Stop Listening and every other playback intent end it; only the current
    /// request may start playing (`isStillPreparing`).
    private(set) var preparation: ListenPreparation?
    /// Told about every position worth keeping (`ListeningProgressRecorder`), synchronously, in the
    /// same transaction as the change, so a replaced page's last spot is reported before the next
    /// page binds.
    @ObservationIgnored var onProgress: ((ListenProgress) -> Void)?
    /// Told about the `ReaderArticle` a page is started from (`listen(to:)`), before its session
    /// binds, so the recorder can keep a page the library doesn't have with its text.
    @ObservationIgnored var onListen: ((ReaderArticle) -> Void)?
    /// The library as folders play through it (`SpeechController+Advance`). nil: every
    /// page plays to its end and stops.
    @ObservationIgnored var nextChapters: NextChapterProviding?
    /// Between chapters: what is staged, fetched and timed (`SpeechController+Advance`).
    @ObservationIgnored var chapterFlow = ChapterFlow()
    @ObservationIgnored private var runStateObserver: NSObjectProtocol?
    /// Debug panel snapshot and background-stretch tracking.
    @ObservationIgnored private(set) lazy var diagnostics = ListenDiagnostics(speech: self)

    let localTTS: LocalTTSCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let localEngine: LocalListenEngine

    /// The voice the live utterance plays in (nil: nothing speaking or held). Set in `speak`,
    /// cleared when the engine stops.
    @ObservationIgnored private(set) var boundSelection: VoiceSelection?
    /// The engine every command goes to (nil: nothing speaking or held).
    var activeEngine: LocalListenEngine? { boundSelection == nil ? nil : localEngine }

    /// What the shell shows next as a toast (`noticeShown` once it has).
    private(set) var notice: ListenNotice?

    /// C138a: the voice of the article with `articleID`: its own selection (locked now if it is
    /// brand new). Its engine starts loading if it isn't; the player waits for it. Never another
    /// voice.
    func selection(forPlaying articleID: UUID) -> VoiceSelection {
        let selection = localTTS.selection(for: articleID)
        localTTS.loadEngineIfNeeded(selection.engine)
        return selection
    }

    /// The shell showed `notice` (`RootView`).
    func noticeShown(_ id: UUID) {
        if notice?.id == id { notice = nil }
    }

    func tell(_ message: String, offersRetry: Bool = false) {
        notice = ListenNotice(message: message, offersRetry: offersRetry)
    }

    /// `engine` stopped (it failed, or killed the last process): playback is paused for Retry.
    func tellStopped(_ engine: SpeechEngineID) {
        tell(String(localized: "\(localTTS.engines.shortName(engine)) stopped."), offersRetry: true)
    }

    /// Why `session` can't be read (`LocalTTSCoordinator.cantReadNotice`), told to the user; false
    /// when it can.
    private func refuses(_ articleID: UUID, paragraphs: [String]) -> Bool {
        guard let refusal = localTTS.cantReadNotice(of: articleID, paragraphs: paragraphs) else { return false }
        ListenTimingLog.log("listen_refused", ["key": ListenTimingLog.shortKey(articleID), "why": refusal])
        tell(refusal)
        return true
    }

    /// The toast's Retry: play on from where it paused (a press of play does the same).
    func retry() { userPerform(.resume) }

    var isPlaying: Bool { playbackPhase == .playing }

    /// Copies `playback` into the published properties (only the ones that changed), then
    /// refreshes what is derived from it: the lock screen and the listen-bar status. Progress
    /// isn't reported while the next chapter is fetched: the page still bound has ended, and
    /// play / pause then say how the next one starts, not that this one plays again.
    private func publishPlayback() {
        let before = ListenProgressKey(id: activeSessionID, paragraph: currentParagraphIndex, phase: playbackPhase)
        var nowPlayingChanged = false
        if activeSessionID != playback.articleID { activeSessionID = playback.articleID; nowPlayingChanged = true }
        if activeFolderID != playback.folderID { activeFolderID = playback.folderID }
        if document != playback.document { document = playback.document; nowPlayingChanged = true }
        if playbackPhase != playback.phase { playbackPhase = playback.phase; nowPlayingChanged = true }
        if currentParagraphIndex != playback.playhead { currentParagraphIndex = playback.playhead; nowPlayingChanged = true }
        if spokenUTF16Offset != playback.utf16Offset { spokenUTF16Offset = playback.utf16Offset }
        if nowPlayingChanged { refreshNowPlaying() }
        sampleListenStatus()
        let after = ListenProgressKey(id: activeSessionID, paragraph: currentParagraphIndex, phase: playbackPhase)
        if after != before, let id = playback.articleID {
            onProgress?(ListenProgress(articleKey: id, text: playback.textFingerprint, paragraph: playback.playhead,
                                       utf16Offset: playback.utf16Offset, phase: playback.phase))
        }
    }

    private struct ListenProgressKey: Equatable {
        var id: UUID?
        var paragraph: Int
        var phase: PlaybackPhase
    }

    private func sampleListenStatus() {
        let status = ListenStatus(showsPause: activeSessionShowsPause(), bufferingNext: engineIsBufferingNext(),
                                  preparingVoice: engineIsPreparingVoice())
        guard status != listenStatus else { return }
        listenStatus = status
        listenStatusRevision &+= 1
    }

    // MARK: - What you hear

    /// The hearing state every surface shows. nil only before anything has played, and after
    /// Stop Listening; a finished page stays bound (`.finished`), so the bar keeps it with ▶.
    var nowPlaying: NowPlaying? {
        guard let id = activeSessionID, !document.isEmpty else { return nil }
        let meta = boundMeta
        let raw = meta?.sourceLabel ?? meta?.site ?? ""
        let host = raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
        let folder = meta?.folder
        let isChapter = folder?.isBookOrSeries == true
        let playingFrom: PlayingFrom = folder.map { .folder(id: $0.id, name: $0.name) } ?? .site(host: host)
        return NowPlaying(articleKey: id, canonicalURL: meta?.canonicalURL, title: meta?.title,
                          source: isChapter ? folder?.name ?? host : host, byline: meta?.site,
                          artwork: meta?.artwork, playingFrom: playingFrom, isChapter: isChapter, phase: playbackPhase)
    }

    /// What the bound page is (nil while the metadata adopted last belongs to another page).
    private var boundMeta: SessionMeta? {
        guard let id = activeSessionID, sessionMeta?.id == id else { return nil }
        return sessionMeta
    }

    /// The one place a ▶ / ⏸ comes from. Reads only session fields, so it is cheap on every
    /// redraw. What you hear shows `.playing` while audible (or meant to be), else `.paused`:
    /// `.prepared` and `.finished` show as paused.
    func playState(of target: ListenTarget) -> PlayState {
        if preparation?.target == target { return .preparing }
        guard isCurrent(target) else { return .idle }
        if isPreparingVoice { return .preparingVoice }
        return activeSessionShowsPause() ? .playing : .paused
    }

    /// What you hear waits for its on-device voice to load: playing, and nothing at its start is
    /// rendered yet (audio already rendered plays without the model). It starts by itself once
    /// the model is loaded; Pause holds it, another play replaces it, and a load that fails
    /// pauses it with a notice (`noteSpeakFailed`).
    var isPreparingVoice: Bool {
        _ = listenStatusRevision
        return engineIsPreparingVoice()
    }

    private func engineIsPreparingVoice() -> Bool {
        playback.phase == .playing && boundSelection != nil && localEngine.isWaitingForVoice
    }

    /// Whether `target` is what you hear (bound, in any phase).
    private func isCurrent(_ target: ListenTarget) -> Bool {
        guard let id = activeSessionID, !document.isEmpty else { return false }
        switch target {
        case .article(let key):
            return key == id
        case .webPage(let url):
            return boundMeta?.canonicalURL == url
        case .folder(let folderID):
            return activeFolderID == folderID
        }
    }

    /// A play button was pressed: pause what you hear, resume it (a finished page from its top,
    /// `PlaybackIntent`), or run `start` for something that isn't it (replacing what's playing).
    /// Never navigates.
    func press(_ target: ListenTarget, start: () -> Void) {
        switch playState(of: target) {
        case .playing, .preparingVoice:
            userPerform(.pause)
        case .paused:
            userPerform(.resume)
        case .idle, .preparing:
            start()
        }
    }

    /// ▶ / ⏸ on what you hear (the Now Playing bar, Now Playing's transport).
    func pressNowPlaying() {
        guard let id = activeSessionID else { return }
        press(.article(id)) {}
    }

    /// `target` is being made ready (its page extracting): its button shows `.preparing`, and
    /// what's playing keeps playing until it is ready. Replaces any earlier request.
    func beginPreparing(_ target: ListenTarget) -> ListenPreparation {
        let request = ListenPreparation(target: target)
        preparation = request
        return request
    }

    /// Whether `request` is still the one to start: no newer request, Stop Listening or other
    /// playback intent has come since it began.
    func isStillPreparing(_ request: ListenPreparation) -> Bool {
        preparation == request
    }

    /// `request` failed: its button goes back to what it was. A request already superseded
    /// changes nothing.
    func endPreparing(_ request: ListenPreparation) {
        if preparation == request { preparation = nil }
    }

    /// Nothing is being prepared any more. Writes only on a change: `playState` readers observe it.
    private func supersedePreparation() {
        if preparation != nil { preparation = nil }
    }

    /// The user asked for something: no auto-resume after an interruption, and a page still being
    /// prepared no longer starts.
    func noteUserIntent() {
        interruptionPolicy.noteUserIntent()
        supersedePreparation()
    }

    /// Every intent the user asks for (a button, a gesture, the scrubber, headphones, the lock
    /// screen) goes through here. What the app does on its own (carrying on to the next chapter,
    /// an interruption) calls `perform`.
    func userPerform(_ intent: PlaybackIntent) {
        noteUserIntent()
        // C129: the user pressing anything but pause after the engine stopped is the Retry.
        if localTTS.isPausedForRetry, intent != .pause, intent != .stop {
            localTTS.retryAfterEngineStop()
        }
        perform(intent)
    }

    /// Plays `article` from `spot` (`start`). The article goes to `onListen` first, so a page the
    /// library doesn't have is kept once it plays.
    func listen(to article: ReaderArticle, at spot: ListenSpot = .top) {
        guard !article.document.isEmpty, !refuses(article.id, paragraphs: article.document.paragraphs) else { return }
        onListen?(article)
        var session = SpeechSession(article: article)
        session.folder = nextChapters?.folder(containing: article.id)
        start(session, at: spot)
    }

    /// The one way a page starts playing: `session` from `spot`, replacing what plays (a page
    /// already bound plays from `spot`'s paragraph). A page in a folder carries on through it. A
    /// page that can't be read (`cantReadNotice`) doesn't start, and what plays plays on.
    func start(_ session: SpeechSession, at spot: ListenSpot = .top) {
        guard !session.document.isEmpty, !refuses(session.id, paragraphs: session.document.paragraphs) else { return }
        prepare(session, at: spot)
        userPerform(.play(from: spot.paragraph))
    }

    /// The page's icon arrived after it started playing (🎧 starts before fetching it).
    func setArtwork(_ data: Data, for articleKey: UUID) {
        guard boundMeta?.id == articleKey, boundMeta?.artwork == nil else { return }
        sessionMeta?.artwork = data
        refreshNowPlaying()
    }

    /// Plays the bound page from `paragraph` (☝︎ in Now Playing).
    func play(fromParagraph paragraph: Int) {
        guard isPrepared else { return }
        userPerform(.play(from: paragraph))
    }

    /// Scrubber release in Now Playing: the bound page's playhead to document offset `utf16`
    /// (a sentence start), keeping play / pause as it is.
    func seek(toUTF16Offset utf16: Int) {
        guard isPrepared else { return }
        userPerform(.seekOffset(utf16: utf16))
    }

    /// Listen intent is active but nothing is audible and more audio is on its way (the bound
    /// engine is waiting for it, e.g. the on-device render queue, or the next chapter is being
    /// fetched). Not the same as paused.
    var isBufferingNext: Bool {
        _ = listenStatusRevision
        return engineIsBufferingNext()
    }

    /// Audible audio always shows Pause, even while the phase briefly disagrees (the engine
    /// hasn't reported a change yet).
    private func activeSessionShowsPause() -> Bool {
        playback.articleID != nil && (engineSnapshot().isAudible || playback.phase == .playing)
    }

    private func engineIsBufferingNext() -> Bool {
        guard playback.articleID != nil, playback.phase == .playing else { return false }
        return activeEngine?.isWaitingForAudio == true
    }

    /// The session's resume point changed (playing a new paragraph, paused, stopped).
    private func saveResumePoint() {
        let resumePoints = localTTS.resumePoints
        if let point = playback.resumePoint {
            resumePoints.save(article: point.article, paragraph: point.paragraph, text: point.text)
        } else {
            resumePoints.clear()
        }
    }

    /// The listen speed, always one of `ListenRate.options` (`setRateMultiplier`).
    private(set) var rateMultiplier: Double {
        didSet {
            defaults.set(rateMultiplier, forKey: Self.rateDefaultsKey)
            // The engine keeps the speed and applies it to what is playing.
            localEngine.setRate(rateMultiplier)
            refreshNowPlaying()
        }
    }

    /// The speed nearest `value` among `ListenRate.options` (the pickers pass one; the lock screen
    /// any rate).
    func setRateMultiplier(_ value: Double) { rateMultiplier = ListenRate.nearest(to: value) }

    /// Over `localTTS`, which also holds the crash-resume file this writes as playback moves.
    /// `audioSession` / `nowPlaying` are injectable for unit tests (no process-wide audio session
    /// or remote command registration).
    init(localTTS: LocalTTSCoordinator,
         defaults: UserDefaults,
         audioSession: ListenAudioSession? = nil,
         nowPlaying: NowPlayingController? = nil) {
        self.localTTS = localTTS
        self.defaults = defaults
        self.localEngine = LocalListenEngine(coordinator: localTTS)
        self.audioSession = audioSession ?? ListenAudioSession()
        self.lockScreen = nowPlaying ?? NowPlayingController()
        // `double(forKey:)` also parses a launch-argument string ("-reader.rateMultiplier 2", a probe).
        let storedRate = defaults.object(forKey: Self.rateDefaultsKey) != nil
            ? defaults.double(forKey: Self.rateDefaultsKey) : 1.0
        self.rateMultiplier = storedRate > 0 ? ListenRate.nearest(to: storedRate) : 1.0
        localEngine.setRate(rateMultiplier)
        localEngine.onEvent = { [weak self] event in self?.handle(event) }
        // Category only; the session is activated when playback starts (activating at launch
        // interrupted other apps' audio just for opening Reader). Non-mixable so Reader becomes
        // the Now Playing app (lock screen controls); `UIBackgroundModes: audio` keeps it playing.
        self.audioSession.configure()
        self.audioSession.onEvent = { [weak self] event in self?.handleAudioSessionEvent(event) }
        self.audioSession.startObserving()
        self.lockScreen.attach { [weak self] command in
            self?.handleRemoteCommand(command) ?? .noActionableNowPlayingItem
        }
        runStateObserver = NotificationCenter.default.addObserver(
            forName: AppRunState.didChange, object: self.localTTS.synthQueue.runState, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appRunStateChanged() }
        }
    }

    // MARK: - Display

    var isPrepared: Bool { activeSessionID != nil && !document.isEmpty }
    var isActive: Bool { activeSessionID != nil && (playbackPhase == .playing || playbackPhase == .paused) }

    var canSkipToPreviousParagraph: Bool { isPrepared && currentParagraphIndex > 0 }
    var canSkipToNextParagraph: Bool { isPrepared && currentParagraphIndex + 1 < document.count }

    // MARK: - Session API (intents)

    /// Binds `session` paused at `spot`. A session already bound to it stays as it is.
    func prepare(_ session: SpeechSession, at spot: ListenSpot = .top) {
        supersedePreparation()
        adoptMeta(of: session)
        if playback.articleID == session.id, !playback.document.isEmpty { return }
        execute(playback.handle(.stop, engine: engineSnapshot()))
        endChapterFlow()
        playback.bind(articleID: session.id, document: session.document, at: spot, folderID: session.folderID)
    }

    /// What the lock screen, the bar and the language rules show for `session`, before it binds.
    func adoptMeta(of session: SpeechSession) {
        let meta = SessionMeta(id: session.id, title: session.title, site: session.site, artwork: session.artwork,
                               canonicalURL: session.canonicalURL, sourceLabel: session.sourceLabel,
                               folder: session.folder)
        if meta != sessionMeta { sessionMeta = meta }
    }

    /// The page changing inside a folder (`SpeechController+Advance`).
    func advancePlayback(to key: UUID, document: ParagraphDocument, folderID: UUID) -> [PlaybackCommand] {
        playback.advance(to: key, document: document, folderID: folderID)
    }

    func skipToPreviousParagraph() {
        guard canSkipToPreviousParagraph else { return }
        userPerform(.skip(delta: -1))
    }

    func skipToNextParagraph() {
        guard canSkipToNextParagraph else { return }
        userPerform(.skip(delta: 1))
    }

    func pause() { userPerform(.pause) }

    func resume() { userPerform(.resume) }

    /// Stop Listening: unbinds the page, so the bar goes away.
    func stop() {
        // Listen preempts bake; on stop, resume gap-fill so save-time work still lands on disk.
        endSession(restartBake: true)
    }

    /// The page keyed `key` is leaving the Library (removed from it, deleted) or being revised
    /// (`LibraryStore.stopPlaybackIfPlaying`). While it is what you hear, the session ends as Stop
    /// Listening ends it, so the bar and Now Playing let it go; but nothing renders for the page
    /// after: no gap fill, and the render its listen queued goes too (`removeBakeJob`, after the
    /// engines stopped; its audio stays). Anything else plays on.
    func stopIfPlaying(_ key: UUID) {
        guard activeSessionID == key else { return }
        endSession(restartBake: false)
        localTTS.removeBakeJob(cacheKey: key)
    }

    private func endSession(restartBake: Bool) {
        userPerform(.stop)
        endChapterFlow()
        finishSession(restartBake: restartBake)
        playback.clear()
    }

    /// The page keyed `oldID` is keyed `newID` now and holds `text` (`ArticleIdentity`
    /// fingerprint): Save landed on an older page holding the address under another key, or a
    /// merge moved a page's audio under the kept page's key (`LibraryStore.keyMerged`). A live
    /// session on `oldID` playing that text takes the new key without stopping audio. One playing
    /// other text stops as playback of a page being revised does (`stopIfPlaying`): a key can name
    /// other text by the time a merge runs (a *Replace* revised the kept chapter, or brought
    /// another chapter back under it), and its positions would be stored on text it isn't
    /// playing. No gap fill follows, since no page holds `oldID` any more.
    func rekeyActiveSession(from oldID: UUID, to newID: UUID, text: String?) {
        guard oldID != newID, playback.articleID == oldID else { return }
        guard let text, text == playback.textFingerprint else {
            ListenTimingLog.log("session_rekey", ["from": ListenTimingLog.shortKey(oldID),
                                                  "to": ListenTimingLog.shortKey(newID), "stopped": "other text"])
            stopIfPlaying(oldID)
            return
        }
        if sessionMeta?.id == oldID { sessionMeta?.id = newID }
        playback.rekey(to: newID)
        localEngine.rekey(to: newID)
    }

    // MARK: - Interruptions / route changes

    /// Calls / Siri pause (and resume if iOS says `shouldResume`); losing the headphones pauses.
    func handleAudioSessionEvent(_ event: ListenAudioEvent) {
        let playing = playback.phase == .playing || engineSnapshot().isAudible
        let action = interruptionPolicy.handle(event, isPlaying: playing)
        ListenTimingLog.log("audio_interruption", [
            "event": String(describing: event), "action": String(describing: action), "p": playback.playhead,
        ])
        ListenDebugLog.shared.append("audio \(event) → \(action)")
        switch action {
        case .pause:
            perform(.pause)
        case .resume:
            audioSession.activate()
            perform(.resume)
        case .rebuildEngines:
            stopEngines()
            localEngine.mediaServicesWereReset()
            execute(playback.holdForRebuiltEngines())
        case .none:
            break
        }
    }

    // MARK: - Foreground / background

    private func appRunStateChanged() {
        let phase = localTTS.synthQueue.runState.phase
        diagnostics.appPhaseChanged(phase)
    }

    // MARK: - Intent execution

    private func perform(_ intent: PlaybackIntent) {
        let commands = playback.handle(intent, engine: engineSnapshot())
        execute(commands)
    }

    func execute(_ commands: [PlaybackCommand]) {
        for command in commands {
            switch command {
            case .enginePlay:
                speak(fromUTF16Offset: playback.utf16Offset, startPaused: false)
            case .enginePause:
                pauseEngines()
            case .engineResume:
                resumeEngines()
            case .engineStop:
                stopEngines()
            case .engineSeek:
                speak(fromUTF16Offset: playback.utf16Offset, startPaused: playback.phase == .paused)
            }
        }
    }

    func engineSnapshot() -> PlaybackEngineSnapshot {
        activeEngine?.snapshot ?? PlaybackEngineSnapshot(isAudible: false, isPaused: false)
    }

    /// The engine confirms with `becamePaused`.
    private func pauseEngines() {
        activeEngine?.pause()
    }

    private func resumeEngines() {
        audioSession.activate()
        guard let engine = activeEngine, engine.snapshot.isPaused || engine.snapshot.isAudible else {
            // Nothing held: play from the playhead (the scrubbed sentence, if any).
            speak(fromUTF16Offset: playback.utf16Offset, startPaused: false)
            return
        }
        engine.resume()
    }

    func stopEngines() {
        boundSelection = nil
        localEngine.stop()
        sampleListenStatus()
    }

    /// Events from the engine while it is bound (its late callbacks after a stop count for
    /// nothing; the engine drops those of a replaced play itself).
    private func handle(_ event: PlaybackEngineEvent) {
        guard boundSelection != nil else { return }
        switch event {
        case .becameAudible:
            playback.handle(event)
            chapterBecameAudible()
        case .becamePaused:
            playback.handle(event)
        case .position(let paragraph, _):
            let moved = paragraph != playback.playhead
            playback.handle(event)
            if moved { stageNextChapterIfDue() }
        case .statusChanged:
            sampleListenStatus()
        case .stalled(let stall):
            let engine = boundSelection?.engine ?? localTTS.defaultSelection.engine
            switch stall {
            case .engineStopped: tellStopped(engine)
            case .background:
                tell(String(localized: "\(localTTS.engines.shortName(engine)) can’t read in the background."))
            }
        case .finished:
            pageEnded(restartBake: true)
        }
    }

    func restartUtteranceIfNeeded() {
        guard playback.isPrepared else { return }
        guard playback.phase == .playing || playback.phase == .paused else { return }
        speak(fromUTF16Offset: playback.utf16Offset, startPaused: playback.phase == .paused)
    }

    /// Binds the article's voice (`selection(forPlaying:)`) and plays from `offset`. A page bound
    /// that can't be read (`cantReadNotice`; one bound paused, then played) stays bound and
    /// unplayed, with the notice.
    func speak(fromUTF16Offset offset: Int, startPaused: Bool) {
        stopEngines()
        playback.moveTo(utf16: offset)
        let start = playback.utf16Offset
        guard start < (document.joinedText as NSString).length, let articleID = playback.articleID else {
            pageEnded(restartBake: false)
            return
        }
        guard !refuses(articleID, paragraphs: document.paragraphs) else {
            playback.reconcile(with: engineSnapshot())
            return
        }
        if !startPaused { audioSession.activate() }
        let selection = selection(forPlaying: articleID)
        boundSelection = selection
        // The phase already says playing or paused (the intent that led here set it); the engine
        // confirms with its own events.
        localEngine.play(ListenPlayRequest(articleID: articleID, document: document, utf16Offset: start,
                                           startPaused: startPaused, selection: selection))
    }

    /// Played to the end (not stopped) with nothing to carry on to: the engines and the audio
    /// session stop, but the page stays bound in `.finished`, so the bar keeps it with ▶ (which
    /// plays it again).
    func completeArticle(restartBake: Bool) {
        playback.handle(.finished)
        finishSession(restartBake: restartBake)
    }

    private func finishSession(restartBake: Bool) {
        let articleID = playback.articleID
        let paragraphs = playback.document.paragraphs
        let isChapter = boundMeta?.folder?.isBookOrSeries == true
        stopEngines()
        // Let other apps' audio resume (Stop Listening / the end of an article or a book).
        audioSession.deactivate()
        localTTS.synthQueue.unstage()
        // Books and series don't bake whole (D7): only the chapter playing and the next render.
        // C134: only for prepared audio; audio from listening isn't filled in whole.
        if restartBake, !isChapter, let articleID, !paragraphs.isEmpty, localTTS.preparedKey(articleID) {
            // Return-to-top gap fill so any paragraphs above the listen playhead still bake.
            localTTS.startBakeIfNeeded(articleID: articleID, paragraphs: paragraphs)
        }
    }

    // MARK: - Bake-ready marks

    /// Indices with a usable CAF for the article in its own voice (stale old-voice units don't
    /// count). nil hides the marks: its voice can't run here.
    func bakeReadyParagraphIndices(articleID: UUID, paragraphCount: Int) -> Set<Int>? {
        // C138a: the article's own selection, else the default it would take.
        let selection = localTTS.effectiveSelection(of: articleID)
        guard localTTS.engines.supports(selection.engine), let voice = localTTS.cacheVoice(of: selection) else { return nil }
        let localID = selection.engine
        // Hide until unit count is known — empty Set would mark every HTML block not-ready.
        guard paragraphCount > 0 else { return nil }
        _ = localTTS.bakeMarksRevision
        _ = localTTS.audioCache.contentRevision
        return localTTS.audioCache.readyIndices(
            articleID: articleID,
            paragraphCount: paragraphCount,
            engineID: localID.rawValue,
            voiceID: voice
        )
    }
}
