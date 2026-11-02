import Foundation

/// The article that explains the app, "How Meridian Reader Works": an ordinary saved article in
/// the Library, with its text and its audio (recorded in the built-in default voice) shipped in
/// `Resources/Welcome/`. Nothing downstream treats it specially; what is special is around it:
/// a fixed key, so the bundled audio lands in the right cache directory and a re-add reuses it;
/// its first launch (a fresh install only); and ⋯ › Help and Settings › About, which bring it
/// back when it was deleted.
///
/// It belongs to the built-in default voice (Phonon's Zoey) whatever Settings says: the audio
/// is in that voice, and *Voice* on the article changes it like any article's.
@MainActor
struct WelcomeArticle {
    /// Persisted: the cache directory of the bundled audio is named by it. Never changes.
    static let key = UUID(uuidString: "5E1C0DE0-0000-4000-8000-4D52444E5244")!
    static let installedKey = "welcome.installed"
    static let storedKeys = [installedKey]

    let library: LibraryStore
    let speech: SpeechController
    let preparedAudio: PrepareCenter
    let shell: ShellState

    private var tts: LocalTTSCoordinator { speech.localTTS }

    /// The first launch of a fresh install: the article is added at the top of the Library as the
    /// page last played, so the chrome's Listen button and the iPad dock offer it until something
    /// else plays, and Listen opens on it paused, unless the launch arrived with somewhere to go
    /// (`ShellState.hasSomewhereToGo`: a Share, an Open In, an import). An upgrade (a library
    /// already in use) and every later launch add nothing.
    func addOnFreshInstall() {
        guard !UserDefaults.standard.bool(forKey: Self.installedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.installedKey)
        guard library.isUntouched, let article = ensure() else { return }
        library.recordPlaybackStarted(article)
        if !shell.hasSomewhereToGo { bindPaused(article) }
    }

    /// ⋯ › Help and Settings › About: the article, added again first when it was deleted or
    /// removed. Listen, paused, so it is read to you, as on first launch; but while another page
    /// plays or is paused, Library Read, as a row's *Open* does: Help never takes over what
    /// you are hearing.
    func open() {
        guard let article = ensure() else { return }
        shell.sheet = nil // Settings' or History's sheet on regular width: Listen rises under system sheets
        if let now = speech.nowPlaying, now.articleKey != Self.key, now.phase == .playing || now.phase == .paused {
            shell.hideNowPlaying()
            shell.openSaved(article.listenKey, in: library)
        } else {
            bindPaused(article)
        }
    }

    #if DEBUG
    /// `-recordWelcome`: the article in the Library and its audio prepared in its voice, ready to
    /// copy out of the cache (`tools/record-welcome-audio.sh`).
    func record() {
        guard let (article, _) = addedToLibrary() else { return }
        _ = preparedAudio.prepare(article)
    }
    #endif

    // MARK: - Pieces

    private func bindPaused(_ article: Article) {
        let session = SpeechSession.article(article)
        speech.prepare(session, at: article.listenStart)
        shell.showNowPlaying()
    }

    /// The article in the Library, with its bundled audio installed and prepared when it was
    /// just added back.
    private func ensure() -> Article? {
        guard let (article, added) = addedToLibrary() else { return nil }
        if added, installAudio(of: article) { _ = preparedAudio.prepare(article) }
        return article
    }

    /// The article in the Library, its voice locked when it is added. `added` is false when it
    /// was in the Library already.
    private func addedToLibrary() -> (article: Article, added: Bool)? {
        if let article = library.article(key: Self.key) {
            if article.isInLibrary { return (article, false) }
            do { try library.saveUnsaved(article) } catch { return nil }
            return (article, true)
        }
        guard let (title, body) = Self.bundledText() else { return nil }
        do {
            let article = try library.saveText(title: title, text: body, in: nil, key: Self.key,
                                               byline: String(localized: "Meridian Reader"))
            library.lockVoice(ofKey: Self.key, to: tts.builtInDefaultSelection.stored)
            return (article, true)
        } catch {
            return nil
        }
    }

    /// `article.md`: its first line "# Title", then the paragraphs.
    private static func bundledText() -> (title: String, body: String)? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Welcome/article.md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2, lines[0].hasPrefix("# ") else { return nil }
        return (String(lines[0].dropFirst(2)), String(lines[1]))
    }

    /// Installs the bundled recording (`Welcome/audio`) as the article's audio. A recording in
    /// another voice than the article speaks in (a model revision it predates) is refused, and the
    /// article renders live. True when audio is there.
    private func installAudio(of article: Article) -> Bool {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("Welcome/audio") else { return false }
        return tts.installRecording(source, as: Self.key, paragraphs: article.listenDocument().paragraphs)
    }
}
