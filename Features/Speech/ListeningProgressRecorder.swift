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
/// - A chapter of a book or series that starts becomes the book's place; the last playable
///   chapter's end finishes the book (`LibraryStore+Chapters`). A chapter that playback carries on
///   past is marked finished by the controller (`NextChapterProviding.pageFinished`), since the
///   session moves straight to the next one.
///
/// It holds the page it writes to, so a position isn't a fetch. What it writes is stored by the
/// next save that works: a failed edit's rollback doesn't drop it (`PendingListening`).
@MainActor
final class ListeningProgressRecorder {
    private let speech: SpeechController
    private let library: LibraryStore
    /// Scene-leave observers. The recorder lives as long as the app; each holds it weakly.
    private var observers: [NSObjectProtocol] = []
    /// The page being written.
    private var current: Page?
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
    private func page(_ key: UUID) -> Page? {
        if let current, current.listenKey == key, !current.isDeleted, current.modelContext != nil { return current }
        current = library.page(key: key)
        return current
    }

    private func record(_ progress: ListenProgress) {
        let key = progress.pageKey
        if progress.phase == .playing {
            if listening != key {
                listening = key
                recordStart(of: key)
            }
        } else {
            listening = nil
        }
        guard let page = page(key) else { return }
        library.recordPosition(page, paragraph: progress.paragraph, utf16Offset: progress.utf16Offset)
        if progress.phase == .finished { library.recordFinished(page) }
    }

    /// Listening started (or resumed) on the page: it moves to the front of Continue listening and
    /// stops counting as finished. Its first start from an article keeps or refreshes its text.
    private func recordStart(of key: UUID) {
        if let article = startedFrom, article.id == key {
            startedFrom = nil
            current = library.recordPlayback(article)
        } else if let page = page(key) {
            library.recordPlaybackStarted(page)
        }
    }

    /// The live spot, including the offset inside the paragraph (which `onProgress` doesn't report
    /// tick by tick), then whatever else is pending.
    private func sceneLeft() {
        if let id = speech.activeSessionID, let page = page(id) {
            library.recordPosition(page, paragraph: speech.currentParagraphIndex, utf16Offset: speech.spokenUTF16Offset)
        }
        library.commit("scene left")
    }
}
