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

/// C138: changing the voice of one article, or of a book (every chapter). Its audio is remade in
/// the new voice, never mixed: playback of it stops (it plays again from the start of its next
/// play, all in the new voice); prepared audio renders again (the old voice's files go once the
/// new audio is whole, `ArticleAudioCache.finalizeVoiceSwitch`, and never play meanwhile); audio
/// from listening is cleared, and made again as it plays.
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

    /// What a change remakes: prepared audio (rendered again) and audio from listening (cleared).
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

    /// C138a: picks `selection` (any engine's voice): downloads its files if needed, then sets
    /// it and remakes the audio. Throws when the download fails.
    func apply(_ selection: VoiceSelection) async throws {
        guard selection != ownSelection else { return }
        if !selection.isApple {
            guard await tts.downloadVoice(selection.voice, for: selection.engine) else {
                throw CocoaError(.fileReadUnknown)
            }
        }
        let keys = articles.map(\.listenKey)
        // Never two voices in one listen: what plays of it stops at once.
        for key in keys { speech.stopIfPlaying(key) }
        switch owner {
        case .article(let a): library.setVoice(selection.stored, of: a)
        case .folder(let f): library.setVoice(selection.stored, of: f)
        }
        tts.articleVoicesChanged()
        if !selection.isApple { tts.loadEngineIfNeeded(selection.engine) }
        for key in keys {
            let prepared = preparedAudio.hasRecord(for: key)
            // An Apple voice renders nothing ahead: its old audio can't be remade, so it goes.
            if (selection.isApple || !prepared), tts.audioCache.bytes(for: key) > 0 {
                try? tts.clearListenAudio(for: key)
            }
            if prepared { preparedAudio.reprepare(article: key) }
        }
        ListenDebugLog.shared.append("C138a voice \(selection) for \(keys.count) article(s)")
    }
}
