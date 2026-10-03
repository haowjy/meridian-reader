import Foundation
import AVFoundation
import Observation

/// Listen façade for UI. Phase / playhead live in `playback` (PlaybackSessionState); views read
/// the published copies below it. Each utterance is bound to one `ListenEngine` (Apple or the
/// on-device engine), which reports events; engines never clear the session themselves.
/// See docs/LISTEN_PLAYBACK.md.
@MainActor
@Observable
final class SpeechController {
    // Exactly one instance per process: built by `AppComposition` (composition root) and
    // injected via ReaderApp + the environment default. A second instance would warm a second
    // copy of the local model.
    private let voiceDefaultsKey = "reader.selectedVoiceIdentifier"
    private let languageDefaultsKey = "reader.selectedLanguageCode"
    private let rateDefaultsKey = "reader.rateMultiplier"
    static let languageAutomaticKey = "reader.languageAutomatic"

    /// Single source of truth for Listen phase + position. Not observed directly: every change is
    /// copied into the published properties below, each assigned only when its value changes.
    @ObservationIgnored private(set) var playback = PlaybackSessionState() {
        didSet {
            if playback.resumePoint != oldValue.resumePoint { saveResumePoint() }
            publishPlayback()
        }
    }
    /// Durable "what is playing" point for crash auto-resume (nil: tests that don't want it).
    @ObservationIgnored private let resumePoints: ListenResumePointStore?

    // MARK: Published playback (what views observe)
    //
    // Observation tracks stored properties one by one. The in-paragraph offset moves several
    // times a second while playing; keeping it apart means a view that reads only the article,
    // phase or paragraph is not redrawn for it. Read `spokenUTF16Offset` only in small leaf views
    // (scrubber thumb, mini-player fill, progress reporter).

    private(set) var activeSessionID: UUID?
    private(set) var document: ParagraphDocument = .empty
    private(set) var playbackPhase: PlaybackPhase = .idle
    private(set) var currentParagraphIndex = 0
    private(set) var spokenUTF16Offset = 0

    /// What the listen bar shows from the engine. Engine state isn't observable, so
    /// `sampleListenStatus` takes this on every playback change and every engine
    /// `statusChanged`, and bumps `listenStatusRevision` only when it differs: views that show it
    /// (`showsPauseIcon`, `isBufferingNext`, `renderNote`) redraw exactly when it changes.
    private struct ListenStatus: Equatable {
        var showsPause = false
        var bufferingNext = false
        var renderNote: String?
    }
    @ObservationIgnored private var listenStatus = ListenStatus()
    private var listenStatusRevision = 0

    // MARK: Background listening (audio session, lock screen, interruptions)

    /// `.playback` / `.spokenAudio`; activated on play/resume, deactivated on stop/finish.
    let audioSession: ListenAudioSession
    /// Lock screen / Control Center info + remote commands (→ `handleRemoteCommand` → Session).
    let nowPlaying: NowPlayingController
    @ObservationIgnored private var interruptionPolicy = ListenInterruptionPolicy()
    private struct NowPlayingMeta {
        var id: UUID
        var title: String?
        var site: String?
        var artwork: Data?
    }
    @ObservationIgnored private var nowPlayingMeta: NowPlayingMeta?
    /// Called when an article plays to its end (e.g. drop it from "Continue listening").
    @ObservationIgnored var onArticleFinished: ((UUID) -> Void)?
    @ObservationIgnored private var runStateObserver: NSObjectProtocol?
    /// Debug panel snapshot and background-stretch tracking.
    @ObservationIgnored private(set) lazy var diagnostics = ListenDiagnostics(speech: self)

    let localTTS: LocalTTSCoordinator
    @ObservationIgnored private let appleEngine: ListenEngine
    @ObservationIgnored let localEngine: LocalListenEngine
    private var listenEngines: [ListenEngine] { [appleEngine, localEngine] }

