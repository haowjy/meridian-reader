import Foundation
@testable import Reader

/// A `SpeechController` over a scripted Apple engine, with no system audio session, lock screen,
/// resume file or shared defaults. `tearDown` stops it and removes its temporary files.
@MainActor
final class TestSpeech {
    let speech: SpeechController
    let apple = FakeListenEngine()
    private let suite = "TestSpeech-\(UUID().uuidString)"
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("TestSpeech-\(UUID().uuidString)")

    init() {
        let defaults = UserDefaults(suiteName: suite)!
        let registry = EngineRegistry(providers: [AppleSpeechProvider()], gate: { _ in true })
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                              audioCache: ArticleAudioCache(root: root.appendingPathComponent("cache")),
                                              crashGuard: EngineCrashGuard(directory: root.appendingPathComponent("guard")))
        speech = SpeechController(engines: registry, localTTS: coordinator,
                                  audioSession: ListenAudioSession(managesSystemSession: false),
                                  nowPlaying: NowPlayingController(commandCenter: nil, infoCenter: nil),
                                  appleEngine: apple, resumePoints: nil)
    }

    func tearDown() {
        speech.stop()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
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
