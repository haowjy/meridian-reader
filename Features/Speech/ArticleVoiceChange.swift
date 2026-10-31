import Foundation

/// What a voice picker is for (C138): an article (by its key) or a book or series (by its id).
enum VoiceTarget: Equatable {
    case article(UUID)
    case folder(UUID)

    var id: String {
        switch self {
        case .article(let key): "article-\(key.uuidString)"
        case .folder(let id): "folder-\(id.uuidString)"
        }
    }
}

/// C138: changing the voice of one article, or of a book (every chapter). Its audio is in the new
/// voice from now on, never mixed: playback of it stops (it plays again from the start of its next
/// play, all in the new voice); the old voice's audio is kept 7 days with other unsaved audio, and
/// audio kept from an earlier change back is its audio again (the voice record,
/// `ArticleAudioCache.settleVoice`); prepared audio renders what the new voice lacks, and audio
/// from listening is made as it plays.
@MainActor
struct ArticleVoiceChange {
    let owner: LibraryStore.VoiceOwner
    let library: LibraryStore
    let speech: SpeechController
    let preparedAudio: PrepareCenter

    private var tts: LocalTTSCoordinator { speech.localTTS }

    init?(target: VoiceTarget, library: LibraryStore, speech: SpeechController, preparedAudio: PrepareCenter) {
        switch target {
        case .article(let key):
            guard let article = library.article(key: key) else { return nil }
            owner = LibraryStore.voiceOwner(of: article)
        case .folder(let id):
            guard let folder = library.folder(id: id) else { return nil }
            owner = .folder(folder)
        }
        self.library = library
        self.speech = speech
        self.preparedAudio = preparedAudio
    }

    /// The articles that speak in this voice: the article, or every chapter.
    var articles: [Article] { library.articlesSpeaking(in: owner) }

    /// Its own selection (engine + voice), nil before it has audio.
    var ownSelection: VoiceSelection? {
        let stored: String? = switch owner {
        case .article(let a): a.voiceID
        case .folder(let f): f.voiceID
        }
        return stored.flatMap(VoiceSelection.init(stored:))
    }

    /// The selection it plays in: its own, else the Settings default its first audio takes.
    var selection: VoiceSelection { ownSelection ?? tts.defaultSelection }

    var isBook: Bool {
        if case .folder = owner { return true }
        return false
    }

    var name: String {
        switch owner {
        case .article(let a): a.lineOne
        case .folder(let f): f.name
        }
    }

    /// What a change leaves behind in the old voice: prepared audio (rendered again in the new one)
    /// and audio from listening (made again as it plays). Both are kept 7 days.
    struct Cost: Equatable {
        var prepared: Int64 = 0
        var listening: Int64 = 0
        var isEmpty: Bool { prepared == 0 && listening == 0 }
    }

    func cost() -> Cost {
        var cost = Cost()
        for article in articles {
            let key = article.listenKey
            let bytes = tts.audioCache.bytes(for: key)
            guard bytes > 0 else { continue }
            if preparedAudio.hasRecord(for: key) { cost.prepared += bytes } else { cost.listening += bytes }
        }
        return cost
    }

    enum Failure: Error {
        /// The voice's files didn't download.
        case download
        /// The library couldn't save the change: nothing changed.
        case save
    }

    /// C138a: picks `selection` (any engine's voice): downloads its files if needed, then sets
    /// it (one save with its voice records, `LibraryStore.setVoice`) and prepares again what was
    /// prepared. Throws `Failure` when the download or the save fails.
    func apply(_ selection: VoiceSelection) async throws {
        guard selection != ownSelection else { return }
        guard await tts.downloadVoice(selection.voice, for: selection.engine) else { throw Failure.download }
        let keys = articles.map(\.listenKey)
        // Never two voices in one listen: what plays of it stops at once.
        for key in keys { speech.stopIfPlaying(key) }
        do {
            try library.setVoice(selection.stored, of: owner)
        } catch {
            ListenDebugLog.shared.append("C138a voice \(selection) not saved: \(error)")
            throw Failure.save
        }
        tts.articleVoicesChanged()
        for key in keys where preparedAudio.hasRecord(for: key) { preparedAudio.reprepare(article: key) }
        ListenDebugLog.shared.append("C138a voice \(selection) for \(keys.count) article(s)")
    }
}