    /// Developer Listen debug sheet (Settings, Debug chip, or long-press play).
    var showListenDebug = false
    /// When true, the listen bar shows a Debug chip that toggles the bake overlay.
    /// Persisted; Settings → Listen → Listen debug.
    var listenDebugEnabled: Bool {
        didSet { UserDefaults.standard.set(listenDebugEnabled, forKey: Self.listenDebugEnabledKey) }
    }
    /// Developer options (Debug rows, Listen debug, long-press-play panel). Off by default in
    /// Release; see `DeveloperOptions`.
    var developerOptionsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(developerOptionsEnabled, forKey: DeveloperOptions.defaultsKey)
            if !developerOptionsEnabled {
                showBakeDebugOverlay = false
                showListenDebug = false
            }
        }
    }
    /// The listen bar's Debug chip / bake overlay: Listen debug on AND developer options on.
    var showsListenDebugUI: Bool { developerOptionsEnabled && listenDebugEnabled }
    /// Inline bake debug strip above the listen controls (chip toggle).
    var showBakeDebugOverlay = false
    private static let listenDebugEnabledKey = "reader.listenDebugEnabled"

    /// The engine the live utterance is bound to (nil: nothing speaking or held). Set in `speak`,
    /// cleared when the engines stop.
    private struct EngineBinding {
        var route: ListenRoute
        var engine: ListenEngine
        /// Paragraph Apple is finishing before the on-device engine takes over (`EngineHandover`).
        var handoverAfterParagraph: Int?
    }
    @ObservationIgnored private var binding: EngineBinding?
    /// The engine every command goes to (nil: nothing speaking or held).
    var activeEngine: ListenEngine? { binding?.engine }

    private func engine(for route: ListenRoute) -> ListenEngine {
        switch route {
        case .apple: return appleEngine
        case .local: return localEngine
        }
    }

    /// The engine `speak` picks now: the on-device engine once it is loaded and speaks this
    /// article's language, else Apple.
    private var wantedRoute: ListenRoute {
        guard let id = localTTS.synth.state.readyEngineID, localTTS.engines.supports(id),
              languageResolution.engineID.isLocal else { return .apple }
        return .local(id, voice: localTTS.voice(for: id))
    }

    // MARK: - Language

    /// Settings → Language → "Automatic (match article)" (default). Off = `selectedLanguageCode`.
    var languageAutomatic: Bool {
        didSet { UserDefaults.standard.set(languageAutomatic, forKey: Self.languageAutomaticKey) }
    }

    /// Detected language of the prepared session's article (nil = unknown / none prepared).
    private(set) var sessionDetectedLanguage: String?

    /// Engine the language picker would use: the active local engine (selected or pending),
    /// else the selected one.
    var languageEngineDescriptor: EngineDescriptor? {
        localTTS.engines.descriptor(localTTS.activeLocalEngineID ?? localTTS.selectedEngineID)
    }

    /// Language + engine for an article with `detected` language under the current settings.
    func languageResolution(detected: String?) -> ListenLanguageResolution {
        ListenLanguageResolution.resolve(
            automatic: languageAutomatic,
            manualCode: selectedLanguageCode,
            detectedCode: detected,
            selectedEngine: languageEngineDescriptor
        )
    }

    /// Resolution for the prepared session (Settings / listen bar).
    var languageResolution: ListenLanguageResolution { languageResolution(detected: sessionDetectedLanguage) }

    /// Language the current session speaks in.
    var effectiveLanguageCode: String { languageResolution.languageCode }

    /// Apple voice for the current session: the user's pick when it speaks the effective
    /// language, else the best installed voice for that language.
    var effectiveAppleVoice: AVSpeechSynthesisVoice? {
        let code = effectiveLanguageCode
        if let voice = selectedVoice, ListenLanguage.baseCode(voice.language) == ListenLanguage.baseCode(code) {
            return voice
        }
        return VoiceCatalog.bestVoice(forLanguage: code)
    }

    /// Cache voice key for local-engine audio (e.g. "kokoro.af_heart").
    var cacheVoiceID: String { localTTS.cacheVoiceID(appleVoice: selectedVoiceIdentifier) }

    var isPlaying: Bool { playbackPhase == .playing }

    /// Copies `playback` into the published properties (only the ones that changed), then
    /// refreshes what is derived from it: the lock screen and the listen-bar status.
    private func publishPlayback() {
        var nowPlayingChanged = false
        if activeSessionID != playback.articleID { activeSessionID = playback.articleID; nowPlayingChanged = true }
        if document != playback.document { document = playback.document; nowPlayingChanged = true }
        if playbackPhase != playback.phase { playbackPhase = playback.phase; nowPlayingChanged = true }
        if currentParagraphIndex != playback.playhead { currentParagraphIndex = playback.playhead; nowPlayingChanged = true }
        if spokenUTF16Offset != playback.utf16Offset { spokenUTF16Offset = playback.utf16Offset }
        if nowPlayingChanged { refreshNowPlaying() }
        sampleListenStatus()
    }

    private func sampleListenStatus() {
        let status = ListenStatus(showsPause: activeSessionShowsPause(), bufferingNext: engineIsBufferingNext(),
                                  renderNote: currentRenderNote())
        guard status != listenStatus else { return }
        listenStatus = status
        listenStatusRevision &+= 1
    }

    /// Pause (not Play) on the active session's button.
    func showsPauseIcon(for sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        _ = listenStatusRevision
        return activeSessionShowsPause()
    }

    /// Listen intent is active but nothing is audible and more audio is on its way (the bound
    /// engine is waiting for it, e.g. the on-device render queue). Not the same as paused.
    var isBufferingNext: Bool {
        _ = listenStatusRevision
        return engineIsBufferingNext()
    }

    /// Listen-bar note while the paragraph playing is Apple TTS instead of the local engine.
    var renderNote: String? {
        _ = listenStatusRevision
        return currentRenderNote()
    }

    /// Audible audio always shows Pause, even while the phase briefly disagrees (the engine
    /// hasn't reported a change yet).
    private func activeSessionShowsPause() -> Bool {
        playback.articleID != nil && (engineSnapshot().isAudible || playback.phase == .playing)
    }

    private func engineIsBufferingNext() -> Bool {
        playback.articleID != nil && playback.phase == .playing && activeEngine?.isWaitingForAudio == true
    }

    private func currentRenderNote() -> String? {
        guard playback.phase == .playing || playback.phase == .paused else { return nil }
        return activeEngine?.sourceNote
    }

    /// The session's resume point changed (playing a new paragraph, paused, stopped).
    private func saveResumePoint() {
        guard let resumePoints else { return }
        if let point = playback.resumePoint {
            resumePoints.save(article: point.article, paragraph: point.paragraph)
        } else {
            resumePoints.clear()
        }
    }

    static let rateOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var selectedLanguageCode: String {
        didSet { UserDefaults.standard.set(selectedLanguageCode, forKey: languageDefaultsKey) }
    }

    var rateMultiplier: Double {
        didSet {
            let clamped = min(2.0, max(0.75, rateMultiplier))
            if clamped != rateMultiplier {
                rateMultiplier = clamped
                return
            }
            UserDefaults.standard.set(rateMultiplier, forKey: rateDefaultsKey)
            // Every engine keeps the speed; the bound one applies it to what is playing.
            for engine in listenEngines { engine.setRate(rateMultiplier) }
            refreshNowPlaying()
        }
    }

    var selectedVoiceIdentifier: String? {
        didSet { UserDefaults.standard.set(selectedVoiceIdentifier, forKey: voiceDefaultsKey) }
    }

    /// `localTTS` / `audioSession` / `nowPlaying` / `appleEngine` / `resumePoints` are injectable
    /// for unit tests (temp cache, no process-wide audio session or remote command registration, a
    /// scripted Apple engine, no resume file).
    init(engines: EngineRegistry,
         localTTS: LocalTTSCoordinator? = nil,
         audioSession: ListenAudioSession? = nil,
         nowPlaying: NowPlayingController? = nil,
         appleEngine: ListenEngine? = nil,
         resumePoints: ListenResumePointStore? = .shared) {
        let coordinator = localTTS ?? LocalTTSCoordinator(engines: engines)
        self.localTTS = coordinator
        self.appleEngine = appleEngine ?? AppleListenEngine()
        self.localEngine = LocalListenEngine(coordinator: coordinator)
        self.audioSession = audioSession ?? ListenAudioSession()
        self.nowPlaying = nowPlaying ?? NowPlayingController()
        self.resumePoints = resumePoints
        let storedLanguage = UserDefaults.standard.string(forKey: languageDefaultsKey)
        let fallback = Locale.current.language.languageCode.map {
            "\($0.identifier)-\(Locale.current.region?.identifier ?? "US")"
        } ?? "en-US"
        self.selectedLanguageCode = storedLanguage ?? Locale.preferredLanguages.first ?? fallback
        // `double(forKey:)` also parses a launch-argument string ("-reader.rateMultiplier 1", UI tests).
        // UI tests start at 1× (hermetic) unless they pass the rate explicitly.
        let args = ProcessInfo.processInfo.arguments
        let ignoreStoredRate = args.contains("-uiTesting") && !args.contains("-\(rateDefaultsKey)")
        let storedRate = !ignoreStoredRate && UserDefaults.standard.object(forKey: rateDefaultsKey) != nil
            ? UserDefaults.standard.double(forKey: rateDefaultsKey) : 1.0
        self.rateMultiplier = (0.25...4).contains(storedRate) ? storedRate : 1.0
        self.selectedVoiceIdentifier = UserDefaults.standard.string(forKey: voiceDefaultsKey)
        self.listenDebugEnabled = UserDefaults.standard.bool(forKey: Self.listenDebugEnabledKey)
        self.developerOptionsEnabled = DeveloperOptions.load()
        self.languageAutomatic = (UserDefaults.standard.object(forKey: Self.languageAutomaticKey) as? Bool) ?? true
        // Init skips didSet — keep overlays off when Release reset / default leaves options off.
        if !developerOptionsEnabled {
            showBakeDebugOverlay = false
            showListenDebug = false
        }
        // Bake / warm only articles the local engine can speak (others speak with Apple).
        self.localTTS.localLanguageGate = { [weak self] paragraphs in
            guard let self else { return true }
            return self.languageResolution(detected: ListenLanguage.detectCached(paragraphs: paragraphs)).engineID.isLocal
        }
        self.localTTS.onEngineChange = { [weak self] in self?.localEngineChanged() }
        for engine in listenEngines {
            engine.setRate(rateMultiplier)
            engine.onEvent = { [weak self, unowned engine] event in self?.handle(event, from: engine) }
        }
        // Category only; the session is activated when playback starts (activating at launch
        // interrupted other apps' audio just for opening Reader). Non-mixable so Reader becomes
        // the Now Playing app (lock screen controls); `UIBackgroundModes: audio` keeps it playing.
        self.audioSession.configure()
        self.audioSession.onEvent = { [weak self] event in self?.handleAudioSessionEvent(event) }
        self.audioSession.startObserving()
        self.nowPlaying.attach(rateOptions: Self.rateOptions) { [weak self] command in
            self?.handleRemoteCommand(command) ?? .noActionableNowPlayingItem
        }
        runStateObserver = NotificationCenter.default.addObserver(
            forName: AppRunState.didChange, object: self.localTTS.synthQueue.runState, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appRunStateChanged() }
        }
    }

    // MARK: - Display

    var selectedVoice: AVSpeechSynthesisVoice? {
        guard let id = selectedVoiceIdentifier else { return nil }
        return AVSpeechSynthesisVoice(identifier: id)
    }

    var selectedVoiceDisplayName: String { selectedVoice?.name ?? "System default" }
    var selectedLanguageDisplayName: String { VoiceCatalog.languageName(for: selectedLanguageCode) }

    var rateDisplayLabel: String {
        let rounded = (rateMultiplier * 100).rounded() / 100
        if abs(rounded - 1.0) < 0.01 { return "1×" }
        return String(format: "%g×", rounded)
    }

    var isPrepared: Bool { activeSessionID != nil && !document.isEmpty }
    var isActive: Bool { activeSessionID != nil && (playbackPhase == .playing || playbackPhase == .paused) }

    var canSkipToPreviousParagraph: Bool { isPrepared && currentParagraphIndex > 0 }
    var canSkipToNextParagraph: Bool { isPrepared && currentParagraphIndex + 1 < document.count }

    func isPrepared(sessionID: UUID) -> Bool {
        activeSessionID == sessionID && isPrepared
    }


    // MARK: - Session API (intents)

    func prepare(_ session: SpeechSession, startingParagraph: Int = 0) {
        if session.title != nil || nowPlayingMeta?.id != session.id {
            nowPlayingMeta = NowPlayingMeta(id: session.id, title: session.title, site: session.site, artwork: session.artwork)
        }
        let detected = session.detectedLanguage ?? ListenLanguage.detectCached(paragraphs: session.document.paragraphs)
        if sessionDetectedLanguage != detected { sessionDetectedLanguage = detected }
        if playback.articleID == session.id, !playback.document.isEmpty { return }
        execute(playback.handle(.stop, engine: engineSnapshot()))
        playback.bind(articleID: session.id, document: session.document, startingAt: startingParagraph)
    }

    func toggle(_ session: SpeechSession, resumeParagraph: Int? = nil, resumeUTF16Offset: Int? = nil) {
        interruptionPolicy.noteUserIntent()
        if playback.articleID != session.id {
            prepare(session, startingParagraph: resumeParagraph ?? 0)
            placeResumeOffset(resumeUTF16Offset, paragraph: resumeParagraph ?? 0)
            perform(.play(from: resumeParagraph ?? 0))
            return
        }
        if !playback.isPrepared {
            prepare(session, startingParagraph: resumeParagraph ?? playback.playhead)
            placeResumeOffset(resumeUTF16Offset, paragraph: resumeParagraph ?? playback.playhead)
        }
        // Reconcile before toggle so stale .paused cannot block Pause while audible.
        playback.reconcile(with: engineSnapshot())
        if playback.phase == .prepared || playback.phase == .idle || playback.phase == .finished {
            let index = resumeParagraph ?? playback.playhead
            perform(.play(from: index))
        } else {
            perform(.toggle)
        }
    }

    /// Prepared (not playing): put the playhead on the stored / scrubbed sentence so Play starts
    /// there instead of at the paragraph start.
    private func placeResumeOffset(_ offset: Int?, paragraph: Int) {
        guard let offset, playback.phase == .prepared, !document.isEmpty,
              document.index(containingUTF16Offset: offset) == paragraph else { return }
        perform(.seekOffset(utf16: offset))
    }

    func start(_ session: SpeechSession, fromParagraph index: Int) {
        prepare(session, startingParagraph: index)
        guard !document.isEmpty else { return }
        perform(.play(from: index))
    }

    func skipToPreviousParagraph() {
        guard isPrepared else { return }
        perform(.skip(delta: -1))
    }

    func skipToNextParagraph() {
        guard isPrepared else { return }
        perform(.skip(delta: 1))
    }

    /// Scrubber: move `session`'s playhead to `paragraph` without changing play/pause state
    /// (a proper paused seek, not stop-and-reload). No-op unless `session` is the prepared one.
    func seek(_ session: SpeechSession, toParagraph paragraph: Int) {
        guard isPrepared(sessionID: session.id) else { return }
        interruptionPolicy.noteUserIntent()
        perform(.seek(paragraph: paragraph))
    }

    /// Scrubber inside a paragraph: move to document offset `utf16` (a sentence start)
    /// without changing play/pause state. Local engine: starts at the synth chunk holding that
    /// sentence, offset into its audio; Apple: speaks from that character.
    func seek(_ session: SpeechSession, toUTF16Offset utf16: Int) {
        guard isPrepared(sessionID: session.id) else { return }
        interruptionPolicy.noteUserIntent()
        perform(.seekOffset(utf16: utf16))
    }

    /// Where a play / seek of `paragraph` starts: the session's sub-paragraph offset when it lies
    /// in that paragraph (scrubbed to a sentence), else the paragraph start.
    private func startOffset(forParagraph paragraph: Int) -> Int {
        guard !document.isEmpty else { return 0 }
        let offset = playback.utf16Offset
        return document.index(containingUTF16Offset: offset) == paragraph
            ? offset : document.startUTF16Offset(forParagraph: paragraph)
    }

    /// Title of the loaded article (mini player). nil when nothing is loaded.
    var nowPlayingTitle: String? {
        guard let id = activeSessionID, nowPlayingMeta?.id == id else { return nil }
        return nowPlayingMeta?.title
    }

    func pause() {
        interruptionPolicy.noteUserIntent()
        perform(.pause)
    }

    func resume() { perform(.resume) }

    func stop() {
        interruptionPolicy.noteUserIntent()
        perform(.stop)
        // Listen preempts bake; on stop, resume gap-fill so save-time work still lands on disk.
        finishSession(restartBake: true)
    }

    /// Swap the live session's identity without stopping audio. Only needed when Save lands on a
    /// different id than the reader key (legacy saved row found mid-read); v2 saves reuse the key,
    /// so this is a no-op.
    func rekeyActiveSession(from oldID: UUID, to newID: UUID) {
        guard oldID != newID, playback.articleID == oldID else { return }
        if nowPlayingMeta?.id == oldID { nowPlayingMeta?.id = newID }
        playback.rekey(to: newID)
        localEngine.rekey(to: newID)
    }

    /// The on-device engine changed state or voice (`LocalTTSCoordinator.onEngineChange`): move the
    /// live utterance to the engine `speak` would pick now, when `EngineHandover` says so.
    private func localEngineChanged() {
        guard let bound = binding?.route, playback.phase == .playing || playback.phase == .paused else { return }
        switch EngineHandover.decide(bound: bound, wanted: wantedRoute, phase: playback.phase) {
        case .none:
            binding?.handoverAfterParagraph = nil
        case .restartNow:
            speak(fromUTF16Offset: playback.utf16Offset, startPaused: playback.phase == .paused)
        case .atNextParagraph:
            if binding?.handoverAfterParagraph == nil { binding?.handoverAfterParagraph = playback.playhead }
        }
    }

    /// Apple started speaking `paragraph`: a pending handover happens here, at its start.
    private func handOverIfDue(atParagraph paragraph: Int) {
        guard let after = binding?.handoverAfterParagraph, paragraph > after else { return }
        guard wantedRoute != binding?.route else {
            binding?.handoverAfterParagraph = nil
            return
        }
        speak(fromUTF16Offset: document.startUTF16Offset(forParagraph: paragraph), startPaused: false)
    }

    // MARK: - Voice / rate

    /// Settings → Language → Automatic (match article).
    func selectAutomaticLanguage() {
        guard !languageAutomatic else { return }
        languageAutomatic = true
        languageSettingChanged()
    }

    /// Settings → Language → a specific language (turns Automatic off).
    func selectLanguage(_ code: String) {
        guard languageAutomatic || selectedLanguageCode != code else { return }
        let codeChanged = selectedLanguageCode != code
        languageAutomatic = false
        selectedLanguageCode = code
        if codeChanged { selectedVoiceIdentifier = nil }
        languageSettingChanged()
    }

    /// Language change can move the article between the local engine and Apple: restart the
    /// utterance and let the bake queue / marks follow.
    private func languageSettingChanged() {
        localTTS.noteBakeMarksChanged()
        restartUtteranceIfNeeded()
    }

    func selectVoice(identifier: String?) {
        let changed = selectedVoiceIdentifier != identifier
        selectedVoiceIdentifier = identifier
        if !languageAutomatic, let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            selectedLanguageCode = voice.language
        }
        guard changed else { return }
        restartUtteranceIfNeeded()
    }

    func setRateMultiplier(_ value: Double) { rateMultiplier = value }

    func cycleRate() {
        if let idx = Self.rateOptions.firstIndex(where: { abs($0 - rateMultiplier) < 0.01 }) {
            setRateMultiplier(Self.rateOptions[(idx + 1) % Self.rateOptions.count])
        } else {
            setRateMultiplier(1.0)
        }
    }

    // MARK: - Remote commands (lock screen / Control Center / headphones)

    /// Every remote command becomes a Session intent — the same path as the on-screen buttons.
    @discardableResult
    func handleRemoteCommand(_ command: RemoteCommand) -> RemoteCommandOutcome {
        guard playback.isPrepared else { return .noActionableNowPlayingItem }
        interruptionPolicy.noteUserIntent()
        ListenTimingLog.log("remote_command", [
            "cmd": String(describing: command), "phase": String(describing: playback.phase), "p": playback.playhead,
        ])
        if case .changePlaybackRate(let rate) = command {
            let nearest = Self.rateOptions.min { abs($0 - rate) < abs($1 - rate) } ?? 1.0
            setRateMultiplier(nearest)
            return .success
        }
        if command == .nextTrack, !canSkipToNextParagraph { return .commandFailed }
        if command == .togglePlayPause { playback.reconcile(with: engineSnapshot()) }
        guard let intent = command.intent else { return .commandFailed }
        perform(intent)
        return .success
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
        case .none:
            break
        }
    }

    // MARK: - Now Playing

    private func refreshNowPlaying() {
        guard let id = playback.articleID, playback.isPrepared,
              playback.phase == .playing || playback.phase == .paused else {
            nowPlaying.update(nil)
            return
        }
        let meta = nowPlayingMeta?.id == id ? nowPlayingMeta : nil
        let info = NowPlayingInfo(
            title: meta?.title ?? "Reader", site: meta?.site,
            paragraph: playback.playhead + 1, paragraphCount: playback.paragraphCount,
            isPlaying: playback.phase == .playing, rate: rateMultiplier, artwork: meta?.artwork)
        nowPlaying.update(info, canNext: playback.playhead + 1 < playback.paragraphCount, canPrevious: true)
    }

    // MARK: - Foreground / background

    private func appRunStateChanged() {
        let phase = localTTS.synthQueue.runState.phase
        if phase == .active { activeEngine?.appDidBecomeActive() }
        diagnostics.appPhaseChanged(phase)
    }

    // MARK: - Intent execution

    private func perform(_ intent: PlaybackIntent) {
        let commands = playback.handle(intent, engine: engineSnapshot())
        execute(commands)
    }

    private func execute(_ commands: [PlaybackCommand]) {
        for command in commands {
            switch command {
            case .enginePlay(let from):
                speak(fromUTF16Offset: startOffset(forParagraph: from), startPaused: false)
            case .enginePause:
                pauseEngines()
            case .engineResume:
                resumeEngines()
            case .engineStop:
                stopEngines()
            case .engineSeek(let paragraph):
                let offset = startOffset(forParagraph: paragraph)
                let startPaused = playback.phase == .paused
                speak(fromUTF16Offset: offset, startPaused: startPaused)
            }
        }
    }

    func engineSnapshot() -> PlaybackEngineSnapshot {
        activeEngine?.snapshot ?? PlaybackEngineSnapshot(isAudible: false, isPaused: false)
    }

    /// The engine confirms with `becamePaused` (the on-device player at once, Apple at the next word).
    private func pauseEngines() {
        activeEngine?.pause()
    }

    private func resumeEngines() {
        audioSession.activate()
        guard let engine = activeEngine, engine.snapshot.isPaused || engine.snapshot.isAudible else {
            // Nothing held: play from the playhead (the scrubbed sentence, if any).
            speak(fromUTF16Offset: startOffset(forParagraph: playback.playhead), startPaused: false)
            return
        }
        engine.resume()
    }

    private func stopEngines() {
        binding = nil
        for engine in listenEngines { engine.stop() }
        sampleListenStatus()
    }

    /// Events from engines. Only the bound engine's count: a stopped or replaced engine's late
    /// callback (a cancelled utterance, a cleared player) must not move the session.
    private func handle(_ event: PlaybackEngineEvent, from engine: ListenEngine) {
        guard engine === activeEngine else { return }
        switch event {
        case .becameAudible, .becamePaused:
            playback.handle(event)
        case .position(let paragraph, _):
            playback.handle(event)
            handOverIfDue(atParagraph: paragraph)
        case .statusChanged:
            sampleListenStatus()
        case .finished:
            completeArticle(restartBake: true)
        }
    }

    private func restartUtteranceIfNeeded() {
        guard playback.isPrepared else { return }
        guard playback.phase == .playing || playback.phase == .paused else { return }
        speak(fromUTF16Offset: playback.utf16Offset, startPaused: playback.phase == .paused)
    }

    private func speak(fromUTF16Offset offset: Int, startPaused: Bool) {
        if !startPaused { audioSession.activate() }
        stopEngines()

        playback.moveTo(utf16: offset)
        let start = playback.utf16Offset
        guard start < (document.joinedText as NSString).length, let articleID = playback.articleID else {
            completeArticle(restartBake: false)
            return
        }

        let route = wantedRoute
        let engine = engine(for: route)
        binding = EngineBinding(route: route, engine: engine)
        // The phase already says playing or paused (the intent that led here set it); the engine
        // confirms with its own events.
        engine.play(ListenPlayRequest(articleID: articleID, document: document, utf16Offset: start,
                                      startPaused: startPaused, appleVoice: effectiveAppleVoice))
    }

    /// Played to the end (not stopped): note it, then tear the session down.
    private func completeArticle(restartBake: Bool) {
        let id = playback.articleID
        playback.handle(.finished)
        finishSession(restartBake: restartBake)
        if let id { onArticleFinished?(id) }
    }

    private func finishSession(restartBake: Bool) {
        let articleID = playback.articleID
        let paragraphs = playback.document.paragraphs
        let voiceID = cacheVoiceID
        stopEngines()
        playback.clear()
        // Let other apps' audio resume (Browse ✕ / end of article).
        audioSession.deactivate()
        if restartBake, let articleID, !paragraphs.isEmpty {
            // Return-to-top gap fill so any paragraphs above the listen playhead still bake.
            localTTS.startBakeIfNeeded(
                articleID: articleID,
                paragraphs: paragraphs,
                voiceID: voiceID
            )
        }
    }

    // MARK: - Bake-ready marks (local engines only)

    /// When a local engine is selected/pending, returns indices with a usable CAF for the article
    /// in the CURRENT voice (stale old-voice units don't count).
    /// `nil` means hide marks (Apple path — no CAF bake, don't fake "not ready").
    func bakeReadyParagraphIndices(articleID: UUID, paragraphCount: Int, detectedLanguage: String? = nil) -> Set<Int>? {
        guard let localID = localTTS.activeLocalEngineID, localTTS.engines.supports(localID),
              localTTS.engines.descriptor(localID)?.supportsBakeCache == true else { return nil }
        // Article speaks with Apple (language the engine can't speak): no marks, like Apple.
        let detected = detectedLanguage ?? (articleID == activeSessionID ? sessionDetectedLanguage : nil)
        guard languageResolution(detected: detected).engineID.isLocal else { return nil }
        // Hide until unit count is known — empty Set would mark every HTML block not-ready.
        guard paragraphCount > 0 else { return nil }
        _ = localTTS.bakeMarksRevision
        _ = localTTS.audioCache.contentRevision
        return localTTS.audioCache.readyIndices(
            articleID: articleID,
            paragraphCount: paragraphCount,
            engineID: self.localTTS.cacheEngineID,
            voiceID: cacheVoiceID
        )
    }
}
