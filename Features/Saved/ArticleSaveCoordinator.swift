import Foundation

/// Saving, unsaving and deleting articles, with their listen audio, in one place. Pages go
/// through `LibraryStore` (one page per canonical URL); the audio cache follows once the library
/// change is stored: saved audio is kept and baked ahead, unsaved audio goes back to the
/// ephemeral TTL, deleted audio is removed. Used by the browser's ⋯ → Save to Library…, the
/// Reader's and Now Playing's 🔖, ⋯ → Save and *Save to Folder…*.
@MainActor
struct ArticleSaveCoordinator {
    let library: LibraryStore
    let speech: SpeechController

    /// Saves `article`, filed by `placement`, and returns the saved page's key. That differs from
    /// `article.id` only when an older page with another key already held this address; its audio
    /// and any live session are then rekeyed to it. Saving never interrupts playback of the
    /// article's text. A session on the article's key still playing older text (bound before the
    /// page was refreshed) gives the page no playhead, and stops if the save moves it to the older
    /// key: no page holds what it plays. Throws `LibraryStoreError.saveFailed` when the save can't
    /// be stored: nothing is saved, and the audio, the live session and the bake queue are left as
    /// they were.
    @discardableResult
    func save(_ article: ReaderArticle, placement: SavePlacement = .keep) throws -> UUID {
        let tts = speech.localTTS
        let live = speech.activeSessionID == article.id
        let playsArticle = live
            && speech.activeTextFingerprint == ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs)
        let page = try library.save(article, placement: placement, playhead: playsArticle ? speech.currentParagraphIndex : nil)
        let key = page.listenKey
        if key != article.id {
            tts.migrateListenCache(from: article.id, to: key)
            speech.rekeyActiveSession(from: article.id, to: key, text: library.textFingerprint(of: page))
        } else {
            // Align cached audio with this text (adopts audio kept under older keys); skipped
            // while it plays. `LibraryStore.save` already turned the cache from ephemeral to saved.
            tts.prepareListenIdentity(
                key: key,
                paragraphs: article.document.paragraphs,
                trustedParagraphs: article.trustedParagraphs,
                legacyKeys: article.legacyCacheKeys,
                isLivePlayback: live
            )
        }
        tts.startBakeIfNeeded(articleID: key, paragraphs: article.document.paragraphs, voiceID: speech.cacheVoiceID)
        return key
    }

    /// Removes the article from the Library (a favorite stays a favorite, as a link). Its audio and
    /// position stay, back on the ephemeral TTL, so a reader showing it keeps playing. Throws
    /// `LibraryStoreError.saveFailed` when that can't be saved: it is still saved.
    func unsave(key: UUID, canonicalURL: String?) throws {
        guard let page = library.page(key: key, canonicalURL: canonicalURL) else { return }
        try library.unsave(page)
    }
}
