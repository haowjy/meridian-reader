import Foundation
@testable import MeridianReader

/// One test's speech stack, sharing nothing with the app or another test: every file it keeps is
/// under `root` (the audio cache, the crash guard, the saved bake jobs and the crash-resume file)
/// and its settings are in a defaults suite of its own. With `LibraryTestEnvironment`, the only
/// way tests build a coordinator.
///
/// `tts`, the on-device coordinator, and `speech`, a `SpeechController` over it with a scripted
/// Apple engine (`apple`) and no system audio session or lock screen, are built at first use, as
/// a launch builds them, so a test can write stored settings or crash markers first.
/// `relaunch()` starts again over the same files and settings. `tearDown` stops playback and
/// removes the files and the suite it made.
@MainActor
final class TestSpeech {
    let root: URL
    let defaults: UserDefaults
    let engines: EngineRegistry
    let apple = FakeListenEngine()
    let audioSession = ListenAudioSession(managesSystemSession: false)
    let nowPlaying = NowPlayingController(commandCenter: nil, infoCenter: nil)
    private let suite: String?
    private let ownsRoot: Bool
    private var launchedTTS: LocalTTSCoordinator?
    private var launchedSpeech: SpeechController?

    /// `providers`: engines beside Apple's. `selected`: the engine stored as selected. `root` and
    /// `defaults`: a test's own (removed by its own cleanup), else new ones.
    init(providers: [SpeechEngineProvider] = [], selected: SpeechEngineID? = nil,
         root: URL? = nil, defaults: UserDefaults? = nil) {
        self.root = root ?? FileManager.default.temporaryDirectory.appending(path: "TestSpeech-\(UUID().uuidString)")
        ownsRoot = root == nil
        if let defaults {
            self.defaults = defaults
            suite = nil
        } else {
            let suite = "TestSpeech-\(UUID().uuidString)"
            self.defaults = UserDefaults(suiteName: suite)!
            self.suite = suite
        }
        engines = EngineRegistry(providers: [AppleSpeechProvider()] + providers, gate: { _ in true })
        if let selected { self.defaults.set(selected.rawValue, forKey: LocalTTSCoordinator.engineIDKey) }
    }

    var cacheRoot: URL { root.appending(path: "TTSCache") }
    var guardDirectory: URL { root.appending(path: "guard") }
    /// The crash-resume file the coordinator reads at launch and the controller writes.
    var resumePoints: ListenResumePointStore { ListenResumePointStore(url: root.appending(path: "listen_resume.json")) }

    var tts: LocalTTSCoordinator {
        if let launchedTTS { return launchedTTS }
        let tts = LocalTTSCoordinator(engines: engines, defaults: defaults,
                                      audioCache: ArticleAudioCache(root: cacheRoot),
                                      crashGuard: EngineCrashGuard(directory: guardDirectory),
                                      pendingBakes: PendingBakeJobStore(storeURL: root.appending(path: "PendingBakeJobs.json"),
                                                                        defaults: defaults),
                                      resumePoints: resumePoints)
        launchedTTS = tts
        return tts
    }

    var speech: SpeechController {
        if let launchedSpeech { return launchedSpeech }
        let speech = SpeechController(localTTS: tts, audioSession: audioSession, nowPlaying: nowPlaying, appleEngine: apple)
        launchedSpeech = speech
        return speech
    }

    /// A new launch over the same files and settings: the next `tts` and `speech` are new.
    func relaunch() {
        launchedSpeech?.stop()
        launchedSpeech = nil
        launchedTTS = nil
    }

    func tearDown() {
        launchedSpeech?.stop()
        if let suite { defaults.removePersistentDomain(forName: suite) }
        if ownsRoot { try? FileManager.default.removeItem(at: root) }
    }

    /// A three-paragraph web article at `url`.
    static func article(_ url: String, id: UUID? = nil, title: String = "Article") -> ReaderArticle {
        let url = URL(string: url)!
        let paragraphs = ["The first paragraph of \(title) has a few sentences. It goes on a while.",
                          "The second paragraph is here.", "The third one ends it."]
        let extracted = ExtractedArticle(title: title, siteName: nil,
                                         cleanedHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                                         plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
        let key = id ?? ArticleIdentity.articleKey(canonicalURL: ArticleIdentity.canonicalURLString(from: url))
        return ReaderArticle(id: key, url: url, extracted: extracted)
    }
}
