# Listen playback

How Reader speaks an article: Apple TTS, or Kokoro on the device (engines: `TTS_ENGINES.md`).
One ownership story, so Play continues, Pause matches what you hear, and rendering ahead makes
starts fast.

## Model

```
UI ──intent──► SpeechController ──command──► bound ListenEngine
                │ PlaybackSessionState ▲          ├─ AppleListenEngine (AVSpeechSynthesizer)
                │ (document, position, │          └─ LocalListenEngine → LocalListenPlayer
                │  phase, resume point)│                                   └─ ListenUnitSource (per play)
                └──────────────────────┴── engine events                     ├─ ArticleAudioCache (rendered paragraphs)
                                           (PlaybackEngineEvent)             └─ GlobalSynthQueue → LocalSynthService (model)

Render queue: GlobalSynthQueue renders chunks ahead of the playhead (and bakes saved articles)
into ArticleAudioCache, admitted by RenderAdmission.
```

### Playback session (the one source of truth)

`PlaybackSessionState` (held by `SpeechController.playback`) owns:

| Field | Meaning |
|--------|---------|
| `articleID` | Session identity (the saved article's id / `SpeechSession.id`) |
| `document` | Ordered paragraphs |
| `playhead` + `utf16Offset` | The position: paragraph and document UTF-16 offset of the spot being spoken |
| `phase` | `idle → prepared → playing ↔ paused → finished` |

The scrubber, the paragraph highlight, Now Playing and crash resume all read the position from
here, and every change is published synchronously. `resumePoint` (article + paragraph while
playing, nil otherwise) is what crash resume reopens; the controller writes it to
`ListenResumePointStore` whenever it changes.

Phase and position change only through:

- **intents** from the UI and remote commands: `play`, `pause`, `resume`, `toggle`, `stop`,
  `skip`, `seek`, `seekOffset`;
- **engine events**: `becameAudible`, `becamePaused`, `position(paragraph, utf16)`, `finished`
  (`statusChanged` only tells the controller to re-read the listen-bar status).

Rules:

- Pause sends `.pause` to the engine; the phase turns paused on `becamePaused`, or at once when
  the engine snapshot already shows it paused.
- Engines never clear the session. They emit `finished`; the session decides idle / finished.
- At the end the engines stop, the audio session deactivates and the lock screen clears, but the
  page stays bound in `finished`: the Now Playing bar keeps it with ▶ and "✓ Finished", and ▶
  plays it again from the start. Only *Stop Listening* (the bar's long-press) unbinds it.
- `toggle`: playing **or** the engine audible → pause; paused → resume; else play.
- Seek (scrubber release) moves the playhead and offset; playing keeps playing from there, paused
  stays paused (the engine re-queues without sounding), prepared / finished just move where Play
  starts.

### What you hear, as the screens see it

`SpeechController` derives everything the screens show about what you hear from the session:

- **`nowPlaying`** (`NowPlaying`): the bound page's key, canonical URL, title, source (its host),
  artwork, where it plays from (`PlayingFrom.site(host:)`) and phase. nil only before anything has
  played and after Stop Listening.
- **`playState(of:)`** for a `ListenTarget` (`.page(key)`, or `.webPage(canonicalURL:)`, compared
  as strings so a saved article with a pre-v2 random id still matches its page): `idle`,
  `preparing` (the target of the current `beginPreparing` request, e.g. 🎧 while its page is
  extracted; a newer request, Stop Listening and every other playback intent end it, and only a
  request that `isStillPreparing` may start),
  `playing`, or `paused` (`.prepared` and `.finished` show as paused). Every ▶ / ⏸ / 🎧 comes from
  it.
- **`press(_:start:)`**: playing → pause; paused → resume (from `.finished`, replay); anything
  else runs `start`, which replaces what is playing. Pressing never navigates.
- **`nowPlayingContent()`**: Now Playing's reading content, asked of the injected
  `NowPlayingContentResolving` (a saved article from its row; an unsaved page from the
  `ReaderArticle` it was started with, kept in memory, so it isn't restored after a relaunch).

### Engine adapters (`ListenEngine`)

`SpeechController.speak` binds one adapter per utterance. An adapter takes
`play(ListenPlayRequest)`, `pause`, `resume`, `stop` and `setRate`, reports `PlaybackEngineEvent`s
through `onEvent`, and answers `snapshot` (audible / paused). The controller drops events from an
engine that isn't bound (a cancelled utterance, a cleared player). Speed is a setting every
adapter keeps, bound or not. Adapters report facts; they own no bake policy and no UI phase.

- **`AppleListenEngine`**: one `AVSpeechUtterance` holding the rest of the article from the
  start offset; `pauseSpeaking(at: .word)` / `continueSpeaking`. The delegate reports
  `becameAudible`, `becamePaused`, `position` (the word about to be spoken) and `finished` (the
  live utterance's `didFinish`). Callbacks from a stopped or replaced utterance are dropped. A
  speed change re-speaks from the word being spoken. A paused `play` holds nothing; Resume plays
  from the playhead.
- **`LocalListenEngine`** drives `LocalListenPlayer` (file player + producer; plays rendered
  CAF units only). Each play binds one `ListenUnitSource` (`QueueUnitSource`: the article's
  paragraphs in one voice, over the audio cache and the render queue); the player never touches
  the model. A `play` or `stop` that arrives while the model loads wins: the waiting play returns
  without starting. Pause keeps `AVAudioPlayer.currentTime` and is confirmed at once; resume plays
  on with no re-queue. The end of the article is decided only by the player
  (`ChunkPlaybackQueue`): the producer calls `endOfInput()` once it has enqueued every paragraph,
  and the player finishes when its queue drains. Position inside a paragraph is player time, which
  has no callbacks, so while audio is wanted the engine samples it 5×/s: in the foreground it
  reports `position` once the spot moved a few characters (`ListenPositionMapper`: chunk
  boundaries plus time into the chunk, never before the offset the play started at) and
  `statusChanged` when the listen-bar status changed; in the background it only holds
  `ReaderListenGap` while waiting for audio. Speed is a pitch-preserving time-stretch on the
  player (`AVAudioPlayer.enableRate` / `rate`; everything is rendered at 1×). If the host fails
  to load it calls `LocalSynthService.noteSpeakFailed`, and engine binding re-speaks the spot with
  Apple.

### Engine binding

- `LocalSynthService` (`LocalTTSCoordinator.synth`) holds the on-device model: the one resident
  host behind `LocalChunkRenderer`, the Apple renderer for text the engine can't produce, and the
  lifecycle `state` (`LocalEngineState`): `off` (Apple speaks), `warming(id, progress, task)`
  (download / load in flight; `task` is the single load, cancelling it abandons the load),
  `ready(id)`, `failed(id, message)` (Apple speaks; Settings shows the message). On every change
  the coordinator persists `reader.tts.engineID` and calls `onEngineChange`.
- `speak` picks the engine once (`ListenRoute`: Apple, or the ready on-device engine and its
  voice when it speaks the article's language) and binds it. Pause, resume, the play icon,
  "Preparing next…" and stop go to the bound engine until stop or the next `speak`.
- On `onEngineChange` the controller compares the bound route with the one `speak` would pick now
  (`EngineHandover.decide`):
  - Apple audible: it finishes the paragraph it is speaking; the next starts on the on-device
    engine.
  - Apple paused: re-speaks, paused, at the playhead on the on-device engine.
  - On-device engine bound but no longer the pick (Apple chosen, model deleted, load failed, route
    reload, voice change): re-speaks at the playhead now.
- Views only call `selectEngine`, `chooseVoice`, `deleteModel` or `synth.cancelDownload`; they
  never restart playback themselves.

### UI binding

Views bind to `phase` and the position (and the paragraph highlight derived from them), never a
second "is playing" flag. The live offset is read only in small leaf views (`PlayheadReader`, the
Now Playing bar's progress, Now Playing's sentence underline), so a tick redraws only those. The
Reader never scrolls by itself; Now Playing follows the audio until you scroll (`NAVIGATION.md`).

While the phase is playing but nothing is audible and more units remain (`isBufferingNext`), the
listen bar shows a spinner and "Preparing next…". That is not paused.

The listening position is saved from the session, whatever is on screen, by
`ListeningProgressRecorder` (built at the composition root): `SpeechController.onProgress`
reports each new paragraph and every phase change (pause, finish, stop, and the stop that comes
before a page is replaced) synchronously, and the recorder also writes the live offset when the
app leaves the foreground. Never per tick. It writes saved articles' position and the listen
history (`SavedArticleProgressStore`); unsaved pages keep none.

## Rendering ahead (on-device engine)

### Render queue

One **`GlobalSynthQueue`** owns all on-device synthesis, live and ahead. A single worker renders
one **chunk** per iteration, so the playhead can preempt bake-ahead between chunks; two model
calls never run at once (`SynthRenderGate.shared`). Actions reorder the queue (`openArticle`,
`focusPlayhead`, demote on switch); nothing builds its own render loop.

1. Open an article → it becomes #1; render from the resume point to the end, then fill gaps
   above it.
2. Skip / jump / seek → still #1; the cursor moves to the new paragraph.
3. Open another article → new #1; the previous one is demoted (its cache is kept).
4. Pending jobs fold in once the engine is ready (`adoptPending`): the article being listened to
   stays #1; any other job is #1 only if the queue is empty; the rest keep their plans, demoted.

`BakePriorityPlan` is the explicit cursor:

| Event | Plan |
|-------|------|
| Article save | `topDown`: `0…end` |
| Listen start / jump | `fromPlayhead(p)`: `p…end`, then missing `0..<p` |
| Playback finished / stopped | `startBakeIfNeeded` (`topDown`): fill leftover gaps |

Saving an article that is #1 keeps its plan; only the job's ephemeral flag flips
(`GlobalSynthQueue.setEphemeral`).

**Priority and admission.** Chunks of an article someone is listening to (a producer waits on
one, or its audio is playing) render at `RenderPriority.listener` (`.userInitiated`); bake-ahead
runs at `.utility`. Bake-ahead is held while the thermal state is `.serious` or worse or Low Power
Mode is on (`BakeConditions`) and resumes on the change notification. Before every chunk, in
`ensureChunk`, on every app-phase change and when a render fails, one pure rule decides
(`RenderAdmission.decide`, `RenderAdmissionTests`):

| App phase | ONNX CPU route (renders in background) | Core ML route |
|---|---|---|
| active | render | render |
| inactive | render | listener's chunks only; bake-ahead parks |
| background | listener's chunks + bake-ahead of the playing article; other articles park | no model call: a listener's chunk plays with Apple, bake-ahead parks |

The renderer checks it again right before each model call (`LocalChunkRenderer`,
`RenderAdmission.modelCallsAllowed`): no Core ML call ever starts in the background (no GPU
there, and the CPU fallback is the libBNNS crash path).

**Producer.** The player keeps a short buffer of rendered units and stops producing when it is
full. Chunk 0 plays as soon as it is rendered; the producer doesn't wait for the paragraph. Seek /
jump cancels the producer's pending units and restarts it at the new playhead; pause and resume
leave it alone. `ChunkPlaybackQueue` primes the next `AVAudioPlayer` while the current unit plays,
so joins between rendered units stay near zero; a gap only appears when rendering can't keep
ahead of the playhead (counted as a starve event).

**Head-start rule** (`HeadStart`, `RenderPace`): before rendering a chunk for a listener, the
engine projects whether rendering at the measured speed would starve playback by more than 2 s;
if so that paragraph plays with Apple ("Kokoro fell behind", `render_behind`). Only listener
calls feed `RenderPace`.

**Never silent, never skipped.** A chunk the engine can't render is rendered with Apple
(ahead), or the rest of the paragraph is spoken with Apple (live). Only if Apple also fails is
the paragraph skipped, logged as `SKIP pN` in the debug overlay and `skip` in the timing log.
Failed units go into `failedUnits`, so the worker never loops on them; a live request retries
once. An overflowing call (`inputTooLong`) is re-split down to 24 units.

### Chunking

The paragraph is the listen unit; internally `TextChunker` cuts it into chunks sized per engine
(`EngineDescriptor.limits`; units ≈ characters, digits count 3). Invariant (unit-tested):
`chunks.joined(" ") == normalize(text)`.

| Limits | Target | Hard max | First chunk | Used by |
|---|---|---|---|---|
| `kokoroCPU` | 240 | 280 | 80 (a whole first sentence ≤ 104) | Kokoro, ONNX route |
| `kokoro` | 220 | 300 | 100 | Kokoro, Core ML route sizing |
| `tenSecondCall` | 120 | 140 | 90 | Apple fallback text, ~10 s-per-call engines |

- **Sentences first.** Whole sentences are packed up to the chunk's budget (abbreviation-,
  initial-, "U.S.A."- and decimal-aware). A sentence that fits the hard max is split only to make
  the short first chunk or the ramp; longer ones are cut by `balancedSplit` (sentence-like
  `etc. The` > `; : —` > `,` > before a conjunction > space, pieces balanced). Aside dashes become
  commas, intra-word hyphens stay, a dash glued to punctuation goes ("etc-." → "etc.").
- **First chunk** (fast first audio):
  1. the whole first sentence if ≤ `firstTarget + 24`;
  2. else its head at the best clause boundary inside `firstTarget` (`; : —` > comma > before
     and/but/which/when…), at least a third of the budget long;
  3. else up to `firstTarget + 40` (120 units): the whole sentence, or the nearest clause boundary
     past the budget. On the phone the ONNX route renders ≈ 0.35 s + 23 ms per char (median,
     28 ms worst), so 120 units is ≈ 3 s to first audio, the most that still feels prompt;
  4. only for a clause-free run longer than that: a space cut inside the budget.
  A tiny first sentence ("Yes.") takes the next sentence, or its head at a clause, while it stays
  ≤ 120 (`growShortFirst`), so it doesn't play out before chunk 1 is ready.
- **Ramp.** Chunk k renders while chunks 0…k−1 play, at ≥ 2× real time, so chunk k ≤
  2·u₀ + u₁ + … + u_{k−1}; the second chunk is at most 160. A whole sentence may overshoot by
  25 % rather than be cut mid-phrase, and a sentence with no clause boundary inside the budget
  stays whole: on ordinary paragraphs the ramp is a target, not a guarantee.
- **Joins.** Kokoro pads every call with ≈0.3 s of leading and ≈0.5 s of trailing silence.
  `ChunkEdgeTrim` (hosts with `trimsEdgeSilence`: the ONNX route) keeps 40 ms before speech and a
  trailing pause by boundary: sentence 360 ms, clause 180, word 40, paragraph end 520. A cut
  before a conjunction counts as a clause (the queue passes the next chunk's first word). Joins
  are ≈0.40 s at sentences and ≈0.22 s at commas, like Kokoro's own pauses.

### Long paragraphs

Paragraphs over **1,200 characters** are split at sentence ends into balanced pieces for display,
navigation and audio alike (`ParagraphSplitter`, listen layout v3), so tap-to-seek, resume,
highlight and the paragraph picker stay fine-grained.

- A paragraph of length L > 1,200 is cut into k = ⌈L/900⌉ pieces (≥ 2) by a DP that minimises
  the squared deviation from L/k with every piece ≥ 300 characters; if no such cut exists it
  tries fewer pieces, else the paragraph stays whole (a single giant sentence stays whole; the
  chunker still splits it for synthesis). Sentence starts come from `TextChunker.isBoundary`.
  Deterministic.
- **The HTML is split, not a side list.** `ListenHTMLBlocks.splitLongBlocks` rewrites leaf `<p>`,
  `<blockquote>`, `<dd>` blocks, closing and reopening inline tags at each cut (ids stay on the
  first piece). `li`, `td`, headings and `pre` are never split. The reading HTML
  (`ParagraphDocument.readingHTML`) and the listen paragraphs (`ParagraphDocument.forListening`)
  come from the same split HTML, so web-view block index = listen / queue / cache paragraph
  index. Plain text splits the same way (`ParagraphDocument(plainText:)`).
- **Migration** (`ArticleLibrary.migrateParagraphLayout`, run by `AppLaunch` before the identity
  migration and crash resume): saved rows with `listenBlocksVersion < 3` get new blocks; the
  reading position maps by character offset (`ParagraphPositionMap`); the resume point, the
  in-memory crash-resume target and any pending bake job are remapped; cached audio of unchanged
  paragraphs moves by text hash, and a split paragraph's CAF is sliced sample-exact
  (`ArticleAudioCache.remapSplitParagraphs`, by `chunkDurations`) into each piece whose chunk
  plan equals a contiguous run of the old chunks; other pieces re-render. Logged as
  `paragraph_layout_migration`. The same remap runs for unsaved reader keys in
  `LocalTTSCoordinator.prepareListenIdentity`.

## Audio cache

`ArticleAudioCache`, `Application Support/TTSCache/<article key>/`:

- `index.json` + `p-NNNN.caf` per rendered paragraph, written incrementally so a partial render
  plays. Each entry stores the paragraph's `textHash` and, for stitched paragraphs,
  `chunkDurations` (mid-paragraph seek and resume). The index is read once per article and kept in
  memory; every write goes through it, so ready / playable reads never touch the disk.
- Chunk scratch: `chunks/p-NNNN-<texthash>/c-KK.caf`. Once every chunk of a paragraph exists the
  worker stitches them off the main actor into `.stitch-p-NNNN.caf` and renames it over
  `p-NNNN.caf` (a CAF that may be playing is never written into), then records it on the main
  actor. Replays use the stitched file. Scratch is disposable at launch; while an article has a
  queue job, scratch whose text hash still matches its paragraphs is kept
  (`removeChunkScratch(for:keepingCurrent:)`), because every extra Kokoro call is exposure to the
  libBNNS crash (`BrowseSaveWhilePlayingTests` pins the call count).
- **Keys** (`ARTICLE_IDENTITY.md`): one per canonical URL, saved or not. Leaving an unsaved
  reader keeps its audio; ephemeral caches are pruned after 7 days or past 500 MB. Save only marks
  the cache saved; unsave marks it ephemeral again; deleting a saved row deletes its audio.
- **One voice per article.** The index's top-level `engineID` / `voiceID` is the target voice.
  After a voice or engine switch, the first new-voice write retargets the index; older entries
  stay, stamped stale. Ready / missing counts look only at the target voice, so the queue
  re-renders the article, while playback uses the stale CAF until each paragraph is replaced
  (`playableAudioURL`). When the article is complete in the new voice, `finalizeVoiceSwitch`
  deletes the leftovers. `GlobalSynthQueue.engineDidChange` retargets queued jobs
  (`VoiceSwitchTests`).
- **Language gate.** An article in a language the engine doesn't speak plays with Apple and is
  kept out of the on-device queue (`LocalTTSCoordinator.localLanguageGate`).

**Pending jobs.** Articles saved or opened while the engine was cold are kept as pending bake
jobs in `Application Support/PendingBakeJobs.json` (`PendingBakeJobStore`) and fold into the
queue once the engine is ready. Nothing bakes while the app is suspended: the app registers no
background task, and full-article rendering in the background is not promised.

**Core ML compile cache.** Core ML adds compiled bundles under
`Library/Caches/<bundle>/com.apple.e5rt.e5bundlecache/<os build>/` after every install and never
evicts the stale ones (a development phone reached 16.7 GB). `CoreMLCompileCacheJanitor` runs once
per install (`reader.coreml.e5janitor.installID` = the install's container UUID; bundle file
dates read as the epoch on device) and deletes bundle dirs whose newest file predates this launch.
Logs `coreml_cache_prune`.

## Language

- **Detection** (`ListenLanguage`): `NLLanguageRecognizer` over the first 4,000 characters of the
  listen blocks; needs ≥ 24 letters and confidence ≥ 0.5. Stored in
  `SavedArticle.detectedLanguageCode` (written with the listen blocks, backfilled on open for
  older rows); unsaved articles use an in-memory memo. Passed through
  `SpeechSession.detectedLanguage`.
- **Resolution** (`ListenLanguageResolution.resolve`): "Automatic (match article)" (the default,
  `reader.languageAutomatic`) or a manual language. If the selected engine doesn't speak it
  (`EngineDescriptor.supportedLanguages`; Kokoro is English only), that article speaks with the
  best Apple voice for the language, without changing settings, and the listen bar and the
  Language footer say so ("Apple · French (Kokoro is English-only)").

## Settings → Listen

`SpeechSettingsView`. Every row is one `SettingsRow` (title, optional one-line subtitle, fixed
accessory and check slots, min height 48), so state changes never move rows
(`ListenSettingsLayoutUITests`).

1. **Engine**: Apple and the registry's on-device engines. State lives in the subtitle
   ("Downloading… 42%", "Preparing voice…", "Ready · recommended") and the accessory (a progress
   ring with a stop square cancels). Swipe to delete a downloaded engine; crash and failure
   notices in the footer.
2. **Voice · <engine>**: the selected engine's voices (Kokoro: curated rows with preview; Apple:
   "System default" and good-quality system voices for the language).
3. **Language**, 4. **Speed**.
5. The version row (a 2 s long-press toggles developer options, `NAVIGATION.md`), then **Listen
   debug** while developer options are on.

## Background listening

Leaving the app (Home, lock, app switcher) keeps Listen playing. Closing Now Playing or a Reader
keeps it playing too; the Now Playing bar shows it.

**Audio session** (`ListenAudioSession`): `UIBackgroundModes: [audio]` (`project.yml`). Category
`.playback`, mode `.spokenAudio`, no options: a mixable (ducking) session never becomes the Now
Playing app, so other apps' audio pauses while Reader speaks, like a podcast app. Only the
category is set at launch; the session activates when playback starts or resumes and deactivates
with `.notifyOthersOnDeactivation` on stop or finish.

**Lock screen / Control Center** (`NowPlayingController`):

- `MPNowPlayingInfoCenter`: title = article, artist = "site · Paragraph N of M", album = site,
  chapter number and count, progress N/M, favicon artwork, rate 0 while paused. Shown while
  playing or paused; cleared on stop or finish.
- `MPRemoteCommandCenter` (decision D4: headphone and lock-screen skips are paragraph skips, like
  the on-screen ⏮ ⏭): play, pause, togglePlayPause, nextTrack (next paragraph),
  previousTrack (previous paragraph, or restart paragraph 1) and changePlaybackRate (snapped to
  the listen-bar rates). Skip, seek and position commands are off.
- Every command goes through `SpeechController.handleRemoteCommand` → `RemoteCommand.intent` →
  `PlaybackSessionState.handle`, the same path as the on-screen buttons. Now Playing is
  re-derived from `playback` on every change; identical updates are skipped.

**Interruptions and route changes** (`ListenInterruptionPolicy`, pure and unit-tested; every pause
and resume goes through session intents):

| Event | Action |
|---|---|
| Call, Siri or alarm starts while playing | Pause; remember it was playing |
| Interruption ends with `.shouldResume`, and it was playing | Reactivate the session and resume |
| Interruption ends without `.shouldResume` | Stay paused |
| `appWasSuspended` notice | Not a real interruption; never auto-resume |
| User pauses, stops or plays during an interruption | Forget the auto-resume |
| Route change `oldDeviceUnavailable` (headphones out, Bluetooth lost) | Pause |
| Media services reset | Reconfigure the category and pause |

**Rendering in the background.** `AppRunState` mirrors `UIApplication` (active / inactive /
background), thread-safe; admission follows the table in "Render queue". On the ONNX route the
playing article keeps rendering. On the Core ML route a paragraph that isn't rendered yet plays
with Apple (`AVSpeechSynthesizer.write` into a temp CAF, played in order, not cached) until the
app is back in the foreground; a chunk that failed because of backgrounding is never replaced
with Apple audio in the cache. `BackgroundGrace` (`beginBackgroundTask`) holds `ReaderListenGap`
while the player waits for audio in the background and `ReaderSynthDrain` so a chunk in flight at
backgrounding can finish and write its CAF; neither permits GPU work.

## Diagnostics

Developer options on (`NAVIGATION.md` → "Developer options"):

- **Listen debug** (Settings → Listen): a **Debug** chip on the listen bar opens a live overlay
  above the controls: article identity (`eph:` / `svd:` + short id), queue #1 and demoted count,
  active / next unit, worker busy or idle, warming model, article render % (ready / total),
  phase, last render event, render mode ("foreground · …", "inactive · …", "background · …"),
  paragraphs ready ahead, what the last background stretch played, and recent log lines.
- **Listen debug panel** (Open full panel, or long-press ▶︎): the same plus buffer / starve /
  handoff numbers, the audio-session state, the Kokoro route toggle, and the last lines of
  `ListenDebugLog`; Debug builds add the engine probe and the CPU route benchmark.

**Timing log.** `Application Support/ListenTiming/timing.jsonl` (rotates at 2 MB to
`timing.1.jsonl`): launch, open, play, model load, every `synth` call (chars, wall ms, audio s,
phonemes, `mem_mb`), chunk / paragraph ready and failed, waits, first audio, buffering, Apple
fallback, skips, app phase and background events, remote commands, interruptions, migrations and
cache prunes. Pull it from a device:

```sh
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier com.jimmyyao.Reader --source "Library/Application Support/ListenTiming" \
  --destination /tmp/timing
```

**Debug-build tools** (launch arguments compile only in Debug):

- `-engineProbe [-probeOnly Kokoro]` or the panel's "Run engine probe": per engine, init,
  first-chunk latency and wall vs audio time for 60 / 150 / 400 characters, into
  `Documents/engine_probe.txt` (written before each step, so a crash shows where it died). It
  reuses the app's live host for the selected engine (a second loaded copy of the same models
  fails on device) and holds the render worker while it runs.
- `-bakeArticle <saved id prefix>`: render that saved article top-down in the foreground without
  playing it, then pull ListenTiming and TTSCache.
- `-selectEngine local.kokoro|apple`, `-kokoroUnits <label>` (Core ML route routing).
- **CPU route benchmark** (panel → "CPU route benchmark"): `KokoroONNXSession` at 1–4 threads and
  QoS variants on a fixed 501-phoneme passage and its first three sentences (load ms, cold / warm
  times, × real time, CPU-s per audio-s, thermal, memory), plus a lock-screen soak that renders
  continuously for N minutes. Pauses the queue and holds the render gate. Output
  `ListenTiming/cpubench.jsonl` and a sample WAV.

Measure on a device with a **Release** build: FluidAudio in Debug is ~3× slower per decode step.

## Verify

- Apple: while audible the button shows Pause, and a tap always pauses.
- Kokoro: Play continues past paragraph 1; Pause mid-paragraph and Play resume at the same spot.
- A partly rendered article starts from the cache for rendered units.
- Consecutive paragraphs have near-zero gaps when rendered ahead.
- A unit Kokoro can't render plays with Apple; playback never goes silent or freezes.
- Skip / jump re-prioritizes from the new playhead; after listening from mid-article, rendering
  returns to the top so the whole article ends up on disk.
- Background: baked audio plays, the playing article keeps rendering on the ONNX route, nothing
  renders with Core ML.

Unit tests by area: `PlaybackSeekTests`, `PlaybackObservationTests`, `ListenPositionTests`,
`EngineBindingTests`, `AppleListenEngineTests`, `LocalListenPlayerTests`, `SynthPipelineTests`,
`RenderAdmissionTests`, `TextChunkerTests`, `HierarchicalChunkerTests`, `FirstChunkBoundaryTests`,
`ChunkEdgeTrimTests`, `ParagraphSplitTests`, `ParagraphLayoutMigrationTests`, `VoiceSwitchTests`,
`BackgroundListeningTests`, `BrowseSaveWhilePlayingTests`.
