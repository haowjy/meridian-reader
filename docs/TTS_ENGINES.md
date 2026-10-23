# TTS engines

Meridian Reader speaks with **Apple TTS** (always available, the default and the fallback) or an
optional on-device neural voice: **Kokoro** (default on-device choice) or **Phonon** 31m English
(selectable, not default). Voice libraries plug in behind one registry, so the listen core never
imports a library or switches on engine types. How playback, rendering and the audio cache use an
engine is in `LISTEN_PLAYBACK.md`.

## Shape

`SpeechController` owns the session (`PlaybackSessionState`: document, position, phase) and the
rate, voice and language settings, and binds one **playback engine** per utterance. On-device
audio is rendered by a **synth host** owned by `LocalSynthService`; the listen player only plays
rendered files.

```
Listen UI  →  SpeechController  →  ListenEngine (bound per utterance)
                                      ├─ AppleListenEngine   AVSpeechSynthesizer, one utterance
                                      └─ LocalListenEngine   LocalListenPlayer: file player + producer
                                                               └─ ListenUnitSource (per play): audio cache + GlobalSynthQueue
                                                                    → LocalSynthService → LocalChunkRenderer
                                                                       → LocalSynthHost (KokoroCPUHost / KokoroHost / PhononHost)
```

```swift
@MainActor
protocol ListenEngine: AnyObject {
    var name: String { get }
    var onEvent: ((PlaybackEngineEvent) -> Void)? { get set }  // audible / paused / position / finished
    func play(_ request: ListenPlayRequest)                     // document, start offset, paused?, Apple voice
    func pause(); func resume(); func stop()
    func setRate(_ multiplier: Double)
    var snapshot: PlaybackEngineSnapshot { get }
    // + listen-bar status (waiting for audio, source note), foreground hook, debug numbers
}
```

Which engine speaks, and what happens when the on-device engine finishes loading or goes away
mid-utterance, is in `LISTEN_PLAYBACK.md` → "Engine binding".

## Apple

- `AppleListenEngine`: `AVSpeechSynthesizer` with one utterance for the rest of the article.
- Voices: all installed non-novelty system voices (`VoiceCatalog`), Premium and Enhanced first then
  Standard, plus a "Best for language" system-default entry. The voice picker lists all qualities
  and labels them Premium / Enhanced / Standard.
- Default voice for English (C139): Nora / "Voice 4" (identifier contains `siri.natural.Nora` or
  name is "Voice 4") if installed, then any Premium/Enhanced voice by quality + gender + region
  score, then Samantha, Daniel, Karen, Moira, Tessa in that order among Standard voices, then any
  remaining installed voice. Non-English languages use quality + gender + region scoring only.
- Offline, nothing to prepare. Speaks whenever no on-device engine is ready, when the article's
  language isn't one the engine supports, and for any chunk the engine can't render.

## Kokoro

Kokoro-82M, English only (`supportedLanguages = ["en"]`), A15 or newer and iOS 17+ (the Simulator
is allowed). `FluidAudioProvider` declares it (`local.kokoro`) and builds its host.

### Routes

Both routes use the same voice packs, phonemes and cache key (`kokoro.<voice>`), so audio rendered
on either stays valid on the other (`KokoroRoute`, `KokoroRouteSettings`).

| Route | Host | Notes |
|---|---|---|
| **ONNX CPU** (default) | `KokoroCPUHost` | ONNX Runtime on the CPU execution provider, onnx-community `model_fp16.onnx` (≈163 MB, downloaded into `Application Support/CPURoute/kokoro-82m-v1.0-onnx/`, SHA-256 checked, excluded from backup), every core but one in front (3 to 6: 5 on an iPhone 17 Pro, so the work an efficiency core holds is a smaller piece; `reader.tts.kokoro.cpuThreads` overrides it in the debug panel) and 1 in the background (the session is rebuilt at the first call after a phase change, `KokoroONNXSessionSlot`). Each run shrinks ORT's CPU arena when it ends (`memory.enable_memory_arena_shrinkage`), so the footprint between calls stays near where it started; a memory warning lets go of the session, which the next call builds again (≈0.5 s; `kokoro_cpu_session_released`, `kokoro_cpu_session_rebuilt`). Frontend `KokoroAneCPUFrontend` (vendored FluidAudio patch: Misaki lexicon + a pure-Swift BART G2P that reads the Core ML G2P weights as data; heteronyms such as read, live, close, record pick Misaki's part-of-speech pronunciation per sentence from Apple's `NLTagger`, with auxiliary rules for past `read`, from the bundled `Resources/KokoroHeteronyms.json`, C132; an OOV `-s`/`-ed`/`-ing` word is built from its known stem by Misaki's suffix rules, a heteronym's VERB reading as the stem, so `lived` is lˈɪvd, and `c.`/`ca.` before a number reads "circa", C137), so no Core ML runs on this route. Renders in the background, in bursts that start below 4 min of listening ready ahead and stop at 8 min (LISTEN_PLAYBACK.md → "Rendering in the background"). |
| Core ML (debug) | `KokoroSplitHost` | In front, FluidAudio's 7-stage Core ML chain (`KokoroHost`) with `aneTailGpu` routing (FluidAudio #667: albert, post-albert, alignment, prosody and vocoder on `.cpuAndNeuralEngine`; noise and the iSTFT tail on `.cpuAndGPU`, so the tail never runs on the CPU's BNNS; `-kokoroUnits <label>` overrides it in Debug builds). From the first load or call made in the background until the process ends it renders on the ONNX route (`KokoroCPUHost`), after releasing the Core ML models; `prepare()` puts the ONNX files on disk so that never downloads in the background. Core ML's E5RT → libBNNS path can still crash on iOS 26.4+ (FluidAudio #844/#817); any Kokoro crash turns this route off. Listen debug panel → "Kokoro fast GPU route". Unused Core ML stages are deleted at launch while it is off. |

