import Foundation
import SwiftData

/// The listening position and history of saved articles: `SavedArticle`'s playhead fields and
/// `ListenHistory`. Pages that aren't saved keep no position (a played, unsaved page isn't
/// restored after a relaunch).
@MainActor
final class SavedArticleProgressStore: ListeningProgressStoring {
    private let context: ModelContext
    private let defaults: UserDefaults
    /// The row written last: positions arrive once per paragraph, so it isn't fetched each time.
    private var current: SavedArticle?

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    private func row(_ key: UUID) -> SavedArticle? {
        if let current, current.id == key, !current.isDeleted, current.modelContext != nil { return current }
        current = ArticleLibrary.savedArticle(id: key, in: context)
        return current
    }

    func storePosition(pageKey: UUID, paragraph: Int, utf16Offset: Int) {
        guard let row = row(pageKey) else { return }
        if row.playbackParagraphIndex != paragraph { row.playbackParagraphIndex = paragraph }
        if row.playbackUTF16Offset != utf16Offset { row.playbackUTF16Offset = utf16Offset }
    }

    func noteListening(pageKey: UUID) {
        guard row(pageKey) != nil else { return }
        ListenHistory.record(pageKey, defaults: defaults)
    }

    func noteFinished(pageKey: UUID) {
        guard row(pageKey) != nil else { return }
        ListenHistory.record(pageKey, finished: true, defaults: defaults)
    }

    func flush() {
        try? context.save()
    }
}

/// Now Playing's text: a saved article from its row; an unsaved page from the `ReaderArticle` it
/// was started with, kept in memory (so it isn't there after a relaunch).
@MainActor
final class SavedArticleContentResolver: NowPlayingContentResolving {
    private let context: ModelContext
    private var remembered: ReaderArticle?

    init(context: ModelContext) {
        self.context = context
    }

    func remember(_ article: ReaderArticle) {
        remembered = article
    }

    func content(for pageKey: UUID) async -> ReaderArticle? {
        if let row = ArticleLibrary.savedArticle(id: pageKey, in: context) {
            return ReaderArticle(saved: row)
        }
        return remembered?.id == pageKey ? remembered : nil
    }
}
