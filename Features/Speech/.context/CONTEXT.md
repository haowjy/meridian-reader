# Speech: working notes

Behavior and architecture are in `../../../docs/LISTEN_PLAYBACK.md` and
`../../../docs/TTS_ENGINES.md`. This file holds what to keep in mind while changing the code.

## Where to start reading

`SpeechController` (intents, engine binding) → `Playback/PlaybackSession.swift` (the state machine)
→ `Playback/` adapters (`AppleListenEngine`, `LocalListenEngine` → `LocalListenPlayer`) →
`LocalTTSCoordinator` (engine selection, `LocalSynthService`, launch recovery) →
`Core/TTS/GlobalSynthQueue.swift` (render queue) and `Core/TTS/ArticleAudioCache.swift`.

## Contracts that break quietly

- **What you hear.** Play buttons ask `playState(of:)` and press through `press(_:start:)`; never
  compare session ids in a view. A finished page stays bound (`.finished`); only `stop()` (Stop
  Listening) unbinds. `onProgress` fires synchronously from `publishPlayback`, so the recorder sees
  a replaced page's last spot (the `.stop` before the next `bind`). `listen(to:)` hands its article
  to `onListen` before it binds, so the recorder can keep a page the library doesn't have on its
  first start.
- **Books, series and folders.** Any page in a folder carries on through it, in the folder's
  sort (D15; books and series too, D19); `PlaybackFolder.isBookOrSeries` is the one thing that
  tells a book or series apart (the bar's source, no catch-up bake). The controller decides at a page's `finished` before the session sees it
  (`SpeechController+Advance`): the next chapter is bound with `advance`, in place. Nothing
  between chapters may deactivate the audio session, clear the session or clear the lock screen
  (`finishSession` is the end only); locked listening depends on it, and the
  `chapter_boundary` timing line checks it on a device. The library is reached only through
  `NextChapterProviding`. A staged next chapter must never render at listener priority, and sits
  right behind the playing chapter's job (at the front once that is done), never behind a job that
  parks in the background, and its opening goes before the playing chapter's paragraphs above
  the playhead (`GlobalSynthQueueStagingTests`); downloads come after all of it
  (`DownloadCenterTests`). While the next chapter is fetched, no progress is reported for the
  page still bound: it has ended, and a resume there isn't a replay.
- **Listening progress outlives rollbacks through the store only.** The recorder writes through
  `LibraryStore`'s `recordPlayback` / `recordPlaybackStarted` / `recordPosition` /
  `recordFinished`, which keep what isn't stored (`PendingListening`) and write it again after a
  failed edit's rollback. Progress set straight on a `Page` is lost to the next rollback. A
  write made while an edit is staged (the position stopping records when the playing page is
  deleted) waits for that edit's save.
- **Progress follows the text.** `PlaybackSessionState.textFingerprint` is set with the document
  (`bind`, `advance`) and travels in every `ListenProgress`. The recorder, `pageFinished` and a
  rollback's rewrite store progress only on a page holding that text (`LibraryStore.holds`), and
  `rekeyActiveSession` moves the session only onto a page holding it, else stops it. The crash
  resume file carries it too, and `AppLaunch.resumeAfterCrash` applies its paragraph only on a
  page holding it. Anything new that writes a position, start or end onto a page, or moves the
  session to another key, goes through the same check.
- **Position.** Only `PlaybackSessionState` holds it, and a seek publishes it synchronously in
  the same transaction as the UI change; the scrubber relies on that to avoid a snap back. An
  engine never reports a spot before the offset its play started at.
- **Per-tick cost.** The live offset changes several times a second. Read it only in leaf views
  (`PlayheadReader`, the Now Playing bar's progress, Now Playing's sentence underline); reading it
  in a screen's body redraws the screen on every tick.
- **Model calls.** One at a time (`SynthRenderGate`), never a Core ML call in the background
  (`RenderAdmission`; the Core ML route's `KokoroSplitHost` switches itself to ONNX there for the
  rest of the process). Every extra Kokoro call is exposure to an uncatchable crash on iOS 26.4+, so
  don't add re-renders: `BrowseSaveWhilePlayingTests` pins the call count.
- **Thread counts are per phase.** In front the ONNX session runs every core but one (3 to 6,
  `KokoroRouteSettings.defaultThreads`), in the background one; the first call after a phase
  change rebuilds the session (`KokoroONNXSessionSlot`). Pick the front count from the CPU route
  benchmark on a device, not from the Mac (`KokoroONNXThreadSweepTests` is only a proxy: a Mac
  has more performance cores than an iPhone's two).
- **Background rendering is budgeted.** On the ONNX route the background gets one thread and
  bake-ahead runs only in bursts between the watermarks (`BackgroundRenderWatermarks`); between
  bursts the worker is idle until playback wakes it (`GlobalSynthQueue.playbackAdvanced`, called
  by `LocalListenEngine` on each unit start and resume). Back-to-back background rendering got the
  app killed by iOS. Anything new that renders in the background goes through the queue's
  admission, and nothing holds a background task per chunk. Downloads (`../../Downloads/`) are
  ordinary bake jobs (`LocalTTSCoordinator+Downloads`): they park in the background and never
  count as playing.
- **`renderObserver` is told inside the queue's work** (`noteBakeMarksChanged` runs mid drain,
  `bakeCompleted` from the worker): an observer acts later, never re-entering the queue in the
  call.
- **Chunk plans are data.** Live playback and bake-ahead share one deterministic plan per text;
  stitched paragraphs store `chunkDurations` by it. Changing `TextChunker` limits or rules changes
  plans: stitched audio stays playable, but mid-paragraph seek offsets into old audio drift until
  it re-renders. Decide whether that needs a cache purge (`KokoroAudioCachePurge` bumps a version).
- **Listen blocks are versioned.** Changing `ListenHTMLBlocks` rules means bumping
  `ListenHTMLBlocks.version`; library pages rebuild once and positions / audio must be remapped
  like `LibraryStore.migrateParagraphLayout` does.
- **Engine changes go through `EngineHandover`.** Views call `selectEngine` / `chooseVoice` /
  `deleteModel`; they never restart playback.
- **Persisted ids and keys** are pinned by `EngineRegistryTests.testPersistedIDsAndCacheKeysUnchanged`.

## Testing here

- Fakes: `Tests/Fakes/FakeEngineProvider.swift` (an engine with configurable latency, caps and
  failures), `FakeListenEngine`, `FakeUnitSource`, `ArticleAudioCache+Fixtures.swift`.
- Behavior that only shows on a device (the libBNNS crash, real render speed, background
  limits) is measured with a Release build and the timing log; see LISTEN_PLAYBACK.md →
  "Diagnostics".
