import Foundation
import SwiftData

/// Launch work, run once by `ReaderApp` when the first window appears: saved-article migrations,
/// app-wide callbacks, the UI-test / diagnostics hooks from `LaunchOptions` (Debug builds), then
/// crash resume.
/// Views only render; nothing here waits on a view appearing in a particular order.
@MainActor
enum AppLaunch {
    private static var didRun = false

    static func run(context: ModelContext, speech: SpeechController, shell: ShellState) async {
        guard !didRun else { return }
        didRun = true
        let tts = speech.localTTS
        #if DEBUG
        LaunchHooks.runBeforeMigrations(.current, context: context, tts: tts)
        #endif

        // Paragraph layout v3 first (it needs the stored pre-split blocks): split giant
        // paragraphs, keeping position and usable audio. Then identity v2: backfill canonical
        // URLs and merge duplicate saves. Both are idempotent and skip finished rows.
        ArticleLibrary.migrateParagraphLayout(in: context, localTTS: tts)
        ArticleLibrary.migrate(in: context, localTTS: tts)

        speech.onArticleFinished = { id in
            ListenHistory.record(id, finished: true)
        }

        #if DEBUG
        LaunchHooks.runAfterMigrations(.current, context: context, speech: speech, shell: shell)
        #endif

        await resumeAfterCrash(context: context, speech: speech, shell: shell)
    }

    /// Kokoro crashed last session: reopen the article at the paragraph that was playing —
    /// playing again (on the ONNX route, once it's loaded) if the crash just happened, else paused
    /// there. Runs after the layout migration, so the stored paragraph uses the current numbering.
    private static func resumeAfterCrash(context: ModelContext, speech: SpeechController, shell: ShellState) async {
        let tts = speech.localTTS
        guard let target = tts.takePendingResume() else { return }
        let rows = (try? context.fetch(FetchDescriptor<SavedArticle>())) ?? []
        guard let article = rows.first(where: { target.matches($0.id) }) else {
            ListenTimingLog.log("kokoro_resume", ["ok": false, "why": "article not found", "key": String(target.articleKey.prefix(8))])
            return
        }
        let session = SpeechSession.saved(article)
        let p = min(max(0, target.paragraph), max(0, session.document.count - 1))
        article.playbackParagraphIndex = p
        shell.openSaved(article.id, in: context)
        if target.autoPlay {
            // Wait (≤20 s) for the Kokoro host so the resume doesn't start on Apple.
            var waited = 0
            while tts.synth.state.warmingEngineID != nil, waited < 100 {
                try? await Task.sleep(for: .milliseconds(200))
                waited += 1
            }
            speech.start(session, fromParagraph: p)
        } else {
            speech.prepare(session, startingParagraph: p)
        }
        ListenTimingLog.log("kokoro_resume", [
            "ok": true, "key": ListenTimingLog.shortKey(article.id), "p": p, "auto_play": target.autoPlay,
            "local": tts.usesLocalEngine,
        ])
    }
}
