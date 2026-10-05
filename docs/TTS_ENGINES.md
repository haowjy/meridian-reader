# TTS engines

Reader speaks with **Apple TTS** (always available, the default and the fallback) or **Kokoro**,
an optional on-device neural voice. Voice libraries plug in behind one registry, so the listen
core never imports a library or switches on engine types. How playback, rendering and the audio
cache use an engine is in `LISTEN_PLAYBACK.md`.

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
                                                                       → LocalSynthHost (KokoroCPUHost / KokoroHost)
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
- Voices: the installed system voices of good quality (`VoiceCatalog`), "System default" first.
- Offline, nothing to download. Speaks whenever no on-device engine is ready, when the article's
  language isn't one the engine supports, and for any chunk the engine can't render.

## Kokoro

Kokoro-82M, English only (`supportedLanguages = ["en"]`), A15 or newer and iOS 17+ (the Simulator
is allowed). `FluidAudioProvider` declares it (`local.kokoro`) and builds its host.

### Routes

Both routes use the same voice packs, phonemes and cache key (`kokoro.<voice>`), so audio rendered
on either stays valid on the other (`KokoroRoute`, `KokoroRouteSettings`).

| Route | Host | Notes |
|---|---|---|
| **ONNX CPU** (default) | `KokoroCPUHost` | ONNX Runtime on the CPU execution provider, onnx-community `model_fp16.onnx` (≈163 MB, downloaded into `Application Support/CPURoute/kokoro-82m-v1.0-onnx/`, SHA-256 checked, excluded from backup), 3 threads (`reader.tts.kokoro.cpuThreads`). Frontend `KokoroAneCPUFrontend` (vendored FluidAudio patch: Misaki lexicon + a pure-Swift BART G2P that reads the Core ML G2P weights as data), so no Core ML runs on this route. Renders in the background. |
| Core ML GPU (debug) | `KokoroHost` | FluidAudio's 7-stage Core ML chain, `gpuAneVocoder` routing on iOS 26.4+ (all stages GPU, vocoder ANE; `-kokoroUnits <label>` overrides it in Debug builds). About 4× faster, but Core ML's CPU path (E5RT → libBNNS) crashes on iOS 26.4+ (FluidAudio #844/#817) and the GPU is off-limits in the background. Listen debug panel → "Kokoro fast GPU route". Unused Core ML stages are deleted at launch while it is off. |

Only the ONNX route needs the model patch: the fp16 model can output an all-NaN chunk (an exact
fp16 0/0 inside the generator's `atan2`, exported as `Atan(Div(imag, real))`).
`KokoroONNXModelPatch` puts `Where(IsNaN(x), 0, x)` in front of every `Atan` once after download
(`KokoroONNXModelStore.ensurePatchedModel`); audio is bit-identical wherever the original was
finite. As defence in depth `KokoroCPUHost` retries a non-finite output once, then renders that
chunk with Apple, and `LocalPCMWriter` writes non-finite samples as 0.

### Assets and voices

- Shared assets (`KokoroAssets`, `Application Support/fluidaudio/Models/kokoro-82m-coreml/ANE/`):
  vocab, BART G2P, the US lexicon, voice packs (`<voice>.bin`, 0.5 MB each) and, for the Core ML
  route, the `.mlmodelc` stages. Settings shows download progress; swipe to delete.
- Voices (`KokoroVoiceCatalog`): `af_heart` (default), `af_bella`, `bf_emma`, `am_puck`,
  `bm_fable`. A stored voice that isn't curated resolves to the default. A voice pack downloads
  when the voice is chosen (`LocalTTSCoordinator.chooseVoice` → `EngineRegistry.prepareVoice`);
  only then does the voice switch. A failed download keeps the old voice and shows the error.
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
`crashGuarded`, with the route, article, paragraph and phase. On the next launch the provider
decides (`SpeechEngineProvider.recover(from:playing:)`; engines without a hook switch to Apple).
Kokoro answers with `KokoroCrashRecovery`:

- a Core ML route crash → the ONNX route, and the article reopens at that paragraph;
- an ONNX crash → ONNX again and the same resume; a second ONNX crash without 40 healthy calls in
  between → Apple, with a notice in Settings ("Tap Kokoro to try again");
- resume auto-plays when the crash was under 20 minutes ago and something was playing
  (`ListenResumePoint`).

On the Core ML route `coreml_breadcrumb.json` names the model and stage that was about to run;
it is logged as `coreml_stage` in `engine_crash_detected`.

### One-time launch steps

`FluidAudioProvider.launchMigrations`, run by `AppComposition.prepareAudioCache` before
anything plays (after the library's unfinished audio work): `KokoroAudioCachePurge` (drops Kokoro audio rendered before the NaN patch and
the boundary-trimmed joins; `reader.tts.kokoro.audioCacheVersion`) and `KokoroONNXMainMigration`
(a user that a Core ML crash left on Apple goes back to Kokoro on the ONNX route, at that crash's
article and paragraph, paused).

## Engine registry

```
AppComposition (composition root: the only file that lists libraries)
  └─ EngineRegistry(providers: [AppleSpeechProvider, FluidAudioProvider, (SpeechSwiftProvider)])
       └─ injected → SpeechController(engines:) → LocalTTSCoordinator(engines:) → LocalSynthService(engines:)

SpeechEngineProvider (one per library)      EngineDescriptor (per engine)
  descriptors / retiredEngines                 id, names, subtitle, recommended, sort order
  makeHost(for:voice:) → LocalSynthHost        voices + default, voice defaults key, cache voice key style
  isInstalled / deleteModels                   chunk limits, hardware gate, languages
  recover(from:playing:) / launchMigrations    supportsBakeCache, crashGuarded, crash notice text
LocalSynthHost (thin: load + ONE call)
  → LocalChunkRenderer (shared: normalize, gate, crash guard, re-split on inputTooLong, log, CAF)
```

The shared core has no `import FluidAudio` and no switch on engine types: `GlobalSynthQueue`
(`SynthQueueContext`, `RenderAdmission`), `ArticleAudioCache` keys, `TextChunker`,
`LocalChunkRenderer`, `EngineCrashGuard`, `SynthRenderGate`, the Settings voice list, the engine
probe. Library code lives only under `Features/Speech/Engines/<Library>/`, including its crash
policy and its launch steps.

Persisted values never change: engine ids (`apple`, `local.kokoro`), cache voice keys
(`kokoro.<voice>`), `reader.tts.engineID`, `reader.tts.kokoroVoice`
(`EngineRegistryTests.testPersistedIDsAndCacheKeysUnchanged`).

**Retired engines.** A provider lists engines it no longer ships in `retiredEngines` (id, display
name, done flag, replacement, file deleter). A stored selection of one maps to the replacement when
that is installed, else Apple, and the `RetiredEngineCleanup` launch migration deletes its cached
audio and model files once. FluidAudio lists one: Chatterbox Nano (`local.chatterbox-nano`), the
engine that also owns index files written without an engine id. `EngineRetirementTests` covers it.

Test seam: `Tests/Fakes/FakeEngineProvider.swift` (tone/silence PCM, latency, per-call cap →
`inputTooLong`, hard failure) and `FakeQueueContext` (temp-dir cache).

### Adding an engine

1. **Dependency.** Add the package in `project.yml` (`packages:` and the target's
   `dependencies:`), then `xcodegen generate`. Library imports stay in
   `Features/Speech/Engines/<Library>/`.
2. **Host.** Implement `LocalSynthHost`: `prepare()` (download and load; hold
   `SynthRenderGate.shared` while loading; report `onProgress`), `synthesizeOnce(text:)` (one call →
   `SynthesizedPCM`; map the library's "input too long" error to `LocalSynthError.inputTooLong` so
   the shared renderer re-splits), `setVoice`, `resetPrepared`, `unload`.
3. **Descriptor.** A new, never-changing `id` (e.g. `local.qwen3-tts`), `cacheVoiceKey:
   .prefixed("<short>")`, chunk `limits` sized from the per-call cap (measure chars or phonemes per
   second of audio on a device), `hardware`, `crashGuarded` if the library can die uncatchably.
4. **Provider.** A `SpeechEngineProvider` with the descriptor(s), `makeHost`, `isInstalled`,
   `deleteModels`; override `recover(from:playing:)` if a crash needs more than "switch away".
5. **Register.** One line in `AppComposition.makeProviders()`.
6. **Verify.** An `EngineRegistryTests`-style test for ids and keys; a Release device run of
   `-engineProbe -probeOnly <ShortName>` (init, first audio, wall vs audio); then pick it in Settings.

The Settings row, download / progress / delete UI, cache, bake-ahead, Apple fallback and probe
come from the registry.

`Features/Speech/Engines/SpeechSwift/SpeechSwiftProvider.swift` is a compiled-out
(`#if canImport(Qwen3TTSCoreML)`) provider and host for speech-swift's Qwen3-TTS, registered
behind the same `#if`. Turning it on means adding the package
(`https://github.com/soniqo/speech-swift`, product `Qwen3TTSCoreML`, package floor iOS 18), then
filling in `isInstalled` / `deleteModels`, measured `limits`, `subtitle` and `hardware`.

## Settings keys

`reader.tts.engineID` (the engine on `ready`, Apple on `off` / `failed`), per-engine voice keys
(`reader.tts.kokoroVoice`), `reader.rateMultiplier`, `reader.languageAutomatic` and
`reader.selectedLanguageCode`. Rate and language apply to every engine.

## Cloud voices

Not built. A cloud engine would be another synth host feeding the same file player (or its own
`ListenEngine` if it streams), behind a `CloudSpeechEngine` with the provider key from the
Keychain, falling back to Apple offline or on failure.
