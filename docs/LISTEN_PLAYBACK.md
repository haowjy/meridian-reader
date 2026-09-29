# Listen Playback Architecture

Status: target model for Reader Listen (Apple TTS + Kokoro, the only local engine; Chatterbox Nano was retired 2026-09-24).  
Goal: one ownership story so Play continues, Pause matches audible audio, and bake makes start fast.

## Problems the old design created

1. **Optimistic UI phase** — `SpeechController.playbackState` was set in `pause()` / `resume()` / `speak()` before AVSpeechSynthesizer or AVAudioPlayer agreed. Result: audio still audible while the button showed Play, and `toggle` called `resume()` which no-op’d (`guard synthesizer.isPaused`).
2. **Engines cleared the session** — (then Nano) local-engine queue-empty called `onFinished` → `clearSession()` even when the next paragraph was still synthesizing. Apple had a separate finish path. Session lifetime was not owned in one place.
3. **Local-engine “generation” on resume** — bumping a cancel token on pause/resume discarded in-flight synth, advanced the produce cursor, and broke playhead / highlight.
4. **Flag tangle** — `isSpeaking`, `isPaused`, `fillingGeneration`, `producerActive`, `speakGeneration`, `suppressCancelSideEffects` overlapped. Fixes fought each other.
5. **Bake unused at play** — save-time bake existed, but play often cold-synthed; bake contended on the same local-model render gate.

## Target model

```
UI ──intent──► PlaybackSession ──command──► Engine adapter
                     ▲                         │
                     └── engine events ────────┘

Background: AudioProducer / BakeCache fills units ahead of playhead.
```

### 1. PlaybackSession (single source of truth)

Owns:

| Field | Meaning |
|--------|---------|
| `articleID` | Session identity (same as saved article / SpeechSession.id) |
| `document` | Ordered paragraph units |
| `playhead` | Current unit index (+ UTF-16 offset for Apple highlight) |
| `phase` | `idle → prepared → playing ↔ paused → finished` |

**Phase changes only via:**

- **Intents** from UI / controller: `prepare`, `play`, `pause`, `resume`, `toggle`, `stop`, `skip`, `seek`
- **Engine events**: `becameAudible`, `becamePaused`, `playheadAdvanced`, `finished`, `failed`

Rules:

- Never set `phase = paused` only because the user tapped Pause; send `.pause` to the engine, then set paused on `becamePaused` **or** after verifying `engine.isPaused` / `!engine.isAudible`.
- Never let an engine call `clearSession` directly. Engines emit `finished`; the session decides idle/finished and whether to release the article.
- `toggle`: if `phase == .playing` **or** engine reports audible → pause intent; else if paused → resume; else play.

### 2. Engine adapters (dumb players)

| Adapter | Role |
|---------|------|
| Apple | One utterance (or remaining text). `pauseSpeaking` / `continueSpeaking`. Mirror `isSpeaking` / `isPaused` into events. |
| Local engine / Kokoro (file player) | Plays **Ready** CAF URLs only. Pause keeps `AVAudioPlayer.currentTime`. Resume = `play()` — **no** produce-epoch bump, **no** queue clear. |

Adapters do not own article documents, bake policy, or UI phase.

### 3. AudioProducer + BakeCache (ahead of playhead)

Each unit is `Ready(URL)` or `Missing`.

- **BakeCache** (`Application Support/TTSCache`): incremental `index.json` + `p-NNNN.caf` so partial bakes are playable.
- **Single Core ML worker**: never run two Core ML renders in parallel (that crashed before). Live listen and background bake share one gate.

#### Priority producer

Two *logical* lanes, one physical synthesizer:

1. **Immediate** — playhead + next few paragraphs into the player buffer; always preempts.
2. **Batch / next** — remaining work from the current priority start downward, persisting each CAF as it completes.

`BakePriorityPlan` is the explicit cursor:

| Event | Plan |
|-------|------|
| Article **save** | `topDown` — bake `0…end` |
| Listen **start** / paragraph **jump** | `fromPlayhead(playhead)` — bake `playhead…end`, then **return to top** for missing `0..<playhead` |
| Playback **finished** | `resumeGapFillBake` / `topDown` — fill any leftover gaps |

On seek/jump: cancel in-flight batch for that article, clear non-needed pending player units, bump produce epoch, restart the producer from the new playhead (immediate first).

Produce **epoch** increments only on `stop` / `seek` / new `play` from a new index — **not** on pause/resume.

#### Persistent bake

Every successfully rendered unit (live *or* batch) is written to `ArticleAudioCache.storeParagraph` — not only a temp `live-*.caf`. Future replays prefer the disk CAF via `bakedURLProvider`.

#### Background bake limits

`BackgroundAudioBakeScheduler` registers a `BGProcessingTask` (`com.jimmyyao.Reader.bake-audio`), requests it when articles save, and resumes pending `BakePriorityPlan`s when iOS runs the task.

**Honesty:** iOS will **not** give unbounded Core ML time. A processing task may run briefly while idle/charging — or not at all. We register, request, process what we can, and re-request. Foreground / active-session bake remains the reliable path. Keep baking while the app is active or inactive when the local engine is free; do not promise full-article completion in the background alone.

**Since 2026-09-24 (background listening):** Reader starts **no Core ML call in the background** (see *Background listening* below), so the processing task now just completes (`bg_task_skipped`) and leaves the jobs pending for the foreground queue.


### 4. UI binding

Bind only to `phase` + `playhead` (and derived paragraph highlight).  
Do not cache a second “isPlaying” in the view.  
**Scroll:** highlight the speaking / selected paragraph, but do **not** auto-scroll the viewport to follow it during playback or jump-mode picking — the user owns scroll.

## Migration (vertical slice landed first)

1. Introduce `PlaybackSession` types + reduce phase mutations to `apply(intent:)` / `apply(event:)`.
2. Rewrite the local-engine path as Player + Producer (epoch not bumped on resume; empty queue ≠ finished while producer active).
3. Apple path: pause/resume/toggle go through session + engine snapshot (`isSpeaking` / `isPaused`).
4. Bake-first lookup on produce; warm bake on article open; cancel bake while speaking.
5. Delete redundant flags as call sites move (prefer deletion over new guards).

## Verify

- Apple: while audible, button shows Pause; tap always pauses.
- Kokoro: Play continues past paragraph 1 without Next.
- Kokoro: Pause mid-paragraph, Play resumes same place (same CAF `currentTime`).
- After bake (or partial bake), Play starts from cache for Ready units.
- Kokoro: consecutive paragraphs have minimal silence (prefetch keeps Ready ahead of playhead).
- Kokoro: a bad/missing unit is skipped; playback continues (does not freeze mid-article).

