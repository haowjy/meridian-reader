import Foundation
import AVFoundation
import Observation

/// Listen façade for UI. Phase / playhead live in `playback` (PlaybackSessionState).
/// Engines are commanded; they never clear the session themselves without an event.
/// See docs/LISTEN_PLAYBACK.md.
@MainActor
@Observable
final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    // Exactly one instance per process: built by `AppComposition` (composition root) and
    // injected via ReaderApp + the environment default. A second instance would warm a second
    // copy of the local model.
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    private let voiceDefaultsKey = "reader.selectedVoiceIdentifier"
    private let languageDefaultsKey = "reader.selectedLanguageCode"
    private let rateDefaultsKey = "reader.rateMultiplier"
    static let languageAutomaticKey = "reader.languageAutomatic"

    /// Single source of truth for Listen phase + playhead.
    private(set) var playback = PlaybackSessionState() {
        didSet { refreshNowPlaying() }
    }

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
    #if canImport(UIKit)
    /// Keeps the app alive while the player is starved in the background (e.g. rendering an
    /// Apple-fallback paragraph) — with nothing audible iOS may suspend the app.
    @ObservationIgnored private lazy var playbackGrace = BackgroundGrace(name: "ReaderListenGap")
    #endif
    @ObservationIgnored private var deferralsAtBackground = 0
    /// Debug: what happened during the last stretch in the background.
    private(set) var lastBackgroundSummary = "—"

    private var utteranceBaseOffset = 0
    private var suppressCancelSideEffects = false
    private var speakGeneration = 0

    let localTTS: LocalTTSCoordinator

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
    /// Bumped while local-engine listen may be awaiting the next CAF so UI can show buffering.
    private(set) var bufferingRevision = 0
    private var bufferingPollTask: Task<Void, Never>?

    private var usesLocalPlayback: Bool {
        localTTS.selectedEngineID.isLocal
            && localTTS.engines.supports(localTTS.selectedEngineID)
            && localTTS.localHostReady
            && languageResolution.engineID.isLocal
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
    private var languageEngineDescriptor: EngineDescriptor? {
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

    // MARK: - Compatibility projections (UI binds these)

    var activeSessionID: UUID? { playback.articleID }
    var document: ParagraphDocument { playback.document }
    var currentParagraphIndex: Int { playback.playhead }
    var spokenUTF16Offset: Int { playback.utf16Offset }

    enum PlaybackState: Equatable {
        case idle, prepared, playing, paused
    }

    var playbackState: PlaybackState {
        switch playback.phase {
        case .idle, .finished: return .idle
        case .prepared: return .prepared
        case .playing: return .playing
        case .paused: return .paused
        }
    }

    var isPlaying: Bool { playback.phase == .playing }
    var isPaused: Bool { playback.phase == .paused }

    /// True when listen intent is still active but the player has no audible unit and more
    /// paragraphs remain (awaiting GlobalSynthQueue / producer). Not the same as paused.
    /// Reads `bufferingRevision` so SwiftUI invalidates while polling.
    var isBufferingNext: Bool {
        _ = bufferingRevision
        guard usesLocalPlayback else { return false }
        guard playback.articleID != nil else { return false }
        guard playback.phase == .playing else { return false }
        let eng = localTTS.localEngineInstance
        if eng.isPaused { return false }
        if eng.isAudible { return false }
        let hasMoreUnits = playback.playhead + 1 < playback.document.count
            || eng.debugNextProduceIndex < playback.document.count
            || eng.debugAwaitingMore
        guard hasMoreUnits else { return false }
        return eng.debugAwaitingMore || eng.debugProducerActive || eng.debugBufferedCount == 0
    }

    private func startBufferingPoll() {
        bufferingPollTask?.cancel()
        bufferingPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.bufferingRevision &+= 1
                if self.playback.phase != .playing {
                    break
                }
                self.updateLocalPlaybackOffset()
                #if canImport(UIKit)
                if self.localTTS.synthQueue.runState.phase == .background, self.isBufferingNext {
                    self.playbackGrace.begin()
                } else {
                    self.playbackGrace.end()
                }
                #endif
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func stopBufferingPoll() {
        bufferingPollTask?.cancel()
        bufferingPollTask = nil
        #if canImport(UIKit)
        playbackGrace.end()
        #endif
        bufferingRevision &+= 1
    }

    static let rateOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// Speed change policy: local playback changes the player's rate in place; only the Apple
    /// synthesizer path re-speaks (from the current word).
    static func rateChangeRestartsUtterance(usesLocalPlayback: Bool) -> Bool { !usesLocalPlayback }

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
            // Local engine: time-stretch the player in place (Nav I) — the sentence keeps going at
            // the new speed, nothing restarts. Apple's synthesizer can't change an utterance's
            // rate, so it restarts from the word being spoken (`willSpeakRange` offset).
            localTTS.localEngineInstance.setPlaybackRate(Float(rateMultiplier))
            if Self.rateChangeRestartsUtterance(usesLocalPlayback: usesLocalPlayback) {
                restartUtteranceIfNeeded()
            }
            refreshNowPlaying()
        }
    }

    var selectedVoiceIdentifier: String? {
        didSet { UserDefaults.standard.set(selectedVoiceIdentifier, forKey: voiceDefaultsKey) }
    }

    /// `localTTS` / `audioSession` / `nowPlaying` are injectable for unit tests (temp cache,
    /// no process-wide audio session or remote command registration).
    init(engines: EngineRegistry,
         localTTS: LocalTTSCoordinator? = nil,
         audioSession: ListenAudioSession? = nil,
         nowPlaying: NowPlayingController? = nil) {
        self.localTTS = localTTS ?? LocalTTSCoordinator(engines: engines)
        self.audioSession = audioSession ?? ListenAudioSession()
        self.nowPlaying = nowPlaying ?? NowPlayingController()
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
        super.init()
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
        synthesizer.delegate = self
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
        wireLocalEngine()
        self.localTTS.localEngineInstance.setPlaybackRate(Float(rateMultiplier))
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

    var paragraphCount: Int { playback.paragraphCount }
    var isPrepared: Bool { playback.isPrepared }
    var isActive: Bool { playback.articleID != nil && (isPlaying || isPaused) }

    var canSkipToPreviousParagraph: Bool { isPrepared && currentParagraphIndex > 0 }
    var canSkipToNextParagraph: Bool { isPrepared && currentParagraphIndex + 1 < document.count }

    func isActive(sessionID: UUID) -> Bool {
        playback.articleID == sessionID && (isPlaying || isPaused)
    }

    func isPrepared(sessionID: UUID) -> Bool {
        playback.articleID == sessionID && isPrepared
    }

    func showsPauseIcon(for sessionID: UUID) -> Bool {
        guard playback.articleID == sessionID else { return false }
        let snap = engineSnapshot()
        // Audible audio always shows Pause, even if phase briefly disagrees.
        return snap.isAudible || playback.phase == .playing
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
        utteranceBaseOffset = playback.utf16Offset
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
    /// there instead of at the paragraph start (Nav I).
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

    /// Scrubber inside a paragraph (Nav I): move to document offset `utf16` (a sentence start)
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
        guard let id = playback.articleID, nowPlayingMeta?.id == id else { return nil }
        return nowPlayingMeta?.title
    }

    func pause() {
        interruptionPolicy.noteUserIntent()
        perform(.pause)
    }

    func resume() { perform(.resume) }

    func stop() {
        interruptionPolicy.noteUserIntent()
        suppressCancelSideEffects = false
        perform(.stop)
        // Listen preempts bake; on stop, resume gap-fill so save-time work still lands on disk.
        finishSession(restartBake: true)
    }

    /// Swap the live session's identity without stopping audio (engine closures read
    /// `playback.articleID` lazily). Only needed when Save lands on a different id than the
    /// reader key (legacy saved row found mid-read); v2 saves reuse the key, so this is a no-op.
    func rekeyActiveSession(from oldID: UUID, to newID: UUID) {
        guard oldID != newID, playback.articleID == oldID else { return }
        if nowPlayingMeta?.id == oldID { nowPlayingMeta?.id = newID }
        playback.articleID = newID
        wireLocalEngine()
    }

    func applyEngineSelectionChange() {
        guard playback.isPrepared else { return }
        guard playback.phase == .playing || playback.phase == .paused else { return }
        let paused = playback.phase == .paused
        speak(fromUTF16Offset: playback.utf16Offset, startPaused: paused)
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
        let eng = localTTS.localEngineInstance
        var fields: [String: Any] = [
            "phase": phase.rawValue, "listen": String(describing: playback.phase),
            "engine": usesLocalPlayback ? eng.engineShortName : "Apple", "p": playback.playhead,
        ]
        switch phase {
        case .background:
            eng.backgroundStats = .init()
            deferralsAtBackground = localTTS.synthQueue.backgroundDeferrals
            fields["ready_ahead"] = readyAheadCount()
        case .active:
            if usesLocalPlayback, let from = eng.reclaimBackgroundFallbacks(), let id = playback.articleID {
                // Queue cursor → the restart paragraph before the worker picks its next chunk.
                localTTS.synthQueue.focusPlayhead(cacheKey: id, paragraph: from)
            }
            if eng.backgroundStats != .init() || localTTS.synthQueue.backgroundDeferrals > deferralsAtBackground {
                lastBackgroundSummary = eng.backgroundStats.label
                    + " · deferred \(localTTS.synthQueue.backgroundDeferrals - deferralsAtBackground)"
                fields["bg_summary"] = lastBackgroundSummary
            }
        case .inactive:
            break
        }
        #if canImport(UIKit)
        if phase != .background { playbackGrace.end() }
        #endif
        ListenTimingLog.log("app_phase", fields)
    }

    /// Consecutive paragraphs after the playhead already rendered in the current voice.
    func readyAheadCount() -> Int {
        guard let id = playback.articleID, usesLocalPlayback else { return 0 }
        var n = 0
        var i = playback.playhead + 1
        while i < playback.paragraphCount,
              localTTS.audioCache.audioURL(articleID: id, paragraphIndex: i,
                                           engineID: localTTS.cacheEngineID, voiceID: cacheVoiceID) != nil {
            n += 1
            i += 1
        }
        return n
    }

    /// Debug: how audio is being produced right now (foreground GPU / background / Apple).
    var renderModeLabel: String {
        let phase = localTTS.synthQueue.runState.phase
        guard usesLocalPlayback else { return "Apple TTS (AVSpeechSynthesizer) · \(phase.rawValue)" }
        let eng = localTTS.localEngineInstance
        let pace = RenderPace.shared.snapshot.speed.map { String(format: " · %.1f× real time", $0) } ?? ""
        if eng.hostRendersInBackground {
            switch phase {
            case .active, .inactive:
                return "\(phase.rawValue) · \(eng.engineShortName) ONNX CPU (\(eng.hostRoutingLabel ?? "cpu"))\(pace)"
            case .background:
                return "background · \(eng.engineShortName) ONNX CPU keeps rendering (playing article)\(pace)"
            }
        }
        switch phase {
        case .active:
            return "foreground · \(eng.engineShortName) Core ML (\(eng.hostRoutingLabel ?? "default"))"
        case .inactive:
            return "inactive · \(eng.engineShortName) for playhead only, bake-ahead held"
        case .background:
            return "background · no Core ML — baked audio + Apple fallback"
        }
    }

    /// Listen-bar note while the paragraph playing is Apple TTS instead of the local engine.
    var renderNote: String? {
        guard usesLocalPlayback, playback.phase == .playing || playback.phase == .paused,
              let reason = localTTS.localEngineInstance.currentAppleFallbackReason else { return nil }
        _ = bufferingRevision
        let name = localTTS.localEngineInstance.engineShortName
        switch reason {
        case "background": return "Apple voice · \(name) can't render in the background"
        case "behind": return "Apple voice for this paragraph · \(name) fell behind"
        default: return "Apple voice · \(name) couldn't render this paragraph"
        }
    }

    // MARK: - Intent execution

    private func perform(_ intent: PlaybackIntent) {
        let commands = playback.handle(intent, engine: engineSnapshot())
        execute(commands)
    }

    private func execute(_ commands: [PlaybackCommand]) {
        for command in commands {
            switch command {
            case .prepareDocument:
                break
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

    private func engineSnapshot() -> PlaybackEngineSnapshot {
        if usesLocalPlayback {
            let eng = localTTS.localEngineInstance
            return .init(isAudible: eng.isAudible || eng.isSpeaking, isPaused: eng.isPaused)
        }
        return .init(
            isAudible: synthesizer.isSpeaking && !synthesizer.isPaused,
            isPaused: synthesizer.isPaused
        )
    }

    private func pauseEngines() {
        if usesLocalPlayback {
            localTTS.localEngineInstance.pause()
            playback.handle(.becamePaused)
            stopBufferingPoll()
            return
        }
        if synthesizer.isSpeaking, !synthesizer.isPaused {
            synthesizer.pauseSpeaking(at: .word)
        }
        // Phase already set by intent; didPause confirms.
        if synthesizer.isPaused {
            playback.handle(.becamePaused)
        }
    }

    private func resumeEngines() {
        audioSession.activate()
        if usesLocalPlayback {
            let eng = localTTS.localEngineInstance
            if eng.isPaused {
                eng.resume()
            } else if !eng.isSpeaking && !eng.isAudible {
                // Nothing held — replay from the playhead (sentence, if scrubbed there).
                let offset = startOffset(forParagraph: playback.playhead)
                speak(fromUTF16Offset: offset, startPaused: false)
            }
            playback.handle(.becameAudible)
            startBufferingPoll()
            return
        }
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            playback.handle(.becameAudible)
        } else if synthesizer.isSpeaking {
            playback.handle(.becameAudible)
        } else {
            let offset = playback.utf16Offset
            speak(fromUTF16Offset: offset, startPaused: false)
        }
    }

    private func stopEngines() {
        stopBufferingPoll()
        localTTS.localEngineInstance.stop()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func wireLocalEngine() {
        let engine = localTTS.localEngineInstance
        engine.onParagraphIndexChange = { [weak self] idx in
            guard let self else { return }
            // Starting mid-paragraph (scrubbed to a sentence): keep that offset; a new paragraph
            // starts at its beginning.
            let utf16 = self.document.isEmpty ? nil : self.startOffset(forParagraph: idx)
            self.playback.handle(.playheadAdvanced(paragraph: idx, utf16Offset: utf16))
            if let utf16 { self.utteranceBaseOffset = utf16 }
        }
        engine.onFinished = { [weak self] in
            self?.completeArticle(restartBake: true)
        }
        engine.articleID = playback.articleID
        if let articleID = playback.articleID {
            engine.isEphemeralCache = localTTS.audioCache.loadMeta(for: articleID)?.kind == .ephemeral
        } else {
            engine.isEphemeralCache = false
        }
        engine.bakedURLProvider = { [weak self] idx in
            guard let self, let articleID = self.playback.articleID else { return nil }
            // Current voice's CAF, else the previous voice's until this paragraph is re-rendered.
            return self.localTTS.audioCache.playableAudioURL(
                articleID: articleID,
                paragraphIndex: idx,
                engineID: self.localTTS.cacheEngineID,
                voiceID: self.cacheVoiceID
            )
        }
        engine.unitEnsureProvider = { [weak self] index, text in
            guard let self, let articleID = self.playback.articleID else {
                throw NSError(
                    domain: "SpeechController",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No active article for ensure"]
                )
            }
            return try await self.localTTS.ensureUnit(
                cacheKey: articleID,
                paragraphIndex: index,
                text: text,
                rate: Float(self.rateMultiplier),
                voiceID: self.cacheVoiceID,
                isEphemeral: self.localTTS.audioCache.loadMeta(for: articleID)?.kind == .ephemeral
            )
        }
        engine.chunkCountProvider = { [weak self] text in
            self?.localTTS.synthQueue.chunkTexts(for: text).count ?? TextChunker.chunks(for: text).count
        }
        engine.chunkEnsureProvider = { [weak self] index, chunk, text in
            guard let self, let articleID = self.playback.articleID else {
                throw NSError(
                    domain: "SpeechController",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No active article for chunk ensure"]
                )
            }
            return try await self.localTTS.synthQueue.ensureChunk(
                cacheKey: articleID,
                paragraphIndex: index,
                chunk: chunk,
                text: text,
                paragraphs: self.playback.document.paragraphs,
                rate: Float(self.rateMultiplier),
                voiceID: self.cacheVoiceID,
                isEphemeral: self.localTTS.audioCache.loadMeta(for: articleID)?.kind == .ephemeral
            )
        }
        engine.chunkTextsProvider = { [weak self] text in
            self?.localTTS.synthQueue.chunkTexts(for: text) ?? []
        }
        engine.chunkDurationsProvider = { [weak self] index in
            guard let self, let articleID = self.playback.articleID else { return nil }
            return self.localTTS.audioCache.entry(articleID: articleID, paragraphIndex: index)?.chunkDurations
        }
        engine.chunkReadyProvider = { [weak self] index, chunk, text in
            guard let self, let articleID = self.playback.articleID else { return false }
            return self.localTTS.synthQueue.isChunkReady(
                cacheKey: articleID, paragraphIndex: index, chunk: chunk, text: text, voiceID: self.cacheVoiceID)
        }
        engine.workerBusyElsewhere = { [weak self] index in
            guard let self, let articleID = self.playback.articleID else { return false }
            let queue = self.localTTS.synthQueue
            guard let active = queue.activeBakeCacheKey else { return false }
            return active != articleID || queue.activeBakeIndex != index
        }
        engine.isRenderingParagraph = { [weak self] index in
            guard let self, let articleID = self.playback.articleID else { return false }
            let queue = self.localTTS.synthQueue
            return queue.activeBakeCacheKey == articleID && queue.activeBakeIndex == index
        }
        engine.onUnitRendered = { [weak self] index, url, duration in
            guard let self, let articleID = self.playback.articleID else { return nil }
            let paragraphs = self.playback.document.paragraphs
            return try? self.localTTS.persistRenderedUnit(
                articleID: articleID,
                paragraphIndex: index,
                sourceURL: url,
                duration: duration,
                rate: Float(self.rateMultiplier),
                voiceID: self.cacheVoiceID,
                text: paragraphs.indices.contains(index) ? paragraphs[index] : nil
            )
        }
    }

    private func restartUtteranceIfNeeded() {
        guard playback.isPrepared else { return }
        guard playback.phase == .playing || playback.phase == .paused else { return }
        speak(fromUTF16Offset: playback.utf16Offset, startPaused: playback.phase == .paused)
    }

    private func speak(fromUTF16Offset offset: Int, startPaused: Bool) {
        if !startPaused { audioSession.activate() }
        speakGeneration += 1
        let generation = speakGeneration
        suppressCancelSideEffects = true
        stopEngines()

        let ns = document.joinedText as NSString
        let clamped = max(0, min(offset, ns.length))
        playback.handle(.playheadAdvanced(
            paragraph: document.isEmpty ? 0 : document.index(containingUTF16Offset: clamped),
            utf16Offset: clamped
        ))
        utteranceBaseOffset = clamped
        let remaining = ns.substring(from: clamped)
        guard !remaining.isEmpty else {
            suppressCancelSideEffects = false
            completeArticle(restartBake: false)
            return
        }

        if usesLocalPlayback {
            let paragraphIndex = document.isEmpty ? 0 : document.index(containingUTF16Offset: clamped)
            // Units are rendered at 1×; the player time-stretches to the listen speed (Nav I).
            let avRate = Float(AVSpeechUtteranceDefaultSpeechRate)
            localTTS.localEngineInstance.setPlaybackRate(Float(rateMultiplier))
            // Scrubbed to a sentence mid-paragraph: start at its synth chunk, offset into the audio.
            let within = clamped - document.startUTF16Offset(forParagraph: paragraphIndex)
            let startPoint = within > 0 ? chunkLocation(paragraph: paragraphIndex, offset: within) : (chunk: 0, fraction: 0)
            if startPaused {
                playback.handle(.becamePaused)
                stopBufferingPoll()
            } else {
                playback.handle(.becameAudible)
                startBufferingPoll()
            }
            ListenTimingLog.log("play", [
                "key": ListenTimingLog.shortKey(playback.articleID), "p": paragraphIndex,
                "paused": startPaused,
                "baked": playback.articleID.flatMap { id in
                    localTTS.audioCache.audioURL(articleID: id, paragraphIndex: paragraphIndex,
                                                 engineID: self.localTTS.cacheEngineID,
                                                 voiceID: cacheVoiceID)
                } != nil,
                "worker_busy": localTTS.synthQueue.activeBakeCacheKey != nil,
                "worker_key": ListenTimingLog.shortKey(localTTS.synthQueue.activeBakeCacheKey),
                "worker_p": localTTS.synthQueue.activeBakeIndex ?? -1,
            ])
            if let articleID = playback.articleID {
                // Reshuffle global queue: this article #1, cursor at playhead.
                let meta = localTTS.audioCache.loadMeta(for: articleID)
                localTTS.prioritizeListen(
                    cacheKey: articleID,
                    playhead: paragraphIndex,
                    paragraphs: document.paragraphs,
                    rate: Float(rateMultiplier),
                    voiceID: cacheVoiceID,
                    isEphemeral: meta?.kind == .ephemeral
                )
            }
            wireLocalEngine()
            Task { @MainActor in
                guard generation == self.speakGeneration else { return }
                do {
                    try await self.localTTS.localEngineInstance.speak(
                        paragraphs: self.document.paragraphs,
                        startingAt: paragraphIndex,
                        chunk: startPoint.chunk,
                        fractionInChunk: startPoint.fraction,
                        rate: avRate,
                        voiceID: self.selectedVoiceIdentifier
                    )
                    if startPaused {
                        self.localTTS.localEngineInstance.pause()
                        self.playback.handle(.becamePaused)
                    }
                } catch {
                    self.localTTS.noteSpeakFailed(error)
                    self.speakApple(remaining: remaining, generation: generation, startPaused: startPaused)
                    return
                }
                self.suppressCancelSideEffects = false
            }
            return
        }

        speakApple(remaining: remaining, generation: generation, startPaused: startPaused)
    }

    // MARK: - Sub-paragraph position (local engine, Nav I)

    @ObservationIgnored private var chunkStartsCache: [String: [Int]] = [:]

    /// Where each synth chunk of paragraph `paragraph` starts (paragraph UTF-16 offsets).
    private func chunkStarts(paragraph: Int) -> [Int] {
        let paragraphs = document.paragraphs
        guard paragraphs.indices.contains(paragraph) else { return [0] }
        let text = paragraphs[paragraph]
        if let cached = chunkStartsCache[text] { return cached }
        let starts = ChunkOffsets.starts(paragraph: text, chunks: localTTS.synthQueue.chunkTexts(for: text))
        if chunkStartsCache.count > 64 { chunkStartsCache.removeAll() }
        chunkStartsCache[text] = starts
        return starts
    }

    /// Synth chunk + fraction for paragraph offset `offset`.
    private func chunkLocation(paragraph: Int, offset: Int) -> (chunk: Int, fraction: Double) {
        let length = document.paragraphs.indices.contains(paragraph) ? document.paragraphs[paragraph].utf16.count : 0
        return ChunkOffsets.locate(offset: offset, starts: chunkStarts(paragraph: paragraph), length: length)
    }

    /// Local engine: estimate the spoken spot inside the playing paragraph from the player's time
    /// (chunk boundaries + time into the chunk, proportional by characters) and move the session
    /// offset there, so the scrubber thumb moves smoothly and scrub-back starts from it.
    private func updateLocalPlaybackOffset() {
        guard usesLocalPlayback, playback.phase == .playing,
              let pos = localTTS.localEngineInstance.currentPlaybackPosition else { return }
        let p = pos.item.paragraphIndex
        guard p == playback.playhead, document.paragraphs.indices.contains(p) else { return }
        let length = document.paragraphs[p].utf16.count
        let starts = chunkStarts(paragraph: p)
        let within: Int
        let chunk = pos.item.chunkIndex ?? 0
        if chunk >= 10_000 {
            // Apple fallback: the remainder from chunk (chunk - 10 000) as one file.
            let from = starts[min(chunk - 10_000, starts.count - 1)]
            let f = pos.duration > 0 ? min(1, pos.time / pos.duration) : 0
            within = from + Int(Double(length - from) * f)
        } else if pos.item.chunkIndex == nil || pos.item.isWholeParagraph {
            let durations = localTTS.localEngineInstance.chunkDurationsProvider?(p)
            let loc = ChunkOffsets.locate(time: pos.time, fileDuration: pos.duration,
                                          durations: durations, chunkCount: starts.count)
            within = loc.chunk < 0
                ? Int(Double(length) * loc.fraction)
                : ChunkOffsets.offset(chunk: loc.chunk, fraction: loc.fraction, starts: starts, length: length)
        } else {
            let f = pos.duration > 0 ? min(1, pos.time / pos.duration) : 0
            within = ChunkOffsets.offset(chunk: chunk, fraction: f, starts: starts, length: length)
        }
        let utf16 = document.startUTF16Offset(forParagraph: p) + max(0, min(within, max(0, length - 1)))
        guard abs(utf16 - playback.utf16Offset) >= 4 else { return }
        playback.handle(.playheadAdvanced(paragraph: p, utf16Offset: utf16))
    }

    private func speakApple(remaining: String, generation: Int, startPaused: Bool) {
        let utterance = AVSpeechUtterance(string: remaining)
        utterance.rate = Float(AVSpeechUtteranceDefaultSpeechRate) * Float(rateMultiplier)
        if let voice = effectiveAppleVoice {
            utterance.voice = voice
        }

        if startPaused {
            // Paused seek / skip: hold nothing. `speak` + an immediate `pauseSpeaking` doesn't
            // stick (the utterance hasn't started yet, so it starts speaking anyway). Resume finds
            // nothing held and speaks from the playhead (`resumeEngines`).
            playback.handle(.becamePaused)
            DispatchQueue.main.async {
                guard generation == self.speakGeneration else { return }
                self.suppressCancelSideEffects = false
            }
            return
        } else {
            playback.handle(.becameAudible)
            synthesizer.speak(utterance)
        }
        DispatchQueue.main.async {
            guard generation == self.speakGeneration else { return }
            self.suppressCancelSideEffects = false
        }
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
        let rate = Float(rateMultiplier)
        let voiceID = cacheVoiceID
        speakGeneration += 1
        stopBufferingPoll()
        stopEngines()
        playback.clear()
        utteranceBaseOffset = 0
        // Let other apps' audio resume (Browse ✕ / end of article).
        audioSession.deactivate()
        if restartBake, let articleID, !paragraphs.isEmpty {
            // Return-to-top gap fill so any paragraphs above the listen playhead still bake.
            localTTS.resumeGapFillBake(
                articleID: articleID,
                paragraphs: paragraphs,
                rate: rate,
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
        let detected = detectedLanguage ?? (articleID == playback.articleID ? sessionDetectedLanguage : nil)
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

    // MARK: - Listen debug

    func listenDebugSnapshot() -> ListenDebugSnapshot {
        let eng = localTTS.localEngineInstance
        let usingLocal = usesLocalPlayback
        let articleID = playback.articleID
        let paragraphs = playback.document.paragraphs
        let queue = localTTS.synthQueue
        let bakePlan: String
        let pending: Int
        if let articleID {
            bakePlan = queue.planDescription(for: articleID)
                ?? (queue.primaryCacheKey == articleID ? "primary" : "queued/idle")
            pending = localTTS.bakeTasksCount(for: articleID)
        } else if let primary = queue.primaryCacheKey {
            bakePlan = queue.planDescription(for: primary) ?? "primary"
            pending = localTTS.bakeTasksCount(for: primary)
        } else {
            bakePlan = "—"
            pending = 0
        }
        let identityKey = articleID ?? queue.primaryCacheKey
        let ready: Int
        let totalForCache: Int
        if let identityKey {
            let count = (articleID != nil) ? paragraphs.count : (
                // Fall back to cache status expected paragraphs when viewing queue #1 with no session.
                paragraphs.count > 0 ? paragraphs.count : pending + 0
            )
            let expected = max(count, paragraphs.count)
            switch localTTS.bakeStatus(for: identityKey, paragraphCount: max(expected, 1)) {
            case .ready(paragraphCount: let n):
                ready = n
                totalForCache = n
            case .partial(ready: let r, total: let t):
                ready = r
                totalForCache = t
            case .baking, .missing:
                ready = 0
                totalForCache = max(paragraphs.count, 0)
            }
        } else {
            ready = 0
            totalForCache = paragraphs.count
        }

        let isEph: Bool = {
            guard let key = identityKey else { return false }
            if let flagged = queue.isEphemeral(cacheKey: key) { return flagged }
            return localTTS.audioCache.loadMeta(for: key)?.kind == .ephemeral
        }()
        let articleIdentity: String = {
            guard let key = identityKey else { return "—" }
            let kind = isEph ? "eph" : "svd"
            return "\(kind):\(key.uuidString.prefix(8))"
        }()
        let queuePrimary: String = {
            guard let key = queue.primaryCacheKey else { return "—" }
            let kind = (queue.isEphemeral(cacheKey: key) == true
                        || localTTS.audioCache.loadMeta(for: key)?.kind == .ephemeral) ? "eph" : "svd"
            return "\(kind):\(key.uuidString.prefix(8))"
        }()
        let activeBake: String = {
            guard let key = queue.activeBakeCacheKey, let idx = queue.activeBakeIndex else { return "—" }
            return "\(key.uuidString.prefix(8)) p\(idx)"
        }()
        let nextMissing: String = {
            if let idx = queue.nextMissingIndex() { return "p\(idx)" }
            return "—"
        }()
        let phaseLabel: String = {
            if isBufferingNext { return "buffering" }
            switch playback.phase {
            case .playing: return "playing"
            case .paused: return "paused"
            case .prepared: return "prepared"
            case .finished: return "finished"
            case .idle: return "idle"
            }
        }()
        let warmingLocal = localTTS.pendingEngineID?.isLocal == true && !localTTS.localHostReady
        let snap = engineSnapshot()
        return ListenDebugSnapshot(
            phase: String(describing: playback.phase),
            phaseLabel: phaseLabel,
            engine: usingLocal ? eng.engineShortName : "Apple",
            isAudible: snap.isAudible,
            isSpeaking: usingLocal ? eng.isSpeaking : synthesizer.isSpeaking,
            isPaused: usingLocal ? eng.isPaused : synthesizer.isPaused,
            playhead: playback.playhead,
            paragraphCount: paragraphs.count,
            bufferedCount: usingLocal ? eng.debugBufferedCount : 0,
            awaitingMore: usingLocal ? eng.debugAwaitingMore : false,
            producerActive: usingLocal ? eng.debugProducerActive : false,
            epoch: usingLocal ? eng.debugEpoch : 0,
            currentCAF: usingLocal ? eng.debugCurrentCAF : "—",
            secondsSinceEnqueue: usingLocal ? eng.debugSecondsSinceEnqueue : nil,
            lastHandoffGapMs: usingLocal ? eng.debugLastHandoffGapMs : 0,
            lastHandoffWasPrimed: usingLocal ? eng.debugLastHandoffWasPrimed : false,
            starveEventCount: usingLocal ? eng.debugStarveEventCount : 0,
            bakePlan: bakePlan,
            bakePendingJobs: pending,
            bakeReadyCount: ready,
            bakeParagraphCount: totalForCache > 0 ? totalForCache : paragraphs.count,
            articleIdentity: articleIdentity,
            queuePrimary: queuePrimary,
            demotedCount: queue.demotedCount,
            activeBakeUnit: activeBake,
            nextMissingUnit: nextMissing,
            workerBusy: queue.isWorkerRunning,
            warmingLocal: warmingLocal,
            lastBakeEvent: queue.lastBakeEvent,
            language: languageDebugLabel,
            renderMode: renderModeLabel,
            readyAhead: readyAheadCount(),
            background: queue.runState.phase == .background
                ? "now: " + eng.backgroundStats.label
                : lastBackgroundSummary,
            audioSession: "\(audioSession.isActive ? "active" : "inactive") · activations \(audioSession.activationCount)"
        )
    }

    /// Debug overlay line: language code + source → engine.
    var languageDebugLabel: String {
        let r = languageResolution
        let source = r.source == .detected ? "auto" : (r.source == .manual ? "manual" : "auto: undetected")
        let engine = r.unsupportedEngineID != nil ? "Apple (\(languageEngineDescriptor?.languageLimitNote ?? "unsupported"))"
            : localTTS.engines.shortName(r.engineID)
        return "\(r.languageCode) (\(source)) → \(engine)"
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.playback.phase != .paused {
                self.playback.handle(.becameAudible)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playback.handle(.becamePaused)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playback.handle(.becameAudible)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            let utf16 = self.utteranceBaseOffset + characterRange.location
            let paragraph = self.document.isEmpty
                ? 0
                : self.document.index(containingUTF16Offset: utf16)
            self.playback.handle(.playheadAdvanced(paragraph: paragraph, utf16Offset: utf16))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.suppressCancelSideEffects else { return }
            guard !self.synthesizer.isSpeaking, !self.synthesizer.isPaused else { return }
            let length = (self.document.joinedText as NSString).length
            guard length == 0 || self.playback.utf16Offset >= max(0, length - 8) else { return }
            self.completeArticle(restartBake: false)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
}
