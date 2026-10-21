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

    /// Its own voice, nil before it has audio.
    var ownVoice: String? {
        switch owner {
        case .article(let a): a.voiceID
        case .folder(let f): f.voiceID
        }
    }

    /// The voice it plays in: its own, else the one in Settings its first audio takes.
    var voice: String? {
        ownVoice ?? tts.activeCacheVoice ?? tts.cacheVoice(of: tts.engines.defaultLocalEngineID)
    }

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

    /// Picks `voice` (an engine voice id, "af_bella") of the engine `descriptor`: downloads its
    /// files if needed, then sets it and remakes the audio. Throws when the download fails.
    func apply(_ engineVoice: String, of descriptor: EngineDescriptor) async throws {
        guard let cacheVoice = descriptor.cacheVoiceID(engineVoice: engineVoice), cacheVoice != ownVoice else { return }
        try await tts.engines.prepareVoice(engineVoice, for: descriptor.id)
        let keys = articles.map(\.listenKey)
        // Never two voices in one listen: what plays of it stops at once.
        for key in keys { speech.stopIfPlaying(key) }
        switch owner {
        case .article(let a): library.setVoice(cacheVoice, of: a)
        case .folder(let f): library.setVoice(cacheVoice, of: f)
        }
        tts.articleVoicesChanged()
        for key in keys {
            if preparedAudio.hasRecord(for: key) {
                preparedAudio.reprepare(article: key)
            } else if tts.audioCache.bytes(for: key) > 0 {
                try? tts.clearListenAudio(for: key)
            }
        }
        ListenDebugLog.shared.append("C138 voice \(cacheVoice) for \(keys.count) article(s)")
    }
}