- Skip/jump re-prioritizes from the new playhead (immediate lane); batch elsewhere is cancelled.
- After listening from mid-article, gap-fill returns to top so the full article is on disk.
- Live Kokoro renders persist into `ArticleAudioCache` (not only temp CAFs).
- Background bake is best-effort only; check Settings / cache status after save + wait.

## Listen debug panel

1. **Settings → Listen → Listen debug** (toggle on). A **Debug** chip appears on the listen bar; tap it for a live bake/queue overlay above the controls (dismiss with ✕ or tap Debug again). **Open full panel** in Settings, or **long-press play/pause**, for the full sheet.
2. Overlay focuses on background bake: article identity (`eph:` / `svd:` + short UUID), GlobalSynthQueue #1 + demoted count, active bake unit / next missing, worker busy vs idle, warming local model, **article bake %** (ready/total), phase (`playing` / `buffering` / `paused`), last bake event, and a few recent log lines.
3. Full sheet also shows local-engine buffer / starve / handoff metrics and the last ~30 `ListenDebugLog` lines.

**Jump / select paragraph** lives in the **top** article row of `ArticleReaderScreen` — `[close] [title] [bookmark] [Jump]`, Jump last (hand.tap). While on, a slim hint banner floats over the article; no second chrome row. Not on the bottom listen bar.

**Bake-ready marks (local engine):** Reading surfaces (`HTMLReadingView` / `ParagraphReadingView`) show a quiet not-ready cue on units that lack a usable CAF — hairline left rail + slight opacity; ready units look normal. Marks update live via `ArticleAudioCache.contentRevision`. Apple TTS hides marks (no CAF bake). Article bake % stays in the debug strip only.

Local-engine inter-paragraph silence: `ChunkPlaybackQueue` primes the next `AVAudioPlayer` while the current unit plays and finishes on the main thread without an async hop, so baked CAF handoffs stay near-zero. Starvation still shows as a gap (and increments starve events) when live produce cannot keep ahead of the playhead.


## GlobalSynthQueue + ephemeral Reader cache

One **GlobalSynthQueue** owns all local-engine synth work (listen + background). Actions **reorganize** the queue (`openArticle`, `focusPlayhead`, demote-on-switch); they do not create per-view bake systems. A single Core ML worker always drains current **#1**’s next missing unit into `TTSCache`.

**Unsaved Reader** uses a stable cache key (`ArticleIdentity` v2: canonical URL only; content fingerprint just detects change, per-paragraph `textHash` decides CAF reuse). Bake/play persist CAFs under that key without Save. Leaving Reader does **not** wipe audio (TTL: prune ephemeral after 7 days or over ~500MB). New saves use the same key as `SavedArticle.id`, so Save only marks the cache saved — the live session and playhead are untouched (see ARTICLE_IDENTITY.md).

**Buffering UI:** when phase is playing but the player is not audible and more units remain (`isBufferingNext`), the listen bar shows a small ProgressView + “Preparing next…”. This is not paused.

See also `docs/ARTICLE_IDENTITY.md`.

## Local engine: Kokoro only (Apple fallback) — 2026-09-24

- **Engines** (`SpeechEngineID`): `apple` (always available, default with no model) and `local.kokoro`
  ("Kokoro (on-device)", recommended). **Kokoro is the only local engine.** Chatterbox Nano
  (`local.chatterbox-nano`) was removed (too slow for listening); see "Chatterbox Nano retirement" below.
- **One host at a time.** `LocalModelSpeechEngine` holds a single `LocalSynthHost`
  (`KokoroHost`, built by `FluidAudioProvider` via `EngineRegistry`) wrapped
  in the shared `LocalChunkRenderer`. Selecting another engine drops (unloads)
  the old host before warming the new one. All renders serialize through `SynthRenderGate.shared`
  and the single `GlobalSynthQueue` worker.
- **Cache keys.** `index.json` carries one `engineID` + `voiceID` per article. Kokoro uses
  `engineID=local.kokoro`, `voiceID=kokoro.<voice>` (default `kokoro.af_heart`). See "One voice per
  article" below for voice / engine switches.
- **One SpeechController.** `AppComposition.speechController` is the only instance (built with the
  engine registry at the composition root, injected via `ReaderApp` + the environment default). Before this, `ReaderApp` and
  the environment default each built one, so two coordinators warmed the local model at launch: a
  double download/compile, double memory, and on device two concurrent Kokoro inits followed by a crash.
- **Kokoro compute routing / crash guard.** On iOS 26.4+ Kokoro runs all stages on GPU except the vocoder on
  ANE (`gpuAneVocoder`). FluidAudio's default ANE routing hit the libBNNS SIGSEGV on device
  (see `TTS_ENGINES_SKETCH.md`). `EngineCrashGuard` marks every call of a crash-guarded engine (descriptor flag; Kokoro) in flight
  (`ListenTiming/engine_inflight.json`, log event `engine_crash_detected`). After a crash inside one,
  the next launch falls back to Apple and Settings shows a notice ("Tap Kokoro to try again"). Debug override: `-kokoroUnits <label>`.
- Dev hook: launch arg `-selectEngine local.kokoro|apple` persists that engine.

### Chatterbox Nano retirement (one-time launch migration)

Declared by `FluidAudioProvider.retiredEngines` (`RetiredEngine`: id, display name, done flag
`reader.tts.retired.chatterboxNano.v1`, replacement `.kokoro`, file deleter) and run by
`LocalTTSCoordinator.init`:

1. A persisted selection of `local.chatterbox-nano` becomes Kokoro if Kokoro is installed, else Apple.
2. Once (done flag), `ArticleAudioCache.purgeEngine("local.chatterbox-nano")` deletes every
   Nano-keyed paragraph CAF + its `index.json` entries (legacy pre-engine-key indexes count as Nano),
   removes `index.json`/`chunks/` when nothing survives (keeps `meta.json`), and deletes orphan `p-*.caf`
   files no index references. Bake marks recompute (`bakeMarksRevision` bump).
3. Deletes the Nano model files: `Application Support/fluidaudio/Models/chatterbox-nano` (~746 MB),
   `Application Support/TTSModels/chatterbox-nano` (old Phase-0 store) and `Documents/nano_*` probe output.
