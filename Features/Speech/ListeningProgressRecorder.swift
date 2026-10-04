import Foundation
import UIKit

/// Where listening progress is kept: a page's position, when it was last listened to, and
/// whether it was heard to the end. The recorder decides when; the store decides where.
@MainActor
protocol ListeningProgressStoring: AnyObject {
    func storePosition(pageKey: UUID, paragraph: Int, utf16Offset: Int)
    /// Listening started (or resumed) on the page: it moves to the front of Continue listening and
    /// stops counting as finished.
    func noteListening(pageKey: UUID)
    func noteFinished(pageKey: UUID)
    /// The app is leaving the foreground: write what is pending.
    func flush()
}

/// Saves the listening position from the playback session, whatever is on screen: a page played
/// from 🎧 or a row's ▶ with no Reader open keeps its spot too. Built once at the composition root.
///
/// It writes on each new paragraph, on every phase change (pause, finish, Stop Listening, a page
/// being replaced, which stops the old one first) and when the app leaves the foreground, never on
/// the playhead's sub-paragraph ticks.
@MainActor
final class ListeningProgressRecorder {
    private let speech: SpeechController
    private let store: ListeningProgressStoring
    /// Scene-leave observers. The recorder lives as long as the app; each holds it weakly.
    private var observers: [NSObjectProtocol] = []
    /// The page last seen playing, so "listening started" is noted once per start, not per paragraph.
    private var listening: UUID?

    init(speech: SpeechController, store: ListeningProgressStoring, notificationCenter: NotificationCenter = .default) {
        self.speech = speech
        self.store = store
        speech.onProgress = { [weak self] progress in self?.record(progress) }
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sceneLeft() }
            })
        }
    }

    private func record(_ progress: ListenProgress) {
        store.storePosition(pageKey: progress.pageKey, paragraph: progress.paragraph, utf16Offset: progress.utf16Offset)
        switch progress.phase {
        case .playing:
            if listening != progress.pageKey {
                listening = progress.pageKey
                store.noteListening(pageKey: progress.pageKey)
            }
        case .finished:
            listening = nil
            store.noteFinished(pageKey: progress.pageKey)
        case .paused, .prepared, .idle:
            listening = nil
        }
    }

    /// The live spot, including the offset inside the paragraph (which `onProgress` doesn't report
    /// tick by tick).
    private func sceneLeft() {
        if let id = speech.activeSessionID {
            store.storePosition(pageKey: id, paragraph: speech.currentParagraphIndex,
                                utf16Offset: speech.spokenUTF16Offset)
        }
        store.flush()
    }
}
