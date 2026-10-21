import Foundation
import SwiftData

/// C138: one voice per article, and per book. An article's audio is all in one voice: the voice
/// it was first rendered or prepared in. A book or series (a folder that plays in order) keeps one
/// voice for every chapter: its first chapter's, which new chapters use too. The voice in Settings
/// only picks the voice of articles and books with no audio yet. A voice is a cache voice key
/// ("kokoro.af_heart"), the one the audio cache files audio under.
extension LibraryStore {
    /// Where an article's voice lives: its book or series, else itself.
    enum VoiceOwner {
        case article(Article)
        case folder(Folder)
    }

    static func voiceOwner(of article: Article) -> VoiceOwner {
        if let folder = article.folder, folder.kind.isBookOrSeries { return .folder(folder) }
        return .article(article)
    }

    /// The voice `article` speaks in; nil while it (or its book) has no audio yet.
    static func voice(of article: Article) -> String? {
        switch voiceOwner(of: article) {
        case .article(let a): a.voiceID
        case .folder(let f): f.voiceID
        }
    }

    /// The voice of the article with `key`; nil: none yet (or no such article).
    func voice(ofKey key: UUID) -> String? {
        article(key: key).flatMap(Self.voice(of:))
    }

    /// The first audio of `key` is about to render in `voice`: the article (or its book) takes it,
    /// unless it already has one. Returns the voice it speaks in after.
    @discardableResult
    func lockVoice(ofKey key: UUID, to voice: String) -> String {
        guard let article = article(key: key) else { return voice }
        if let held = Self.voice(of: article) { return held }
        try? edit("voice") {
            switch Self.voiceOwner(of: article) {
            case .article(let a): a.voiceID = voice
            case .folder(let f): f.voiceID = voice
            }
        }
        return voice
    }

    /// *Voice* in an article's menu: the article (or its book) speaks in `voice` from now on.
    func setVoice(_ voice: String, of article: Article) {
        try? edit("set voice") {
            switch Self.voiceOwner(of: article) {
            case .article(let a): a.voiceID = voice
            case .folder(let f): f.voiceID = voice
            }
        }
    }

    /// *Voice* in a book's menu.
    func setVoice(_ voice: String, of folder: Folder) {
        try? edit("set voice") { folder.voiceID = voice }
    }

    /// The pages whose audio a voice change on `owner` remakes: the article, or every chapter.
    func articlesSpeaking(in owner: VoiceOwner) -> [Article] {
        switch owner {
        case .article(let a): [a]
        case .folder(let f): articles(in: f)
        }
    }

    /// Migration (C138), once: every article with audio and no voice takes the voice most of its
    /// audio is in (`voiceOf`); a book or series, the voice most of its chapters' audio is in.
    /// Articles with no audio keep none. Returns how many articles and books got a voice.
    func adoptVoicesFromAudio(voiceOf: (UUID) -> String?) -> (articles: Int, folders: Int) {
        let all = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        var articleCount = 0
        var books: [ObjectIdentifier: (Folder, [String: Int])] = [:]
        try? edit("adopt voices") {
            for article in all {
                guard let voice = voiceOf(article.listenKey) else { continue }
                switch Self.voiceOwner(of: article) {
                case .article(let a):
                    guard a.voiceID == nil else { continue }
                    a.voiceID = voice
                    articleCount += 1
                case .folder(let f):
                    guard f.voiceID == nil else { continue }
                    var entry = books[ObjectIdentifier(f)] ?? (f, [:])
                    entry.1[voice, default: 0] += 1
                    books[ObjectIdentifier(f)] = entry
                }
            }
            for (folder, counts) in books.values {
                let most = counts.values.max() ?? 0
                folder.voiceID = counts.filter { $0.value == most }.keys.sorted().first
            }
        }
        return (articleCount, books.count)
    }

    /// C138a migration: voices stored before engines were part of them (a cache voice key,
    /// "kokoro.af_heart") become selections ("local.kokoro/af_heart"); one no engine wrote is cleared.
    @discardableResult
    func convertVoices(_ convert: (String) -> String?) -> Int {
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        var count = 0
        try? edit("convert voices") {
            for article in articles {
                guard let old = article.voiceID, !old.contains("/") else { continue }
                article.voiceID = convert(old)
                count += 1
            }
            for folder in folders {
                guard let old = folder.voiceID, !old.contains("/") else { continue }
                folder.voiceID = convert(old)
                count += 1
            }
        }
        return count
    }
}