4. Logs the freed bytes to the listen debug log (`retired Chatterbox Nano: freed …`) and the timing
   event `retired_engine_cleanup` (`model_bytes`, `cache_*`, `orphan_*`, `total_bytes`, `selection`).

Covered by `EngineRetirementTests`. `Vendor/FluidAudio` keeps its Nano patches (unused by Reader).

### One voice per article (voice / engine switch)

An article keeps only ONE voice's audio (`ArticleAudioCache`):

- `index.json`'s top-level `engineID`/`voiceID` is the target voice. When the user switches Kokoro voice
  (e.g. `af_heart` → `af_bella`) or engine, the first new-voice store retargets the index; existing
  entries stay, stamped with their own `engineID`/`voiceID` (stale).
- Bake marks / % / `readyIndices` / `missingIndices` count only target-voice entries, so the article
  shows as un-baked in the new voice and the queue re-renders it.
- Playback uses `playableAudioURL`: the target-voice CAF if present, else the stale old-voice CAF, so
  listening continues while re-rendering.
- A re-rendered paragraph replaces `p-NNNN.caf` (the old-voice file for that paragraph is deleted).
  The stitch step writes `.stitch-p-NNNN.caf` first so it never overwrites a file that may be playing.
- When the article completes in the new voice, `finalizeVoiceSwitch` deletes any remaining old-voice
  files/entries (`voice switch done … old-voice audio removed` in the debug log).
- `GlobalSynthQueue.engineDidChange` retargets all queued jobs to the new voice key
  (`SynthQueueContext.normalizedCacheVoice`) and kicks the worker. Fully baked articles that aren't
  queued re-render when next opened / listened to.

Before this change (2026-09-24) a switch made old audio unplayable immediately, left the old CAFs on disk as orphans,
and queued BG jobs kept the old key (so they were treated as done). Covered by `VoiceSwitchTests`.

### Core ML compile-cache janitor

