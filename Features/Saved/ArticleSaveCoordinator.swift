import SwiftData
import Foundation

/// Saving, unsaving and deleting articles, with their listen audio, in one place. Rows go
/// through `ArticleLibrary` (one row per canonical URL); the audio cache follows: saved audio is
/// kept and baked ahead, unsaved audio goes back to the ephemeral TTL, deleted audio is removed.
/// Used by the browser's ⋯ → Save, the reader's 🔖, and the library's swipe-to-delete.
@MainActor
struct ArticleSaveCoordinator {
    let context: ModelContext
    let speech: SpeechController

    /// Saves `article` and returns the saved row's id. That differs from `article.id` only when an
    /// older row with another id already held this page; its audio and any live session are then
    /// rekeyed to it. Saving never interrupts playback.
    @discardableResult
    func save(_ article: ReaderArticle) -> UUID {
        let tts = speech.localTTS
        let live = speech.activeSessionID == article.id
        let row = ArticleLibrary.save(article, playhead: live ? speech.currentParagraphIndex : nil, in: context)
        if row.id != article.id {
            tts.migrateListenCache(from: article.id, to: row.id)
            speech.rekeyActiveSession(from: article.id, to: row.id)
        } else {
            // Align cached audio with this text (adopts audio kept under older keys); skipped
            // while it plays. Then the cache just changes kind: ephemeral → saved.
            tts.prepareListenIdentity(
                key: row.id,
                paragraphs: article.document.paragraphs,
                trustedParagraphs: article.trustedParagraphs,
                legacyKeys: article.legacyCacheKeys,
                isLivePlayback: live
            )
            tts.migrateListenCache(from: row.id, to: row.id)
        }
        tts.startBakeIfNeeded(articleID: row.id, paragraphs: article.document.paragraphs, voiceID: speech.cacheVoiceID)
        return row.id
    }

    /// Removes the article from Saved. Its audio and playhead stay, back on the ephemeral TTL, so
    /// a reader showing it keeps playing.
    func unsave(id: UUID, canonicalURL: String) {
        ArticleLibrary.unsave(id: id, canonicalURL: canonicalURL, in: context)
        speech.localTTS.markListenCacheEphemeral(id, canonicalURL: canonicalURL)
    }

    /// Library swipe-to-delete: removes the article and its audio.
    func delete(_ row: SavedArticle) {
        let id = row.id
        let canonical = row.canonicalURL.isEmpty ? ArticleIdentity.canonicalURLString(from: row.urlString) : row.canonicalURL
        speech.localTTS.handleArticleDeleted(id)
        ArticleLibrary.unsave(id: id, canonicalURL: canonical, in: context)
    }
}
