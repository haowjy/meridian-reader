import Foundation

/// Saving an article, with its listen audio, in one place. Pages go through `LibraryStore` (one
/// page per canonical URL); the audio cache follows once the library change is stored: saved
/// audio is kept and baked ahead. (*Remove from Library* is `LibraryStore.remove`, which puts the
/// audio back on the ephemeral TTL.) Used through `ArticleActions` by every page menu's *Save to
/// Library* and *Save to Folder…* (the browser's page extracted first) and by 🔖.
@MainActor
struct ArticleSaveCoordinator {
    let library: LibraryStore
    let speech: SpeechController

    /// Saves `readerArticle`, filed by `placement`, and returns the saved page's key. That differs from
    /// `readerArticle.id` only when an older page with another key already held this address; its audio
    /// and any live session are then rekeyed to it. Saving never interrupts playback of the
    /// article's text. A session on the article's key still playing older text (bound before the
    /// page was refreshed) gives the page no playhead, and stops if the save moves it to the older
    /// key: no page holds what it plays. Throws `LibraryStoreError.saveFailed` when the save can't
    /// be stored: nothing is saved, and the audio, the live session and the bake queue are left as
    /// they were.
    @discardableResult
    func save(_ readerArticle: ReaderArticle, placement: SavePlacement = .keep) throws -> UUID {
        let tts = speech.localTTS
        let live = speech.activeSessionID == readerArticle.id
        let playsArticle = live
            && speech.activeTextFingerprint == ArticleIdentity.contentFingerprint(paragraphs: readerArticle.document.paragraphs)
        let article = try library.save(readerArticle, placement: placement, playhead: playsArticle ? speech.currentParagraphIndex : nil)
        let key = article.listenKey
        if key != readerArticle.id {
            tts.migrateListenCache(from: readerArticle.id, to: key)
            speech.rekeyActiveSession(from: readerArticle.id, to: key, text: library.textFingerprint(of: article))
        } else {
            // Align cached audio with this text (adopts audio kept under older keys); skipped
            // while it plays. `LibraryStore.save` already turned the cache from ephemeral to saved.
            tts.prepareListenIdentity(
                key: key,
                paragraphs: readerArticle.document.paragraphs,
                trustedParagraphs: readerArticle.trustedParagraphs,
                legacyKeys: readerArticle.legacyCacheKeys,
                isLivePlayback: live
            )
        }
        // C134: saving keeps the text; audio renders only while listening, or when prepared.
        return key
    }
}
