import Foundation
import UIKit

/// Saves listening progress from the playback session into the library, whatever is on screen: a
/// page played from 🎧 or a row's ▶ with no Reader open keeps its spot too. Built once at the
/// composition root.
///
/// - Each start (play, resume, replay) dates the page and makes it unfinished. A page started from
///   a `ReaderArticle` (`SpeechController.listen(to:)`) is recorded from it, so a page the library
///   doesn't have is kept with its text: played without saving, for 7 days after its last play.
/// - The position is written on each new paragraph, on every phase change (pause, finish, Stop
///   Listening, a page being replaced, which stops the old one first) and when the app leaves the
///   foreground, never on the playhead's sub-paragraph ticks.
/// - Playing to the end marks the page finished.
/// - A page in a folder (a book's chapter, or a page in any folder) that starts becomes the
///   folder's place; the last playable
///   chapter's end finishes the book (`LibraryStore+Chapters`). A chapter that playback carries on
///   past is marked finished by the controller (`NextChapterProviding.articleFinished`), since the
///   session moves straight to the next one.
///
/// Progress lands only on the text that was played: each write goes to the page for the session's
/// key only while that page holds the text the session plays (`LibraryStore.holds`, against the
/// fingerprint `ListenProgress` carries). A key can name other text by then: a *Replace* brought
/// another chapter back under it, a page was refreshed on open while it played, a resumed or
/// staged session holds a document older than its page. Such a session plays on and nothing it
/// reaches is written; the page keeps its own listening.
///
/// It holds the page it writes to, so a position isn't a fetch, and the comparison costs a look at
/// the stored text, not a hash. What it writes is stored by the next save that works: a failed
/// edit's rollback doesn't drop it (`PendingListening`).
@MainActor
final class ListeningProgressRecorder {
    private let speech: SpeechController
    private let library: LibraryStore
    /// Scene-leave observers. The recorder lives as long as the app; each holds it weakly.
    private var observers: [NSObjectProtocol] = []
    /// The page being written.
    private var current: Article?
    /// The article the session about to bind was started from, until its first start is recorded.
    private var startedFrom: ReaderArticle?
    /// The page last seen playing, so a start is recorded once, not per paragraph.
    private var listening: UUID?

    init(speech: SpeechController, library: LibraryStore, notificationCenter: NotificationCenter = .default) {
        self.speech = speech
        self.library = library
        speech.onListen = { [weak self] article in self?.startedFrom = article }
        speech.onProgress = { [weak self] progress in self?.record(progress) }
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sceneLeft() }
            })
        }
    }

    /// The library's page for `key`: the held one, or fetched once when the session moves on, or
    /// when a rollback dropped the one held (a page its first play made, which the library makes
    /// again).
    private func article(_ key: UUID) -> Article? {
        if let current, current.isLive, current.listenKey == key { return current }
        current = library.article(key: key)
        return current
    }

    /// The page for `key` while it holds `text`, the text the session plays: nil when no page has
    /// the key or it holds other text.
    private func article(_ key: UUID, holding text: String?) -> Article? {
        guard let article = article(key), library.holds(article, text: text) else { return nil }
        return article
    }

    private func record(_ progress: ListenProgress) {
        let key = progress.articleKey
        if progress.phase == .playing {
            if listening != key {
                listening = key
                recordStart(of: key, text: progress.text)
            }
        } else {
            listening = nil
        }
        guard let article = article(key, holding: progress.text) else { return }
        library.recordPosition(article, paragraph: progress.paragraph, utf16Offset: progress.utf16Offset)
        if progress.phase == .finished { library.recordFinished(article) }
    }

    /// Listening started (or resumed) on the page: it is dated (most recently played) and
    /// stops counting as finished. Its first start from an article keeps or refreshes its text,
    /// when the session plays that article's text; a session bound before keeps its own document
    /// (`SpeechController.prepare`), and is recorded like any other, on a page holding it.
    private func recordStart(of key: UUID, text: String?) {
        if let article = startedFrom, article.id == key {
            startedFrom = nil
            if ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs) == text {
                current = library.recordPlayback(article)
                return
            }
        }
        if let article = article(key, holding: text) {
            library.recordPlaybackStarted(article)
        }
    }

    /// The live spot, including the offset inside the paragraph (which `onProgress` doesn't report
    /// tick by tick), then whatever else is pending.
    private func sceneLeft() {
        if let id = speech.activeSessionID, let article = article(id, holding: speech.activeTextFingerprint) {
            library.recordPosition(article, paragraph: speech.currentParagraphIndex, utf16Offset: speech.spokenUTF16Offset)
        }
        library.commit("scene left")
    }
}