Core ML keeps compiled models in `Library/Caches/<bundle>/com.apple.e5rt.e5bundlecache/<os build>/`
and adds new bundles after every app install without evicting old ones (seen on device: 16.7 GB,
326 bundle dirs, mostly Nano + old Kokoro builds). `CoreMLCompileCacheJanitor` runs once per install
(`reader.coreml.e5janitor.installID` = the per-install `Bundle/Application/<UUID>` container name; bundle
file dates read as the epoch on device, so they can't be used) on a GCD utility queue from
`AppComposition.runLaunchMaintenance()`, and deletes bundle dirs whose newest file predates this launch
(Kokoro compiles fresh bundles on the first launch after each install anyway, ~18 bundles / ~130 MB).
Logs `coreml_cache_prune` (removed, kept, bytes).

## Synth chunking + never-silent-skip — 2026-09-24

**Root cause of "long paragraphs skipped" (historical, Chatterbox Nano):** a Nano call can generate at most ≈9.9 s of
audio (247 speech tokens, `.standard` capacity) and read ≤135 BPE tokens. Over the cap FluidAudio
*throws* `generationTooLong` after decoding the whole budget (it does not truncate). The old renderer
chunked at 500 chars with one resplit to ~250 chars (still ≈14 s), so paragraphs over ~180 chars
failed; the queue logged `bake fail`, the producer logged `produce failed … (skip)` and advanced.
Seen on device: Royal Road "The Forgotten" p6 (2543 chars) and p7 (1397 chars) missing from `index.json`.
The drain loop also re-picked the failing paragraph forever (no failed set).

**Rules now:**
- Paragraph stays the UI / listen unit. Internally each paragraph is split by `TextChunker`
  into synth chunks sized per engine (`SpeechEngineID.chunkLimits`), units = chars with digits ×3:

  | engine | per-call cap (FluidAudio) | target | hardMax | first chunk | min resplit |
  |---|---|---|---|---|---|
  | Kokoro | ≤510 IPA phonemes (`phonemeSequenceTooLong`), ≤2000 frames ≈ 50 s | 220 | 300 | 100 | 24 |

  Kokoro sizing: measured on device, phonemes ≈ 1.0x chars (57/60, 138/137, 132/127, 175/173), so 300
  units ≈ 310 phonemes ≈ 18 s of audio, well under both caps. The smaller first chunk keeps
  time-to-first-audio low.

  Split order: sentences (abbreviations, initials, U.S.A., decimals aware) → clauses (`, ; :`) →
  spaces → hard cut. Aside dashes become commas; intra-word hyphens stay. Invariant (unit-tested):
  `chunks.joined(" ") == normalize(text)`. `Limits.tenSecondCall` (120/140/90, formerly `.nano`) remains
  for ~10 s-per-call engines (Apple fallback splitting, speech-swift placeholder).

  Giant-paragraph tests (`TextChunkerTests`: 10k-char punctuated paragraph, 5k-char run-on with only
  spaces, 600-char URL) found two bugs, fixed 2026-09-24: (1) the first chunk could exceed
  `firstTarget` (201/299/285 units vs 100) when the first sentence/clause was long; now its head is cut
  at the best clause/space boundary ≤ `firstTarget`. (2) `normalize` turned a dash next to
  non-quote punctuation inside a token (`z-_`, `/-/`) into ", ", inserting spaces into URLs; now dashes
  only become soft pauses next to spaces, quotes or brackets.
- Overflow (`phonemeSequenceTooLong`/`acousticFramesExceedCap` for Kokoro) re-splits that chunk recursively (≈halves) down to 24 units.
- **Work unit = one chunk.** The worker renders one chunk per iteration, so the playhead can preempt
  bake-ahead between chunks. Chunk scratch: `TTSCache/<article>/chunks/p-NNNN-<hash>/c-KK.caf`; when
  all chunks exist they are stitched into `p-NNNN.caf` with `chunkDurations` (mid-paragraph resume).
- **Play-while-building.** The producer enqueues chunk 0 as soon as it's rendered; it does not wait
  for the whole paragraph.
- **Never silently skip.** If the local engine can't render a chunk, that chunk is rendered with Apple
  TTS (bake path) or the rest of the paragraph is spoken with Apple TTS (live path). Only if Apple also
  fails is the paragraph skipped, logged as `SKIP pN` in the debug overlay and `skip` in the timing log.
  Failed units go into `failedUnits` so the worker never hot-loops; a live request retries once.
- **Starve watchdog** re-arms (doesn't re-kick) while the worker is rendering the awaited paragraph.

## Timing log + engine probe

- `Library/Application Support/ListenTiming/timing.jsonl` (rotates at 2 MB to `timing.1.jsonl`):
  `app_launch`, `reader_open`, `play`, `kokoro_init_*`, `retired_engine_cleanup`, `coreml_cache_prune`, `synth` (every model call:
  chars, wall_ms, audio_s, depth, phonemes/frames for Kokoro), `chunk_ready`, `paragraph_ready`,
  `paragraph_failed`, `unit_wait` (incl. `worker_busy_other`), `first_audio`, `buffering`,
  `fallback_apple`, `skip`, `engine_probe`.
- Pull: `xcrun devicectl device copy from --device <id> --domain-type appDataContainer
  --domain-identifier com.jimmyyao.Reader --source "Library/Application Support/ListenTiming" --destination /tmp/timing`
- Engine probe (per local engine; init, first-chunk latency, wall vs audio for 60/150/400 chars):
  launch with `-engineProbe` or Listen debug panel → "Run engine probe". Output `Documents/engine_probe.txt`.
- Measured (iPhone 17 Pro, iOS 26.6.2, Release, 2026-09-24):

  | | init (warm) | 60 chars | 137 chars | 399 chars |
  |---|---|---|---|---|
  | Kokoro `gpuAneVocoder` | 6.0-6.5 s (first install: download 17.6 s + compile 15.4 s) | 818-846 ms first call / 231-242 ms warm, 3.70 s audio | 480-490 ms, 8.65 s audio | first audio 435-454 ms, wall 1.37 s, 25.25 s audio |
  | Chatterbox Nano (retired) | (already loaded) | 997 ms, 2.76 s audio | first audio 1.07 s, wall 2.57 s, 7.76 s audio | first audio 2.18 s, wall 6.73 s, 20.6 s audio |

  Kokoro stress: 150 x 137-char calls, no crash, about 470 ms per call at first and about 670 ms at thermal state 2.
- Device installs/timing should use **Release** (FluidAudio: Debug is ~3× slower per decode step).
  The vendored FluidAudio target also compiles with `-O` in Debug (`Vendor/FluidAudio/VENDORED.md`).

## Engine DI + queue priority fix — 2026-09-24

- Engines are plugged in through providers + `EngineRegistry` (see `TTS_ENGINES_SKETCH.md` §
  "Engine dependency injection"). `GlobalSynthQueue` depends only on `SynthQueueContext`
  (cache, active engine key + chunk limits, `SynthChunkRendering`); chunk sizing, bake support,
  cache voice keys, crash guarding and hardware gates come from each engine's `EngineDescriptor`.
- **Priority fix:** `drainPendingIntoQueue` used to call `openArticle` for any persisted pending
  job with `priorityStart > 0` (a BG bake started mid-article), which stole #1 from the article
  being listened to. Now `GlobalSynthQueue.adoptPending(_:focusKey:)`: the focused article (last
  `warmListenAudio` / `prioritizeListen` target) is adopted first and is #1; any other job becomes
  #1 only if the queue is empty; everything else is demoted *with its mid-article plan kept*.
  Covered by `SynthPipelineTests.testPendingMidArticleJobDoesNotStealActiveArticle`.
- Engine probe: `-engineProbe [-probeOnly Kokoro]` (legacy `-kokoroOnly` still works).
  The probe reuses the app's live host when it probes the selected engine: a second loaded
  Kokoro instance made every `albert` prediction fail on device ("Unable to compute the asynchronous
  prediction using ML Program"), seen 2026-09-24 with Kokoro selected.

## Settings → Listen redesign + language auto-detect — 2026-09-24

**Layout** (`Features/Speech/SpeechSettingsView.swift`), all rows are one private `SettingsRow`
(title + optional one-line subtitle, fixed 30×30 accessory slot, fixed 22×22 check/spinner slot,
min height 48) so state changes never reflow rows:

1. **Engine** — Apple + registry local engines. State lives in the subtitle ("Downloading… 42%",
   "Preparing voice…", "Ready · recommended") and the accessory slot (`DownloadRing` = progress
   ring with stop square → cancel). Swipe-to-delete on downloaded engines; crash/failure notices
   in the section footer. No voice picker inside the row.
2. **Voice · <engine>** — voices of the *selected* engine from `EngineDescriptor.voices`.
   Kokoro: curated rows with checkmark + preview button. Apple: "System default" + good-quality
   system voices for the effective language.
3. **Language** — "Automatic (match article)" (default, `reader.languageAutomatic`) + manual list
   (languages that have Enhanced/Premium Apple voices, unchanged from before).
4. **Speed**, 5. **Debug** — unchanged.

UI test `ListenSettingsLayoutUITests` asserts every engine/voice row keeps its frame while a
voice downloads, after switching, while previewing, and after switching back (screenshots →
`/tmp/reader-voiceui/`).

### Kokoro voices — one swap point
`Features/Speech/Engines/FluidAudio/KokoroVoiceCatalog.swift`: `defaultVoice` + `curated`
(af_heart default "Warm · American", af_bella, bf_emma, am_puck, bm_fable). A stored voice that
isn't curated resolves to the default (`EngineDescriptor.resolvedVoice`).

**Voice packs download on select:** `LocalTTSCoordinator.chooseVoice` → `EngineRegistry.prepareVoice`
→ `FluidAudioProvider.prepareVoice` → `KokoroHost.ensureVoicePack` →
FluidAudio `KokoroAneResourceDownloader.ensureVoicePack` (HF `voices/<id>.json` → `<id>.bin`,
522,240 B, in `Application Support/fluidaudio/Models/kokoro-82m-coreml/ANE/`). Only after the
pack is on disk does `setVoice` run (one-voice-per-article replace). Failure keeps the old voice
and shows the error in the Voice footer.

**Previews** are bundled: `Resources/VoicePreviews/voice-preview-kokoro-<id>.m4a` (flattened into
the bundle root; `VoicePreviewPlayer` looks in the subdirectory first, then root). Rendered on the
Mac with the FluidAudio CLI then AAC-encoded:

```sh
fluidaudiocli tts "The lighthouse keeper opened the old logbook, and began to read by lamplight." \
  --backend kokoro-ane --voice <id> --output /tmp/voiceprev/<id>.wav
afconvert -f m4af -d aac -c 1 -b 48000 /tmp/voiceprev/<id>.wav voice-preview-kokoro-<id>.m4a
```
(≈5 s, 24 kHz mono, ≈35 KB each.) Swapping a voice = edit the catalog line + render its clip.

### Language: auto-detect, engine capability, Apple fallback
- **Detection** (`Core/TTS/ListenLanguage.swift`): `NLLanguageRecognizer` over the first 4,000
  chars of the listen blocks; needs ≥24 letters and confidence ≥0.5, else nil. Result is the
  `NLLanguage` raw value ("en", "fr", "zh-Hans").
- **Storage:** `SavedArticle.detectedLanguageCode` (optional SwiftData attribute → lightweight
  migration). Written in `storeListenParagraphs` (save/off-main block build) and backfilled lazily
  (`detectedLanguageBackfilling()`) on open for older rows. Unsaved Reader articles use
  `ListenLanguage.detectCached` (in-memory memo). Passed through `SpeechSession.detectedLanguage`.
- **Capability:** `EngineDescriptor.supportedLanguages` (base codes; empty = any). Kokoro = `["en"]`.
  FluidAudio finding: Reader uses `KokoroAneVariant.english` — Misaki **US** lexicon + BART G2P
  fallback only (no GB lexicon; `bf_`/`bm_` voices change timbre, not pronunciation). FluidAudio
  has separate `.mandarin` (`ANE-zh`) and `.japanese` (`ANE-ja`) variants with their own model
  bundles; not wired up.
- **Resolution:** `ListenLanguageResolution.resolve(automatic:manualCode:detectedCode:selectedEngine:)`
  → effective language (detected, manual, or fallback to the manual/system code) and engine. If the
  selected engine doesn't support it, that article speaks with Apple (`VoiceCatalog.bestVoice`
  for the language) — no settings change — and `note` reads e.g. "Apple · French (Kokoro is
  English-only)", shown next to the paragraph index in the listen bar (`listenLanguageNote`) and
  in the Language footer. `LocalTTSCoordinator.localLanguageGate` keeps such articles out of the
  Kokoro queue/bake; bake marks are hidden for them (Apple). Debug panel shows `Language`.


## Background listening — 2026-09-24

Leaving the app (Home, lock, app switcher) keeps Listen playing. Browse ✕ still stops audio;
Saved ‹ still keeps it playing (unchanged).

### Audio session (`Features/Speech/Playback/ListenAudioSession.swift`)

- `UIBackgroundModes: [audio, processing]` (`project.yml` → `App/BGTasks-Info.plist`).
- Category `.playback`, mode `.spokenAudio`, **no options**. The old `.duckOthers` made the session
  mixable, and a mixable app never becomes the Now Playing app (no lock-screen controls). Other apps'
  audio is now paused rather than ducked while Reader speaks (like a podcast app).
- Only the category is set at launch. The session is **activated when playback starts or resumes**
  (`speak`, `resumeEngines`, a remote play, or an interruption resume) and **deactivated with
  `.notifyOthersOnDeactivation` on stop or finish**, so music can resume. Before this change, just
  launching Reader activated the session.

### Lock screen / Control Center (`NowPlayingController.swift`)

- `MPNowPlayingInfoCenter`:
  - Title: the article title.
  - Subtitle (artist): "site · Paragraph N of M".
  - Album: the site.
  - Chapter number and count, playback progress N/M, favicon artwork.
  - Rate: 0 while paused.
  - Shown only while playing or paused; cleared on stop or finish.
- `MPRemoteCommandCenter`: play, pause, togglePlayPause, nextTrack (next paragraph),
  previousTrack (previous paragraph, or restart paragraph 1), and changePlaybackRate (snapped to
  the listen-bar rates). The skip, seek and position commands are disabled.
- **No second source of truth:** every command goes through
  `SpeechController.handleRemoteCommand` → `RemoteCommand.intent` → `PlaybackSessionState.handle`,
  the same path the on-screen buttons use. Now Playing is re-derived from `playback` on every
  change (`didSet`), and identical updates are skipped.
- Session metadata comes from `SpeechSession.title/site/artwork`: `ArticleReaderScreen` and
  `SpeechSession.saved`.

### Interruptions / route changes

`ListenInterruptionPolicy` is a pure, unit-tested set of rules. Every pause and resume goes
through Session intents.

| Event | Action |
|---|---|
| Call, Siri or alarm starts while playing | Pause. Remember that we were playing. |
| Interruption ends with `.shouldResume`, and we were playing | Re-activate the session and resume. |
| Interruption ends without `.shouldResume` | Stay paused. |
| `appWasSuspended` notice | Not a real interruption. Never auto-resume. |
| User pauses, stops or plays during an interruption | Forget the auto-resume. |
| Route change `oldDeviceUnavailable` (headphones unplugged, BT lost) | Pause. |
| Media services reset | Re-configure the category and pause. |

### Background rendering: never a Core ML call in the background

**Why no "background-safe compute units":** iOS forbids GPU work in the background. Every Kokoro
routing on iOS 26.4–27 still runs BNNS CPU ops, and the libBNNS SIGSEGV (FluidAudio #844/#817) hits
cpuOnly, cpuAndGPU, the default ANE routing, and ANE with a CPU tail. So there's no compute setting
that is safe in the background: ANE-only still has CPU stages, and CPU is the crash path. Switching
compute units would also need a second `KokoroAneManager`, and two loaded managers make predictions
fail on device.

**`AppRunState`** (`Core/TTS/AppRunState.swift`) mirrors `UIApplication` (active / inactive /
background) and is thread-safe:

| State | Rule |
|---|---|
| active | Live chunks and bake-ahead both render. |
| inactive (Control Center, call banner, app switcher, on the way out) | Only chunks a listener is waiting for render. Bake-ahead waits. |
| background | No model call starts. |

It's checked **before each synthesis**, at two layers:

1. `GlobalSynthQueue`:
   - Before every chunk, the worker parks instead of rendering.
   - `ensureChunk` / `ensureUnit` for unrendered audio throw `LocalSynthError.deferredInBackground`
     right away. They still move the priority cursor to the playhead, so foreground bake resumes
     there.
   - A chunk render that fails because of backgrounding is **not** replaced with Apple audio in the
     engine cache. Chunks already rendered stay on disk.
   - On returning to active, the worker is re-kicked.
2. `LocalChunkRenderer.synthesizeResilient` is the last line of defense. It sits right before
   `host.synthesizeOnce` (covering the queue, the probe and the legacy paths) and refuses with
   `deferredInBackground` (`synth_blocked_bg` in the timing log).

**Playback in the background:**
- Baked paragraphs and already-rendered chunks play from the on-disk cache.
- For an unrendered paragraph, the producer gets `deferredInBackground` and uses its existing
  never-skip path, `fallbackToApple`:
  - The rest of that paragraph is rendered with `AVSpeechSynthesizer.write` into a temp CAF (not
    cached) and played in order.
  - It's never silent and never skipped. Kokoro takes over again for later paragraphs once the
    app is back in the foreground.
- `BackgroundGrace` (`beginBackgroundTask`):
  - `ReaderListenGap` is held while the player is starved in the background (e.g. while an Apple
    paragraph renders), so iOS doesn't suspend the app between units.
  - `ReaderSynthDrain` lets a chunk that was in flight at the moment of backgrounding finish and
    write its CAF.
  - Neither permits GPU work.
- Staying ahead:
  - In the foreground the queue always renders the playing article from the playhead downward, so
    the longer the app was open, the more is ready.
  - `app_phase` in the timing log records `ready_ahead` (paragraphs rendered past the playhead) at
    the moment of backgrounding.

**Diagnostics:**
- Listen debug panel, Session section:
  - **Render mode**: "foreground · Kokoro Core ML (gpuAneVocoder)", "inactive · Kokoro for
    playhead only, bake-ahead held", "background · no Core ML — baked audio + Apple fallback", or
    "Apple TTS (AVSpeechSynthesizer)".
  - **Ready ahead**: paragraphs rendered past the playhead.
  - **Background**: what the last background stretch played (baked / chunks / Apple) and how many
    requests were deferred.
  - **Audio session**: active state and activation count.
  - The bake overlay shows the same render and bg lines.
- Listen bar: while the paragraph playing is Apple fallback, the note reads "Apple voice · Kokoro
  can't render in the background".
- Timing log events: `app_phase`, `bg_deferred`, `bg_unit`, `synth_queue_parked`,
  `synth_queue_phase`, `bg_grace_begin/end`, `remote_command`, `audio_interruption`,
  `audio_session`, `bg_task_skipped`.

**Tests** (`Tests/BackgroundListeningTests.swift`, 9):
- Remote command → intent mapping, and Session transitions.
- The `SpeechController` path: Now Playing info, audio-session activation and deactivation, next and
  previous paragraph, rate snapping, stop clearing.
- The interruption policy, notification parsing, and interruption and unplug pause/resume through
  the Session.
- With the fake engine:
  - The renderer refuses in the background.
  - The background defers live chunks and holds bake-ahead, and bake resumes in the foreground
    with each chunk rendered once.
  - Going to background mid-bake parks after the in-flight chunk: no Core ML calls while
    backgrounded, rendered chunks stay playable, and no Apple audio is written into the cache.
  - Inactive serves only the listener.

### Crash 2026-09-24 22:00 (Browse → Save → Reader while a saved article played)

- The crash: Kokoro libBNNS SIGSEGV again (the same PCs as the 17:25 and 17:33 crashes; #844),
  inside `BNNSGraphContextExecute_v2` on an E5RT thread. There were no Reader frames and no
  concurrent render.
- What made it likelier in this flow:
  - `prepareListenIdentity` ran on reader open for the just-saved article. That article isn't the
    live session, so the `isLivePlayback` guard didn't skip it.
  - It deleted the chunk scratch of the paragraph the queue was baking for that same article.
  - Chunks already rendered were then synthesized again: `p2 c0` twice, 2.5 s apart, and the crash
    came on the next call.
- The fix: while the article has a queue job, keep the chunk dirs whose `p-NNNN-<texthash>` still
  matches the current paragraphs (`ArticleAudioCache.removeChunkScratch(for:keepingCurrent:)`).
- Test: `BrowseSaveWhilePlayingTests`. It failed before the fix (15 model calls for 14 chunks) and
  passes after.
- This removes the extra Core ML exposure but not Apple's bug. The crash guard still switches to
  Apple on the next launch.

## CPU route benchmark (debug-only) — 2026-09-24

Candidate background renderer: Kokoro-82M through **ONNX Runtime on the CPU execution provider**
(no Core ML, no GPU, no ANE), fed by FluidAudio's own phonemizer, `vocab.json` and `af_heart`
pack. Nothing in normal playback routing uses it yet; it lives only in the Listen debug panel
(Settings → Listen → Listen debug → Open full panel → **CPU route benchmark**).

- **Package / model.** `microsoft/onnxruntime-swift-package-manager` 1.24.2 (product
  `onnxruntime`, module `OnnxRuntimeBindings`; only `Features/Speech/Engines/ONNX/KokoroONNXSession.swift`
  imports it). Model `onnx-community/Kokoro-82M-v1.0-ONNX/onnx/model_fp16.onnx` (163,234,740 B,
  SHA-256 verified) is downloaded on demand into `Application Support/CPURoute/kokoro-82m-v1.0-onnx/`
  (excluded from backup; delete button). Never bundled.
- **Inputs** (`Core/TTS/CPURoute/KokoroCPUInputs.swift`, unit-tested): `input_ids` = `[0, ids…, 0]`,
  `style` = `pack[len(phonemes) - 1]` (clamped 0…509; full 256 floats = ONNX `ref_s`), `speed` = 1.
  Frontend via `KokoroCPURouteFrontend`, implemented by `KokoroHost` (the live host is reused).
  Phonemization may load Kokoro's Core ML models + BART G2P → foreground only, holds
  `SynthRenderGate`, result cached in `Application Support/CPURoute/phonemes-cache.json`.
- **Benchmark.** Fixed passage (501 phonemes) + its first three sentences (190). Configs:
  1/2/3/4 threads @ `.userInitiated`, 3 @ `.utility`, 3 @ `.userInitiated` with ORT spinning off.
  Per config: fresh session (load ms), cold 190, warm 190, warm 501 → ×real-time, RTF, CPU-s per
  audio-s (getrusage), thermal, `phys_footprint` (sampled every 100 ms), `os_proc_available_memory`,
  device, OS. Pauses the bake queue (`isPausedForProbe`, waits for the worker and any engine
  prepare) and holds `SynthRenderGate` → never overlaps a Kokoro Core ML call.
- **Soak (lock-screen test).** Toggle "Soak: render continuously for N minutes" (default 15):
  3 threads @ `.userInitiated`, alternating 501/190 inputs, per chunk logs ×real-time, rolling-5
  and cumulative, app state, thermal, memory, battery, gate wait and gaps. Normal Listen playback,
  or else a silent loop on Listen's session config (`.playback`/`.spokenAudio`), keeps the app
  alive. The soak never phonemizes and never touches Core ML (inputs precomputed in the
  foreground); the existing `AppRunState` / `LocalChunkRenderer` background guard is unchanged.
- **Output.** `Application Support/ListenTiming/cpubench.jsonl` (`cpubench_start/run/end/error`,
  `cpubench_soak_start/chunk/end`, `cpubench_sample`) and
  `ListenTiming/cpubench-sample-501tok-onnx-gain0.69.wav` (3-thread render ×0.69 ≈ −3 dB to match
  Core ML loudness). Pull with the timing-log devicectl command (same folder).
- **Launch probe.** `BGTaskScheduler.supportedResources.contains(.gpu)` → `probe_bg_gpu` in
  timing.jsonl + the debug log + the section's "Background GPU" row.

## Kokoro ONNX-main + auto-recover — 2026-09-25
- The ONNX CPU route **renders in the background** (`LocalSynthHost.rendersInBackground`): the
  renderer allows model calls when backgrounded; `GlobalSynthQueue` keeps serving live waiters and
  bakes ahead **only the playing article** (`backgroundRenderCacheKey`), holding other articles until
  foreground. The debug Core ML route keeps the old rule (no model call in background → Apple).
- First chunk is short (`TextChunker.Limits.kokoroCPU`: first ≤ 80, a whole first sentence ≤ 104)
  so first audio arrives after one small call; then a head-start ramp up to 240/280 (see
  "Run-on paragraphs" below).
- Head-start rule (`HeadStart`, `RenderPace`): before rendering a chunk the engine projects whether
  rendering at the measured speed would starve playback by > 2 s; if so that paragraph plays with
  Apple ("Kokoro fell behind", `render_behind` log).
- Crash auto-recover: the in-flight marker now carries route/article/paragraph/phase. On launch the
  coordinator keeps Kokoro (ONNX) and reopens the article at the paragraph (auto-play if the crash was
  < 20 min ago and something was playing; `listen_resume.json` records the playing paragraph). Banner:
  "Kokoro stopped unexpectedly; resumed on the stable route."
- Crash attribution on the Core ML route: `coreml_breadcrumb.json` names the model + stage
  (`g2p.bart/decoder`, `kokoro/vocoder`, …) that was about to run; logged as `coreml_stage` in
  `engine_crash_detected`.

## Run-on paragraphs "breaking up" — 2026-09-25
Report: The Forgotten (royalroad 178276, "Prologue / Chapter One: Gunner") "sounds like it's
breaking up". Evidence (ListenTiming + the phone's TTSCache for that article, 55 paragraphs):
- **Not** render underruns, Apple fallback or voice swaps: rendering ran 2.4–3.1× real time, no
  `render_behind`, `bg_summary` Apple 0.
- **Main cause: NaN audio.** 14 of the chunks (113.7 s of 701 s = 16 %) were entirely NaN; p6 had 5 of
  19. `LocalPCMWriter` clamped NaN with `min(1, NaN)` = 1, so each became a full-scale DC block: a
  pop, 5–15 s of silence, a pop. Root cause in the onnx-community `model_fp16.onnx`: the generator's
  harmonic-source phase is `atan2` exported as `Atan(Div(imag, real))`; an exact fp16 0/0 = NaN,
  which spreads through `noise_convs` → AdaIN → the whole chunk. Whether an exact 0/0 happens depends
  on rounding (threads, graph optimisation, ORT version, CPU), so it looked random.
  Fix: `KokoroONNXModelPatch` rewrites the model once after download (`model_fp16_atan2nanfix.onnx`,
  ≈1 s): `Where(IsNaN(x), 0, x)` in front of the Atan (atan(0)=0, the same angle the quadrant fix
  picks). Audio is bit-identical wherever the original was finite (Swift + Python cross-checks).
  Defence in depth: `KokoroCPUHost` retries a non-finite output once (speed 1.02) then falls back to
  Apple for that chunk (`onnx_nonfinite`); `LocalPCMWriter` writes non-finite samples as 0.
- **Dead air at joins.** Kokoro pads each call with ≈0.3 s + ≈0.5 s of silence, so every chunk join
  was ≈0.8 s — even at a mid-sentence comma. `ChunkEdgeTrim` (hosts with `trimsEdgeSilence`, i.e.
  the ONNX route) keeps 40 ms before speech and a trailing pause by boundary: sentence 360 ms,
  clause 180, word 40, paragraph end 520 → joins ≈0.40 s at sentences, ≈0.22 s at commas (Kokoro's
  own in-chunk pauses are ≈0.35–0.6 s / 0.2–0.4 s).
- **Cut points.** The old chunker cut "pound on the | door", "Smallpox, | announcing that…",
  "business admin, | etc-. The next Castra…". `TextChunker.chunks` is now hierarchical:
  sentences are packed whole; a sentence ≤ hardMax is never split except to make the short first
  chunk / head-start ramp; over-long sentences are split by `balancedSplit` (DP over cut points:
  sentence-like `etc. The` > `; : —` > `,` > before a conjunction > space, pieces kept balanced).
  First chunk: the whole first sentence if ≤ 104, else its head at the strongest boundary ≤ 80.
  Ramp: chunk k ≤ 2·u₀ + u₁ + … + u_{k−1} (rendering ≥ 2× real time; a whole sentence may overshoot
  25 %), second chunk ≤ 160, then 240 target / 280 hardMax (`KokoroCPUHost.maxTokensPerCall` 360).
  `normalize` drops a dash glued to punctuation ("etc-." → "etc."). Whole chapter: 164 → 160 chunks,
  mid-paragraph non-sentence cuts 9 → 4 (all at commas), word cuts 2 → 0.
- **Cache purge.** Saved Kokoro audio from before this fix is deleted once at launch
  (`reader.tts.kokoro.audioCacheVersion` = 2, `kokoro_audio_cache_purge` log).
- Tests: `HierarchicalChunkerTests` (real p6/p7/p15 text), `ChunkEdgeTrimTests`,
  `LocalPCMWriterNaNTests`, `KokoroNaNProbeTests` (patch + a p6 render: 15 chunks, all finite,
  joins 0.40 s / 0.22 s).
- `mem_mb` (phys_footprint) is logged per ONNX call to watch memory with the longer chunks (Mac:
  ORT activations ≈ +380 MB at 300 tokens).
- Giant paragraphs: implemented — see "Long paragraphs split at sentences" below.
- On-device check without playing: `xcrun devicectl device process launch --device <id>
  --terminate-existing com.jimmyyao.Reader -- -bakeArticle <saved id prefix>` bakes that saved
  article top-down (foreground), then pull ListenTiming + TTSCache. Verified 2026-09-25 01:28–01:36
  on The Forgotten: 55 paragraphs, 162 chunks, all Kokoro, 0 NaN retries, 0 saturated audio (was
  16 %), 107 joins at 0.40 s (sentence) / 0.22 s (comma) (was ≈0.8 s), chunk plan identical to the
  unit-tested plan, ONNX ≈2.6× real time (min 2.2× when warm), app memory peak ≈1.04 GB.

## Long paragraphs split at sentences (listen layout v3) — 2026-09-25
Giant paragraphs (2.5k chars ≈ 2.8 min of audio) made tap-to-seek, resume, highlight and the
paragraph picker coarse. Paragraphs over **1,200 chars** are now split at sentence ends into
balanced pieces for display, navigation and audio alike.
- **One rule, one place.** `ParagraphSplitter` (`Core/Domain`): sentence starts come from
  `TextChunker.isBoundary` (the same abbreviation/decimal-aware rule the chunker uses). A paragraph
  of length L > 1200 is cut into k = ⌈L/900⌉ pieces (≥ 2) by a DP that minimises squared deviation
  from L/k with every piece ≥ 300 chars; if no such cut exists it tries fewer pieces, else the
  paragraph stays whole. Never splits a paragraph ≤ 1200; a single giant sentence stays whole
  (the chunker still splits it for synthesis). Deterministic: same text → same pieces.
- **Split the HTML, not a side list.** `ListenHTMLBlocks.splitLongBlocks` (layout `version` 3)
  rewrites leaf `<p>`, `<blockquote>`, `<dd>` blocks: at each piece start it inserts
  `</inline…></p><p attrs-without-id><inline…>` so open inline tags (em/strong/a) are closed and
  re-opened. `li`, `td`, headings and `pre` are never split. Both the reading HTML
  (`ParagraphDocument.readingHTML`, used by `ReaderArticle.displayHTML` and `HTMLReadingView`'s
  page-title path) and the listen paragraphs (`ParagraphDocument.forListening`) derive from the same
  split HTML, so web-view leaf-block index = listen / queue / cache paragraph index. Plain-text
  documents split the same way (`ParagraphDocument(plainText:)`). Browse → Reader uses the same
  path. Pieces are ordinary paragraphs with normal paragraph spacing; each piece gets its own
  highlight, tap target and a paragraph pause (~0.52 s) at its end.
- **One-time migration** (`ArticleLibrary.migrateParagraphLayout`, launch, before `migrate`/bake):
  for each saved article with `listenBlocksVersion < 3` it rebuilds the blocks, maps the saved
  position by non-whitespace character offset (`ParagraphPositionMap`; a stale offset falls back to
  the piece start), remaps `ListenResumePointStore` and any pending bake job, then fixes the audio
  cache: unchanged paragraphs keep / move their CAFs by text hash; for a split paragraph the old CAF
  is **sliced sample-exact** (`ArticleAudioCache.remapSplitParagraphs`, by `chunkDurations`) into
  each piece whose chunk plan equals a contiguous run of the old chunks; misaligned pieces are
  dropped (only those paragraphs re-bake). Logged as `paragraph_layout_migration` (old/new counts,
  split, pos_old/pos_new, audio kept/moved/sliced/misaligned/dropped). The same remap also runs in
  `LocalTTSCoordinator.prepareListenIdentity` (unsaved Reader keys), log `split=` / `sliced=`.
- The Forgotten chapter: 3 paragraphs split — 2,543 → 813/872/856, 1,397 → 722/674,
  1,560 → 803/756; 1,121 and 1,131 stay whole; 55 → 59 paragraphs.
- Tests: `ParagraphSplitTests` (real chapter HTML: counts, sizes, determinism, inline tag
  balance, idempotence, index parity reading ↔ listen) and `ParagraphLayoutMigrationTests`
  (position + resume-point mapping, shifted audio moved, aligned pieces sliced sample-exact,
  misaligned dropped, second run is a no-op).

## First chunk never cut between bare words — 2026-09-25
After the split, two pieces of The Forgotten p6 started with a head cut mid-phrase ("…to buy toilet
paper | and canned food", "…departments such as | healthcare") and got the 40 ms word pause
(first join ≈0.08 s). The first (fast-start) chunk now (`TextChunker.chunks`, k = 0):
1. the whole first sentence if ≤ firstTarget + 24 (104 on the ONNX route);
2. else its head at the best clause boundary inside firstTarget (80): `; : —` > comma > before
   a conjunction (and/but/which/when…); head ≥ a third of the budget (a 5-char "Well," can't
   carry the fast start); back half of the budget preferred;
3. else a slightly bigger first chunk up to **firstTarget + `firstStretch` (40) = 120 units**: the
   whole sentence, or the nearest clause boundary past 80. Justification (phone ONNX timing,
   231 chunks): render ≈ 0.35 s + 23 ms/char median, 28 ms/char worst → 80 units ≈ 2.2 s
   (worst 2.8 s) to first audio, 120 ≈ 3.1 s (worst 3.7–4.1 s);
4. only for a clause-free run longer than 120 units: a space cut inside 80 (last resort).
- A tiny first sentence ("Yes.") followed by a much longer one used to play out before the second
  chunk was rendered (a stall right after first audio, e.g. [5, 75] or [25, 88] units). The next
  sentence (or its head at a clause) now joins the first chunk while it stays ≤ 120
  (`growShortFirst`), so the head-start ramp holds for every chapter paragraph.
- Join pause: a cut before a conjunction is a clause join (`ChunkEdgeTrim.boundary(after:nextWord:)`,
  the queue passes the next chunk's first word) → 180 ms trail + 40 ms lead ≈ 0.22 s, like a comma.
- Chunk plans changed only where these rules apply (on the phone's Forgotten cache: the 5 missing
  pieces plus 5 already-baked paragraphs whose stitched audio stays valid and plays whole).
- Crash resume vs. layout migration: the crash-resume target is read at coordinator init, before
  the saved rows migrate. The migration now also remaps the in-memory target
  (`LocalTTSCoordinator.remapPendingResume`), and `SavedListView` runs the (idempotent) migration
  before taking the target, whichever view appears first.
- Tests: `FirstChunkBoundaryTests` (the two real pieces, every join in the chapter ≠ word and
  ≥ 0.15 s, ramp for all pieces, stretch / tiny-head / clause-free fallback, conjunction pause);
  `ParagraphLayoutMigrationTests` checks the in-memory crash target is remapped.
