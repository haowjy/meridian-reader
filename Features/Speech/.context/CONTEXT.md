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
  a replaced page's last spot (the `.stop` before the next `bind`).
- **Position.** Only `PlaybackSessionState` holds it, and a seek publishes it synchronously in
  the same transaction as the UI change; the scrubber relies on that to avoid a snap back. An
  engine never reports a spot before the offset its play started at.
- **Per-tick cost.** The live offset changes several times a second. Read it only in leaf views
  (`PlayheadReader`, the Now Playing bar's progress, Now Playing's sentence underline); reading it
  in a screen's body redraws the screen on every tick.
- **Model calls.** One at a time (`SynthRenderGate`), never a Core ML call in the background
  (`RenderAdmission`). Every extra Kokoro call is exposure to an uncatchable crash on iOS 26.4+, so
  don't add re-renders: `BrowseSaveWhilePlayingTests` pins the call count.
- **Chunk plans are data.** Live playback and bake-ahead share one deterministic plan per text;
  stitched paragraphs store `chunkDurations` by it. Changing `TextChunker` limits or rules changes
  plans: stitched audio stays playable, but mid-paragraph seek offsets into old audio drift until
  it re-renders. Decide whether that needs a cache purge (`KokoroAudioCachePurge` bumps a version).
- **Listen blocks are versioned.** Changing `ListenHTMLBlocks` rules means bumping
  `ListenHTMLBlocks.version`; saved rows rebuild once and positions / audio must be remapped like
  `ArticleLibrary.migrateParagraphLayout` does.
- **Engine changes go through `EngineHandover`.** Views call `selectEngine` / `chooseVoice` /
  `deleteModel`; they never restart playback.
- **Persisted ids and keys** are pinned by `EngineRegistryTests.testPersistedIDsAndCacheKeysUnchanged`.

## Testing here

- Fakes: `Tests/Fakes/FakeEngineProvider.swift` (an engine with configurable latency, caps and
  failures), `FakeListenEngine`, `FakeUnitSource`, `ArticleAudioCache+Fixtures.swift`.
- Behavior that only shows on a device (the libBNNS crash, real render speed, background
  limits) is measured with a Release build and the timing log; see LISTEN_PLAYBACK.md →
  "Diagnostics".
