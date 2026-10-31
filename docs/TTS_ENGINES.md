# TTS engines

Meridian Reader speaks with an on-device neural voice: **Phonon** 31m English (the default, Zoey)
or **Kokoro** (the second default, Heart; Heart's pack ships in the app). Both read English only.
Playback never changes the voice on its own: an article plays in its own voice or pauses and says
why (`LISTEN_PLAYBACK.md` → "One voice, never swapped"). Voice libraries plug in behind one registry, so the listen core never
imports a library or switches on engine types. How playback, rendering and the audio cache use an
engine is in `LISTEN_PLAYBACK.md`.

## Shape

`SpeechController` owns the session (`PlaybackSessionState`: document, position, phase) and the
rate, and binds one `LocalListenEngine` per play, in the article's voice. Audio is rendered by a
**synth host** owned by `LocalSynthService`; the listen player only plays rendered files.

```
Listen UI  →  SpeechController  →  LocalListenEngine (bound per play, one voice)
                                     └─ LocalListenPlayer: file player + producer
                                          └─ ListenUnitSource (per play): audio cache + GlobalSynthQueue
                                               → LocalSynthService → LocalChunkRenderer
                                                  → LocalSynthHost (KokoroCPUHost / PhononHost)
```

The engine reports events (`PlaybackEngineEvent`: audible, paused, position, finished, stalled);
the session decides. Only the render queue's worker loads an engine, for the work it takes
(`LISTEN_PLAYBACK.md` → "Render queue", "Loads"). What binds, and what happens while the voice's
engine loads or stops, is in `LISTEN_PLAYBACK.md` → "Engine binding".

## Kokoro

Kokoro-82M, English only (`supportedLanguages = ["en"]`), A15 or newer and iOS 17+ (the Simulator
is allowed). `FluidAudioProvider` declares it (`local.kokoro`) and builds its host.

### Route

Kokoro renders on one route, ONNX Runtime on the CPU (`KokoroCPUHost`; its knobs are
`KokoroRouteSettings`). Its phonemes, voice packs and cache key (`kokoro.<voice>`) are those of
FluidAudio's Core ML Kokoro, so audio rendered on it stays valid.

| Route | Host | Notes |
|---|---|---|
| **ONNX CPU** | `KokoroCPUHost` | ONNX Runtime on the CPU execution provider, onnx-community `model_fp16.onnx` (≈163 MB, downloaded into `Application Support/CPURoute/kokoro-82m-v1.0-onnx/`, SHA-256 checked, excluded from backup), every core but one in front (3 to 6: 5 on an iPhone 17 Pro, so the work an efficiency core holds is a smaller piece; `reader.tts.kokoro.cpuThreads` overrides it in the debug panel) and 1 in the background, as the render policy passes per call, never more than that setting (the session is rebuilt at the first call at a new count, `KokoroONNXSessionSlot`). Route `kokoro.onnx`, `ThreadControl.honored`. Each run shrinks ORT's CPU arena when it ends (`memory.enable_memory_arena_shrinkage`), so the footprint between calls stays near where it started; a memory warning lets go of the session, which the next call builds again (≈0.5 s; `kokoro_cpu_session_released`, `kokoro_cpu_session_rebuilt`). Frontend `KokoroAneCPUFrontend` (vendored FluidAudio patch: Misaki lexicon + a pure-Swift BART G2P that reads the Core ML G2P weights as data; heteronyms such as read, live, close, record pick Misaki's part-of-speech pronunciation per sentence from Apple's `NLTagger`, with auxiliary rules for past `read`, from the bundled `Resources/KokoroHeteronyms.json`, C132; an OOV `-s`/`-ed`/`-ing` word is built from its known stem by Misaki's suffix rules, a heteronym's VERB reading as the stem, so `lived` is lˈɪvd, and `c.`/`ca.` before a number reads "circa", C137), so no Core ML runs on this route. Renders in the background, chunk after chunk while audio plays (LISTEN_PLAYBACK.md → "Rendering in the background"). |

Measured with `-KokoroStress` (320 fixed calls, app in front, iPhone 17 Pro, iOS 26.6.2, Release
build with the Debug hooks, 2026-10-11):

| Route | Calls | Crashes | ms per audio second (× real time) | First audio, models compiled |
|---|---|---|---|---|
| ONNX CPU, 5 threads | 320 / 320 | 0 | 300, p90 325 (3.3×) | 1.25 s (load 0.8 s + call 0.47 s) |
| Core ML, `aneTailGpu` | 20, stopped at 5 crashes | 5 | 62 (16×) | 1.1–1.4 s |
| Core ML, `gpuAneVocoder` | 20, stopped at 5 crashes | 5 | 95 (10.5×) | 1.8–2.0 s |

The Core ML rows are FluidAudio's 7-stage Core ML chain, which the app doesn't run because of
these crashes. Every Core ML crash is the same: `SIGSEGV` in `libBNNS` (`BNNSGraphContextExecute_v2`, from
`E5RT::Ops::BnnsCpuInferenceOperation` on `com.apple.e5rt.concurrentExecutionQueue`) during the
`tail` stage, though that stage is placed on `.cpuAndGPU`: E5RT still runs part of it on the
CPU. Calls 1, 2 and 19 crashed on both routings, two of them as a fresh process's first call, so
some inputs crash it whatever came before. The ONNX run's footprint grew from about 480 MB to
1.9 GB over the 320 calls: ORT's CPU arena kept every block it grew for the longest inputs. Each
run now shrinks the arena when it ends (`KokoroONNXSession`). Measured on the Simulator (Debug
build, the Mac's CPU, 6 threads, 2026-10-15), the same 320 calls end at 1,351 MB without the
shrink and stay between 466 and 482 MB with it (footprint between calls), at 264 against 259 ms
per audio second (about 2 % slower, the arena's blocks allocated again each run). The phone needs
the same run again (Release).

Only the ONNX route needs the model patch: the fp16 model can output an all-NaN chunk (an exact
fp16 0/0 inside the generator's `atan2`, exported as `Atan(Div(imag, real))`).
`KokoroONNXModelPatch` puts `Where(IsNaN(x), 0, x)` in front of every `Atan` once after download
(`KokoroONNXModelStore.ensurePatchedModel`); audio is bit-identical wherever the original was
finite. As defence in depth `KokoroCPUHost` retries a non-finite output once, then fails the
chunk (playback pauses there with Retry), and `LocalPCMWriter` writes non-finite samples as 0.

### Assets and voices

- Shared assets (`KokoroAssets`, `Application Support/fluidaudio/Models/kokoro-82m-coreml/ANE/`):
  vocab, BART G2P, the US lexicon and voice packs (`<voice>.bin`, 0.5 MB each). The shared ONNX model download shows progress under the voice
  list (tap to cancel). Each downloaded voice pack is removed with a swipe *Remove Download* on
  that voice row; Heart cannot be removed while it is the only curated pack on disk.
- Voices (`KokoroVoiceCatalog`): `af_heart` (Heart, default), `af_bella`, `bf_emma`, `am_puck`,
  `bm_fable`. Heart's pack ships in the app (`Resources/Kokoro/af_heart.bin`) and is copied into
  the cache on first launch (`KokoroHeartPackInstall`), so the Voice picker never starts empty.
  A stored voice that isn't curated resolves to the default. Other packs prepare (~0.5 MB) when
  the voice is chosen (`LocalTTSCoordinator.downloadVoice` → `EngineRegistry.prepareVoice`);
  only then does the voice switch. A failed prepare keeps the old voice and shows the error.
- Previews are bundled (`Resources/VoicePreviews/voice-preview-kokoro-<id>.m4a`, ≈5 s, 24 kHz
  mono AAC), rendered on the Mac:

  ```sh
  fluidaudiocli tts "The lighthouse keeper opened the old logbook, and began to read by lamplight." \
    --backend kokoro-ane --voice <id> --output /tmp/voiceprev/<id>.wav
  afconvert -f m4af -d aac -c 1 -b 48000 /tmp/voiceprev/<id>.wav voice-preview-kokoro-<id>.m4a
  ```

  Swapping a voice = edit its catalog line and render its clip.

### Crashes

The libBNNS crash kills the process; nothing catches it. `EngineCrashGuard` writes an in-flight
marker (`ListenTiming/engine_inflight/<call id>.json`, one per call) around every call of an engine whose descriptor sets
`OnDeviceTraits.isCrashGuarded` (Phonon, Kokoro), with the route, article, paragraph, app phase and
memory footprint (`phys_footprint`), and removes it when the call returns, so it exists only
while a call is in flight. Termination (`willTerminateNotification`, e.g. a swipe-kill while the
app runs, playing or rendering) removes them and lets no call write another. A marker an older
build left (`ListenTiming/engine_inflight.json`) is read the same way.

A marker found at launch counts as a crash only when the engine killed the process
(`MarkerVerdict`); otherwise it is logged (`engine_marker_dismissed`) and the launch is a normal
one: no notice, no crash count, nothing reopened:

- **stale:** the resume point (written per paragraph while listening) is more than 60 s newer
  than the marker: the process played on long past the call's start, so the call didn't end it;
- **memory kill:** the call started in the background with a footprint of 1,000 MB or more: iOS
  reclaiming memory (jetsam), not the engine;
- **engine crash:** anything else.

When more than one marker reads as an engine crash (more than one call was in flight), it is one
crash, ambiguous (`CrashInfo.isAmbiguous`): it can't say which call did it, so the provider's
recovery doesn't run and the article pauses for Retry in the same voice.

A crash never changes the engine or the voice. The provider decides how it resumes
(`SpeechEngineProvider.recover(from:playing:)`, a `CrashRecovery`). An engine without a hook
(Phonon) pauses for Retry: the article reopens in Listen, paused at that paragraph, and the toast
says "Phonon stopped." with *Retry*; Retry, or any press of play, loads the engine afresh in the
same voice and plays on. Kokoro answers with `KokoroCrashRecovery`:

- a marker from an older build's Core ML route (route `coreml`, or none) → the ONNX route, and the
  article reopens at that paragraph; it doesn't count toward the pause;
- an ONNX crash → ONNX again on one thread fewer and the same resume; a second ONNX crash without
  40 healthy calls in between pauses for Retry, as above ("Kokoro stopped.");
- a resume that doesn't pause auto-plays when the crash was under 20 minutes ago and something was
  playing (`ListenResumeTarget.forCrash`);
- the paragraph is applied only on an article that still holds the text it was played in; otherwise
  the article opens paused at its own spot (`AppLaunch.resumeAfterCrash`, `LISTEN_PLAYBACK.md`).

A process that dies while suspended
mid-call (no notice, no time to clear) can't be told from a crash, but the render queue holds a
background task around every call in the background (`ReaderSynthDrain`), so the call ends first.

### Launch steps

`FluidAudioProvider.launchMigrations`, run by `AppComposition.prepareAudioCache` before
anything plays (after the library's unfinished audio work): `KokoroAudioCachePurge` (drops Kokoro
audio rendered before the NaN patch and the boundary-trimmed joins;
`reader.tts.kokoro.audioCacheVersion`; audio held for library work that couldn't finish is left
for a later launch's purge), `KokoroCoreMLStageCleanup` (at every launch: removes the stored
`reader.tts.kokoro.fastGPURoute` an older build's Core ML route setting left, and deletes the Core
ML stages it downloaded, off the main thread, whenever they are found), and in Debug builds
`CPURouteProbes` (whether background tasks can get GPU time, `probe_bg_gpu`).

The route settings (`KokoroRouteSettings`) belong to `FluidAudioProvider`. Its Listen debug panel
section (`KokoroRouteDebugSection`, from the provider's `debugSections`) changes them through it
(`setCPUThreads`), then asks the coordinator to rebuild the live host
(`LocalTTSCoordinator.reloadEngine`, which knows no engine): the render queue's worker drops it
after the call in flight, and its next Kokoro work loads one built the new way.


## Phonon

On-device English TTS via Gradium [`ptts`](https://github.com/gradium-ai/xn-ptts) 0.6.0
(Phonon 31m on Core ML's CPU path, Apache 2.0). **The default on-device engine** (Zoey, picked on a fresh
install when the engine is supported); Kokoro Heart is the second default. iOS 18+.

| | |
|---|---|
| Engine id | `local.phonon` |
| Host | `PhononHost`, on its route's compute unit: Core ML's CPU path (route `phonon.cpu`, routing label `phonon-31m cpu`) or the Neural Engine (route `phonon.ane`, lane `.neuralEngine`, label `phonon-31m ane`); the crash marker's route tag is `cpu` or `ane`. The app's policy uses the CPU route alone; the Neural Engine route is used only by the two-lane policy, a Debug launch's `-renderPolicy lanes` (LISTEN_PLAYBACK.md → "The render policy"). On an iPhone 17 Pro (Release) the CPU path renders about 22× real time in front at about 1.7 cores and 13.4× in the background; the Neural Engine about 21× at about 1.1 cores; both at once about 19× together at about 2.7 cores and 430 MiB (p433). Both routes share one cache revision: their audio sounds the same (the owner's listening check), so the cache key doesn't name the compute unit. |
| Models | Built into the app (`Resources/PhononBundle`, ~170 MB, every voice), put there at build time by `tools/fetch-phonon-bundle.sh` from the release [`phonon-31m-en-200-v0.6.0`](https://github.com/haowjy/xn-ptts/releases/tag/phonon-31m-en-200-v0.6.0) on the owner's fork, haowjy/xn-ptts. Nothing downloads at run time. Core ML compiles a model beside its package, so the first load of a process copies the bundle to `PhononTTS/models` unless that copy already holds the same export (`bundle.json`'s `built`); the copy is staged and swapped in whole, before any Phonon model loads. Builds that downloaded the model left the zip and an unzipped `bundle/`; a launch step removes them (`PhononDownloadLeftovers`). |
| Voices | The full English set in the bundle (`PhononVoiceCatalog`): eight curated at the top of the picker (Zoey default), the rest under *More voices*. Every one is always installed. |
| Prefill | 200 tokens. ptts groups a paragraph's sentences up to the bundle's prefill and cuts a longer sentence at the word nearest its middle, ending each piece with a full stop; the model speaks each piece as its own sentence, so a cut sounds like a false sentence end. Upstream's release bundle is exported at 48 tokens (about 150 characters of prose), which cut ordinary long sentences; at 200 (ptts's own fit limit, past which the model stops early and skips words) a sentence goes through whole. The larger cache (ctx 1200 against 414) makes every step costlier: on a Mac's Neural Engine it still renders about 15× real time and takes about 30 MB more; on the Simulator, which has no Neural Engine, it renders about 2.5× slower than the 48-token bundle. |
| Bundle export | At ptts v0.6.0: `cargo build -j 2 --release -p ptts --example export_coreml --features hub`, then `export_coreml --max-tokens 200 phonon-31m-en-coreml` (its default checkpoint, `hf://gradium/phonon-31m-en@8c64b55ec301728e2d1695bfea87a08a267d0c2d`). The checkpoint carries only its `default` voice, so the other 37 voice files are copied unchanged from upstream's v0.4.0 bundle and added to `bundle.json`'s `files` and `voices`; `source.json` records the sources. Zipped with the root folder `phonon-31m-en-coreml`. The release notes give the details and hashes. |
| Cache revision | Cache voice keys carry the bundle's `built` stamp (`phonon@1793455047.Zoey`, `OnDeviceTraits.cacheRevision`), so audio a different bundle rendered never plays or counts as prepared, and renders again. Keys without a revision (`phonon.Zoey`) were rendered by upstream's 0.4.0 bundle and were renamed once at launch to its stamp, `phonon@1792483937` (`PhononCacheRevision`). |
| Chunking | `TextChunker.Limits.phonon`: target 1200, `hardMax` 1600, whole-paragraph calls (no short first clip). |
| Background | Route `phonon.cpu`, `ThreadControl.uncapped`: the CPU path renders in the background as in front, chunk after chunk while audio plays (LISTEN_PLAYBACK.md → "Rendering in the background"). The Neural Engine lane runs only with the app in front (`Lane.runsInBackground`). |
| Launch steps | `PhononDownloadLeftovers`, `PhononCacheRevision`, then `CoreMLCompileCacheJanitor` (Core ML's compiled-model cache, once per install, in the background; `LISTEN_PLAYBACK.md` → "Audio cache"). |
| Probe | `-engineProbe -probeOnly Phonon,Kokoro` (the short names; the log line `compute units=` shows the routing label). |

Phonon's own English `normalize_text` runs inside every `Phonon.synthesize` (the host loads with
`language: .english`): it owns numbers, symbols, currency, ellipsis and pauses.

Files: `Features/Speech/Engines/Phonon/` (`PhononProvider`, `PhononHost`, `PhononModelStore`,
`PhononSpokenText`, `PhononVoiceCatalog`). Registered from `AppComposition.makeProviders()`.

### Large model downloads

`LargeModelDownloadConsent` guards Kokoro's ONNX model (~163 MB).
On Wi-Fi (or Ethernet) with Low Data Mode off a download starts without a prompt. On cellular or
with Low Data Mode on, an alert from `RootView` asks "Download on Cellular?" ("<engine> needs about
<size>. You're not on Wi-Fi.") with *Download* or *Wait for Wi-Fi* (which cancels the download
for now). Offline never prompts, so the download's own error shows.

## Text prep for speech

Three steps, in this order; engines own normalization, the shared code only hands over clean text
in chunks the engine can take:

1. **Normalize** (`TTSTextNormalize`, shared): collapses whitespace only (NBSP and runs of
   whitespace to one space, trimmed). Dashes, semicolons and the rest pass through. Listen path
   only; the Reader's HTML is unchanged.
2. **Chunk** (`TextChunker`, per-engine `Limits` from the provider): sentences packed up to the
   engine's `target`, a sentence over `hardMax` cut at clauses, then balanced pieces. Chunks
   reassemble to the normalized paragraph. Limits: Phonon `target` 1200 / `hardMax` 1600
   (`TextChunker.Limits.phonon`); Kokoro `target` and `hardMax` 280 (`.kokoroCPU`, bounded by
   Kokoro's per-call memory growth). They are measured values owned by the provider.
3. **Engine-side prep**, at render time (`LocalSynthHost.spokenText(forChunk:)`), inside the
   engine's directory: Phonon runs `PhononSpokenText` (softens shouty ALL CAPS, keeps `?` / `!`
   intonation) before Gradium's normalizer; Kokoro closes a mid-sentence chunk that ends on a bare
   word with a comma (`KokoroSpokenText`) and picks heteronym pronunciations in its vendored
   frontend (`Resources/KokoroHeteronyms.json`, above). Prep may change letter case or drop
   redundant punctuation, never words, so planned chunks still map to the normalized paragraph
   (sub-paragraph positions, the audio cache).

There is no shared "speakable text" rewriter (it was removed) and no app-side grammar or pause
pass for Kokoro; changing how something is pronounced means changing the engine's directory or
its data file.

## Engine registry

```
AppComposition (composition root: the only file that lists libraries)
  └─ EngineRegistry(providers: [FluidAudioProvider, PhononProvider])
       └─ injected → LocalTTSCoordinator(engines:defaults:…) → LocalSynthService(engines:)
            └─ SpeechController(localTTS:defaults:) over the coordinator

SpeechEngineProvider (one per library)      EngineDescriptor (per engine)
  descriptors / retiredEngines                 id, names, subtitle, recommended, sort order
  makeHost(for: route, voice:) → LocalSynthHost  voices + default, voice defaults key
  isInstalled                                  hardware gate, languages
  recover(from:playing:)                       onDevice: OnDeviceTraits
  launchMigrations / debugSections(speech:)      cache voice prefix and revision, chunk limits, crash guard
LocalSynthHost (thin: load + ONE call)
  → LocalChunkRenderer (shared: normalize, gate, crash guard, re-split on inputTooLong, log, CAF)
```

Every engine is on-device (`OnDeviceTraits`): it renders ahead into the audio cache through the
render queue. The registry needs at least one; its `defaultEngine` is the recommended one that
runs here, else the first. The shared core has no `import FluidAudio` and no switch on engine types: `GlobalSynthQueue`
(`SynthQueueContext` and its `RenderTarget`, the `RenderPolicy` and its routes), `ArticleAudioCache` keys, `TextChunker`,
`LocalChunkRenderer`, `EngineCrashGuard`, `SynthRenderGate`, the Settings voice list, the engine
probe, the Listen debug panel. Library code lives only under `Features/Speech/Engines/<Library>/`,
including its crash policy, its launch steps and its debug-panel sections. The provider protocol
and the registry sit beside them (`Features/Speech/Engines/SpeechEngineProvider.swift`): their
hooks hand out launch steps and SwiftUI sections, which Core can't name.

Persisted values never change without a migration: engine ids (`local.phonon`, `local.kokoro`), cache
voice keys (`kokoro.<voice>`, `phonon@<revision>.<voice>`), `reader.voiceSelection.default`,
`reader.tts.kokoroVoice`. A cache revision is the one planned change of a key: audio of another
revision stops counting and re-renders.

**Retired engines.** A provider lists engines it no longer ships in `retiredEngines` (id, display
name, done flag, file deleter). A stored default in an engine no longer registered takes the
built-in default (`LocalTTSCoordinator.loadDefaultSelection`), and the `RetiredEngineCleanup` launch migration deletes its cached
audio and model files once (again on a later launch if audio was held for unfinished library
work). FluidAudio lists one: Chatterbox Nano (`local.chatterbox-nano`), the
engine that also owns index files written without an engine id.

**Apple's voices** (engine id `apple`) are gone. `AppComposition.removeAppleVoices` runs once,
marked done only when every step succeeded: articles and books stored in an Apple voice
(`apple/…`) have none again, so they take the Settings default at their next first use; audio
filed under `apple` is deleted (audio held for unfinished library work waits for a later launch);
the settings only Apple used (`reader.selectedVoiceIdentifier`, `reader.languageAutomatic`,
`reader.selectedLanguageCode`, `reader.tts.engineID`) are removed. A stored default in an Apple
voice takes the built-in default as any unregistered engine's does.

### Adding an engine

1. **Dependency.** Add the package in `project.yml` (`packages:` and the target's
   `dependencies:`), then `xcodegen generate`. Library imports stay in
   `Features/Speech/Engines/<Library>/`.
2. **Host.** Implement `LocalSynthHost`: `prepare()` (prepare and load through a
   `SingleFlightLoad`, so callers share one load and a cancel reaches it; hold
   its route's lane's `SynthRenderGate.of(lane)` while loading Core ML; report `onProgress`),
   `synthesizeOnce(text:priority:threads:)` (one call at the QoS and, for a route that takes a
   count, the threads the policy passes → `SynthesizedPCM`; map the library's "input too long" error to
   `LocalSynthError.inputTooLong` so the shared renderer re-splits), `setVoice`, `unload` (for good:
   close the load first, so a load in flight can't set the models again).
3. **Descriptor.** A new, never-changing `id` (e.g. `local.<engine>`), `hardware`, and
   `OnDeviceTraits`: `cacheVoicePrefix: "<short>"` (cache voice keys `<short>.<voice>`; with a
   `cacheRevision` when the model can change under the same voices, `<short>@<revision>.<voice>`), chunk
   `limits` sized from the per-call cap (measure chars or phonemes per second of audio on a
   device), and `isCrashGuarded` if the library can die uncatchably.
4. **Provider.** A `SpeechEngineProvider` with the descriptor(s), `makeHost`, `isInstalled`,
   `routes` (a `RenderRoute` per way an engine runs: its lane, `.cpu` or `.neuralEngine`, whether
   it takes a thread count, and about how much memory its loaded host adds, measured on a phone;
   the registry refuses an engine without a `.cpu` route, every engine's fallback lane;
   `makeHost` builds a host for the route the render policy loads);
   override `recover(from:playing:)` if a crash needs more than a pause for Retry,
   `launchMigrations` for the library's launch steps (`LaunchMigration`s, run after retired
   engines' cleanup), `debugSections(speech:)` for its own Listen debug panel sections, and
   `storedKeys` for settings it stores itself (beyond each engine's voice key), which
   `-resetLibrary` clears.
   Anything that decides them (a launch argument, a setting) comes in at the provider's init.
5. **Register.** One line in `AppComposition.makeProviders()`.
6. **Verify.** A Release device run of
   `-engineProbe -probeOnly <ShortName>` (init, first audio, wall vs audio); then pick it in Settings.

The Settings row, prepare / progress / delete UI, cache, bake-ahead and probe come from the
registry.

## Settings keys

Per-engine voice keys (`reader.tts.kokoroVoice`, `reader.tts.phononVoice`), the default
selection (`reader.voiceSelection.default`: engine + voice for new articles) and
`reader.rateMultiplier`. Rate applies to every engine. Kokoro's thread count and
ONNX crash count (`reader.tts.kokoro.cpuThreads`, `.onnxCrashCount`) are
`FluidAudioProvider`'s `storedKeys`. `-resetLibrary` clears all of these.

## Cloud voices

Not built. A cloud engine would be another synth host feeding the same file player (or its own
`ListenEngine` if it streams), behind a `CloudSpeechEngine` with the provider key from the
Keychain. Offline or on failure it pauses and says so, as the on-device engines do; it never
hands the article to another voice.