Measured with `-KokoroStress` (320 fixed calls, app in front, iPhone 17 Pro, iOS 26.6.2, Release
build with the Debug hooks, 2026-10-11):

| Route | Calls | Crashes | ms per audio second (× real time) | First audio, models compiled |
|---|---|---|---|---|
| ONNX CPU, 5 threads | 320 / 320 | 0 | 300, p90 325 (3.3×) | 1.25 s (load 0.8 s + call 0.47 s) |
| Core ML, `aneTailGpu` | 20, stopped at 5 crashes | 5 | 62 (16×) | 1.1–1.4 s |
| Core ML, `gpuAneVocoder` | 20, stopped at 5 crashes | 5 | 95 (10.5×) | 1.8–2.0 s |

Every Core ML crash is the same: `SIGSEGV` in `libBNNS` (`BNNSGraphContextExecute_v2`, from
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
finite. As defence in depth `KokoroCPUHost` retries a non-finite output once, then renders that
chunk with Apple, and `LocalPCMWriter` writes non-finite samples as 0.

### Assets and voices

- Shared assets (`KokoroAssets`, `Application Support/fluidaudio/Models/kokoro-82m-coreml/ANE/`):
  vocab, BART G2P, the US lexicon, voice packs (`<voice>.bin`, 0.5 MB each) and, for the Core ML
  route, the `.mlmodelc` stages. The shared ONNX model download shows progress under the voice
  list (tap to cancel). Each downloaded voice pack is removed with a swipe *Remove Download* on
  that voice row; Heart cannot be removed while it is the only curated pack on disk.
- Voices (`KokoroVoiceCatalog`): `af_heart` (Heart, default), `af_bella`, `bf_emma`, `am_puck`,
  `bm_fable`. Heart's pack ships in the app (`Resources/Kokoro/af_heart.bin`) and is copied into
  the cache on first launch (`KokoroHeartPackInstall`), so the Voice picker never starts empty.
  A stored voice that isn't curated resolves to the default. Other packs prepare (~0.5 MB) when
  the voice is chosen (`LocalTTSCoordinator.downloadVoice` → `EngineRegistry.prepareVoice`);
  only then does the voice switch. A failed prepare keeps the old voice and shows the error.
  Until Kokoro's model is ready, Apple's "Best for English" remains available as today.
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
marker (`ListenTiming/engine_inflight.json`) around every call of an engine whose descriptor sets
a crash notice (`OnDeviceTraits.crashNotice`), with the route, article, paragraph, app phase and
memory footprint (`phys_footprint`), and removes it when the call returns, so it exists only
while a call is in flight. Termination (`willTerminateNotification`, e.g. a swipe-kill while the
app runs, playing or rendering) removes it and lets no call write another.

A marker found at launch counts as a crash only when the engine killed the process
(`MarkerVerdict`); otherwise it is logged (`engine_marker_dismissed`) and the launch is a normal
one: no notice, no crash count, no voice switch, nothing reopened:

- **stale:** the resume point (written per paragraph while listening) is more than 60 s newer
  than the marker: the process played on long past the call's start, so the call didn't end it;
- **memory kill:** the call started in the background with a footprint of 1,000 MB or more: iOS
  reclaiming memory (jetsam), not the engine;
- **engine crash:** anything else, including every Core ML call (they run only in front).

For a crash the provider decides (`SpeechEngineProvider.recover(from:playing:)`; engines without
a hook switch to Apple). Kokoro answers with `KokoroCrashRecovery`:

- any crash turns the Core ML route off (the setting, so it stays off until turned on again);
- a Core ML crash → the ONNX route, and the article reopens at that paragraph;
- an ONNX crash → ONNX again and the same resume; a second ONNX crash without 40 healthy calls in
  between → Apple, with a notice in Settings ("Tap Kokoro to try again");
- resume auto-plays when the crash was under 20 minutes ago and something was playing
  (`ListenResumeTarget.forCrash`);
- the paragraph is applied only on an article that still holds the text it was played in; otherwise
  the article opens paused at its own spot (`AppLaunch.resumeAfterCrash`, `LISTEN_PLAYBACK.md`).

On the Core ML route `coreml_breadcrumb.json` names the model and stage that was about to run;
after a Kokoro crash, `FluidAudioProvider.recover` logs it as `coreml_stage` in
`engine_crash_coreml_stage`, right after `engine_crash_detected`, and clears it. A process that dies while suspended
mid-call (no notice, no time to clear) can't be told from a crash, but the render queue holds a
background task while a call is in flight as the app leaves the front, so the call ends first.

### Launch steps

`FluidAudioProvider.launchMigrations`, run by `AppComposition.prepareAudioCache` before
anything plays (after the library's unfinished audio work): `KokoroAudioCachePurge` (drops Kokoro
audio rendered before the NaN patch and the boundary-trimmed joins;
`reader.tts.kokoro.audioCacheVersion`; audio held for library work that couldn't finish is left
for a later launch's purge), `KokoroONNXMainMigration`
(a user that a Core ML crash left on Apple goes back to Kokoro on the ONNX route, at that crash's
article and paragraph, paused), `KokoroCoreMLStageCleanup` (with the Core ML route off, the
stages are deleted off the main thread whenever they are found; skipped for a Core ML stress run,
which the provider is told at init), `CoreMLCompileCacheJanitor` (Core ML's compiled-model cache,
once per install, in the background; `LISTEN_PLAYBACK.md` → "Audio cache"), and in Debug builds
`CPURouteProbes` (whether background tasks can get GPU time, `probe_bg_gpu`).

The route settings (`KokoroRouteSettings`) belong to `FluidAudioProvider`. Its Listen debug panel
section (`KokoroRouteDebugSection`, from the provider's `debugSections`) changes them through it
(`setFastGPURoute`, `setCPUThreads`), then asks the coordinator to rebuild the live host
(`LocalTTSCoordinator.reloadEngine`, which knows no engine).


## Phonon

Optional on-device English TTS via Gradium [`ptts`](https://github.com/gradium-ai/xn-ptts) 0.4.0
(Phonon 31m Core ML). **Not the default** — Settings → Listen lists it beside Kokoro; Apple stays
the fallback. iOS 18+.

| | |
|---|---|
| Engine id | `local.phonon` |
| Host | `PhononHost` (`computeUnit: .cpu` in this PR for the CPU probe vs Kokoro ONNX) |
| Models | `phonon-31m-en-coreml.zip` (~131 MB) downloaded on first use into Application Support, unzipped, then `PhononModels.install` → `PhononTTS/models` |
| Voices | Full English set in the zip (`PhononVoiceCatalog`); default `default` |
| Chunking | `TextChunker.Limits.phonon` (short first chunk for TTFA) |
| Background | No (`rendersInBackground` false) — Core ML path |
| Probe label | `phonon-31m cpu` (`routingLabel`); `-engineProbe -probeOnly Phonon,Kokoro` |

Desktop GGUF "q8" is a different stack; on iOS the fair CPU comparison is Core ML
`computeUnit: .cpu` vs Kokoro's ONNX CPU route. ANE remains Phonon's upstream default and can be
re-enabled later once the CPU numbers are in.

Files: `Features/Speech/Engines/Phonon/` (`PhononProvider`, `PhononHost`, `PhononModelStore`,
`PhononVoiceCatalog`). Registered from `AppComposition.makeProviders()`.

## Engine registry

```
AppComposition (composition root: the only file that lists libraries)
  └─ EngineRegistry(providers: [AppleSpeechProvider, FluidAudioProvider, PhononProvider])
       └─ injected → LocalTTSCoordinator(engines:defaults:…) → LocalSynthService(engines:)
            └─ SpeechController(localTTS:defaults:) over the coordinator

SpeechEngineProvider (one per library)      EngineDescriptor (per engine)
  descriptors / retiredEngines                 id, names, subtitle, recommended, sort order
  makeHost(for:voice:) → LocalSynthHost        voices + default, voice defaults key
  isInstalled / deleteModels                   hardware gate, languages
  recover(from:playing:)                       onDevice: OnDeviceTraits? (nil for Apple)
  launchMigrations / debugSections(speech:)      cache voice prefix, chunk limits, crash notice
LocalSynthHost (thin: load + ONE call)
  → LocalChunkRenderer (shared: normalize, gate, crash guard, re-split on inputTooLong, log, CAF)
```

An engine is on-device exactly when its descriptor has `OnDeviceTraits`
(`EngineRegistry.isOnDevice`): it renders ahead into the audio cache through the render queue.
The shared core has no `import FluidAudio` and no switch on engine types: `GlobalSynthQueue`
(`SynthQueueContext` and its `RenderTarget`, `RenderAdmission`), `ArticleAudioCache` keys, `TextChunker`,
`LocalChunkRenderer`, `EngineCrashGuard`, `SynthRenderGate`, the Settings voice list, the engine
probe, the Listen debug panel. Library code lives only under `Features/Speech/Engines/<Library>/`,
including its crash policy, its launch steps and its debug-panel sections. The provider protocol
and the registry sit beside them (`Features/Speech/Engines/SpeechEngineProvider.swift`): their
hooks hand out launch steps and SwiftUI sections, which Core can't name.

Persisted values never change: engine ids (`apple`, `local.kokoro`), cache voice keys
(`kokoro.<voice>`), `reader.tts.engineID`, `reader.tts.kokoroVoice`.

**Retired engines.** A provider lists engines it no longer ships in `retiredEngines` (id, display
name, done flag, replacement, file deleter). A stored selection of one maps to the replacement when
that is installed, else Apple, and the `RetiredEngineCleanup` launch migration deletes its cached
audio and model files once (again on a later launch if audio was held for unfinished library
work). FluidAudio lists one: Chatterbox Nano (`local.chatterbox-nano`), the
engine that also owns index files written without an engine id.

### Adding an engine

1. **Dependency.** Add the package in `project.yml` (`packages:` and the target's
   `dependencies:`), then `xcodegen generate`. Library imports stay in
   `Features/Speech/Engines/<Library>/`.
2. **Host.** Implement `LocalSynthHost`: `prepare()` (prepare and load through a
   `SingleFlightLoad`, so callers share one load and a cancel reaches it; hold
   `SynthRenderGate.shared` while loading Core ML; report `onProgress`), `synthesizeOnce(text:)`
   (one call → `SynthesizedPCM`; map the library's "input too long" error to
   `LocalSynthError.inputTooLong` so the shared renderer re-splits), `setVoice`, `unload` (for good:
   close the load first, so a load in flight can't set the models again).
3. **Descriptor.** A new, never-changing `id` (e.g. `local.<engine>`), `hardware`, and
   `OnDeviceTraits`: `cacheVoicePrefix: "<short>"` (cache voice keys `<short>.<voice>`), chunk
   `limits` sized from the per-call cap (measure chars or phonemes per second of audio on a
   device), and a `crashNotice` if the library can die uncatchably.
4. **Provider.** A `SpeechEngineProvider` with the descriptor(s), `makeHost`, `isInstalled`,
   `deleteModels`; override `recover(from:playing:)` if a crash needs more than "switch away",
   `launchMigrations` for the library's launch steps (`LaunchMigration`s, run after retired
   engines' cleanup), `debugSections(speech:)` for its own Listen debug panel sections, and
   `storedKeys` for settings it stores itself (beyond each engine's voice key), which
   `-resetLibrary` clears.
   Anything that decides them (a launch argument, a setting) comes in at the provider's init.
5. **Register.** One line in `AppComposition.makeProviders()`.
6. **Verify.** A Release device run of
   `-engineProbe -probeOnly <ShortName>` (init, first audio, wall vs audio); then pick it in Settings.

The Settings row, prepare / progress / delete UI, cache, bake-ahead, Apple fallback and probe
come from the registry.

## Settings keys

`reader.tts.engineID` (the engine on `ready`, Apple on `off` / `failed`), per-engine voice keys
(`reader.tts.kokoroVoice`), `reader.rateMultiplier`, `reader.languageAutomatic` and
`reader.selectedLanguageCode`. Rate and language apply to every engine. Kokoro's route knobs and
ONNX crash count (`reader.tts.kokoro.fastGPURoute`, `.cpuThreads`, `.onnxCrashCount`) are
`FluidAudioProvider`'s `storedKeys`. `-resetLibrary` clears all of these.

## Cloud voices

Not built. A cloud engine would be another synth host feeding the same file player (or its own
`ListenEngine` if it streams), behind a `CloudSpeechEngine` with the provider key from the
Keychain, falling back to Apple offline or on failure.
