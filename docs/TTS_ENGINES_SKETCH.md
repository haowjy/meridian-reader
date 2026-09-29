# TTS engines sketch (post-v1)

Status: **design only** — not in v1. v1 stays Apple `AVSpeechSynthesizer` (FRD P1).

Goal: keep today’s listen UX (play/pause/stop, paragraph skip, rate, resume) while making **audio generation** swappable: Apple system voices → **local AI models** → later **paid cloud / subscription** TTS.

## Principle

`SpeechController` stays the **session owner** (document, paragraph index, rate, UI state). It no longer owns a concrete synthesizer forever.

A `SpeechSynthesizing` engine owns **how samples / speech are produced**. Controllers and Saved/Browse listen UI talk only to `SpeechController`.

```
Listen UI  →  SpeechController  →  SpeechSynthesizing
                                      ├─ AppleSpeechEngine      (v1 / always available)
                                      ├─ LocalModelSpeechEngine (downloadable bundle)
                                      └─ CloudSpeechEngine      (subscription; optional)
```

## Protocol (sketch)

```swift
@MainActor
protocol SpeechSynthesizing: AnyObject {
    var engineID: String { get }          // "apple" | "local.<model>" | "cloud.<provider>"
    var displayName: String { get }
    var requiresNetwork: Bool { get }
    var isReady: Bool { get }             // model downloaded / entitlement valid

    func availableVoices() async -> [SpeechVoiceDescriptor]
    func prepareIfNeeded() async throws   // download / warm-up

    /// Speak `text` starting at UTF-16 offset; report word/char progress for highlighting.
    func speak(
        text: String,
        voiceID: String?,
        rate: Double,
        fromUTF16Offset: Int,
        delegate: SpeechSynthesisDelegate
    )

    func pause()
    func resume()
    func stop()
}

struct SpeechVoiceDescriptor: Identifiable, Hashable {
    var id: String
    var name: String
    var languageCode: String
    var qualityLabel: String?    // "Enhanced", "Neural", …
    var engineID: String
    var isInstalled: Bool
}
```

Progress / finish / cancel stay on a small delegate so Apple’s `AVSpeechSynthesizerDelegate` and a PCM player for local/cloud engines map to the same paragraph + highlight updates.

## Engine 1 — Apple (keep)

- Thin wrapper around current `AVSpeechSynthesizer` path.
- Voices = installed system voices (`VoiceCatalog` today).
- Offline. Zero download beyond what the user already gets from Settings.
- Default engine forever (fallback if local model missing or cloud fails).

## Engine 2 — Local AI model

**Idea:** ship or download a neural TTS package into app sandbox (not into iOS Settings voices).

Candidate families (pick one in a spike):

| Option | Pros | Cons |
|--------|------|------|
| Piper / ONNX small voices | Small, proven offline, many langs | Quality below top neural |
| Kokoro / similar Core ML | Better quality | Larger; packaging work |
| Custom Core ML export | Full control | Training/export cost |

**Install flow**

1. Settings → Voices → “On-device AI voices”.
2. List models with size (~50–500+ MB), languages, sample.
3. Download to `Application Support/TTSModels/<id>/` with resumable URLSession; verify checksum.
4. Mark `isInstalled`; appear in voice picker under a separate section.
5. Delete model reclaiming space.

**Runtime**

- Load model once; synthesize **paragraph chunks** (same paragraph boundaries as today) to PCM.
- Play via `AVAudioEngine` / `AVAudioPlayerNode` (or write temp CAF and play).
- Map byte/frame progress → approximate UTF-16 offset for highlight (or request word timestamps if the model provides them).
- Rate: time-stretch carefully, or re-synthesize at rate if cheap enough.

**Constraints**

- First launch of a model: warm-up latency; show “Preparing voice…”.
- Thermal / battery: prefer streaming chunk synthesis, not whole-article upfront.
- App Store: large on-demand resources (ODR) or first-run download; disclose size.
- Still **offline listen** once installed → preserves Saved/Speak offline story.

## Engine 3 — Paid / subscription cloud (later)

- Same `SpeechSynthesizing` surface.
- `requiresNetwork = true`; gate with StoreKit 2 entitlement.
- Stream or fetch audio per paragraph; cache recent paragraphs optionally.
- On failure / offline / no sub → automatic fallback to Apple (or installed local model), with a quiet banner once.
- Do **not** bake provider SDKs into `SpeechController`; wrap behind `CloudSpeechEngine`.

## Selection & settings UX

Voice picker becomes two-level:

1. **Engine** — Apple | On-device AI | Premium (if entitled)
2. **Voice** within that engine

Persist:

- `reader.tts.engineID`
- `reader.tts.voiceID` (engine-scoped)
- Existing rate + language prefs stay global where they still make sense

Mid-playback engine/voice change = stop + restart current paragraph with new engine (same as today’s voice hot-swap).

## What stays stable

- `SpeechSession` / paragraph document / resume indices in SwiftData  
- Listen bar UI  
- Offline Saved playback **as long as** the chosen engine is Apple or an installed local model  

## What changes when we build it

1. Extract Apple path from `SpeechController` into `AppleSpeechEngine`.
2. Introduce `SpeechSynthesizing` + engine registry at composition root.
3. Spike one local model end-to-end (download → speak one article → paragraph skip).
4. Only then design StoreKit + `CloudSpeechEngine`.

## FRD impact (when we commit)

- Soften P1 from “Apple only” to “Default Apple; optional local/cloud engines”.
- Add: local model download/delete; offline once installed; cloud requires sub + network; fallback rules.
- Keep custom cloud as **non-goal for v1**; this doc is post-v1.

## Open decisions (spike)

1. Which local model family and max download size we accept.
2. Word-level timing quality for HTML highlight with non-Apple engines.
3. Whether Premium is subscription-only or also pack-based voice purchases.
4. Whether Apple Enhanced-voice deep-link ships in v1 as a small win before local AI.

## Model catalog UX (curated + optional Hub browse)

**Recommendation:** curated allowlist first; Hugging Face as discovery for *already-supported runtimes*, not a raw App Store for every Hub TTS repo.

Why not “browse all HF TTS”:
- `GET https://huggingface.co/api/models?pipeline_tag=text-to-speech&sort=downloads` works and is public.
- Most hits are PyTorch/CUDA research checkpoints (Kokoro, XTTS, Qwen3-TTS, full Chatterbox, …) that will not run in Reader as-is.
- iOS needs a **runtime pack** we own (Core ML / ExecuTorch / ONNX Runtime Mobile) + known input/output contract + RAM/disk budgets.
- Licensing, watermarking, and “looks like TTS but is voice-conversion / 7GB desktop” noise.

**Proposed UI**
1. **Featured by tier** (pinned JSON we ship / fetch from our CDN):
   - *Lite* — small Kokoro/Piper-class or Nano distilled packs (~100–400 MB)
   - *Standard* — Chatterbox-Nano Core ML–class (~0.7–1 GB)
   - *Heavy* — only if device class allows (A17+/lots of free disk); warn hard
2. Each card: size, languages, quality note, sample clip, min iOS / chip hint, license.
3. **Browse Hub** (secondary): search HF TTS, but only surface repos that match a **manifest we understand** (e.g. tag `reader-tts` / known `library_name` / companion `reader-ios.json` with Core ML file list + SHA256). Everything else: “Open on Hugging Face” (Safari), not Install.
4. Install path always downloads **our resolved artifact list**, never “git clone the whole repo.”

## Chunk / prefetch queue (research takeaway)

**Yes — pipelined chunk synthesis + bounded playback queue is the standard approach** for neural TTS (on-device and streaming). Apple’s one-shot `AVSpeechUtterance` is the exception.

What production / OSS stacks do:
- Split at sentence/paragraph (then soft max length ~100–400 chars or model token limit).
- Synthesize chunk **N+1 while N plays** (single synth worker — avoid parallel model runs / OOM).
- Feed PCM into a **bounded** audio queue (`AVAudioPlayerNode` schedule); start after a short watermark (~0.2–0.5 s).
- **Backpressure**: pause synth when queued audio exceeds ~2–5 s; resume when below threshold (prevents multi‑10 MB PCM buildup).
- Cancel + clear queues on skip / voice / rate / stop (same role as today’s `speakGeneration`).
- Optional: keep model “session” warm (voice conditioning) across chunks; reset only what the model requires per chunk.

So for Reader local/cloud engines: implement that pipeline behind `SpeechSynthesizing`. Apple engine stays utterance-based with no queue.

## Phased shipping (agreed direction)

### Principles
- Prefer the **smallest/fastest** model that sounds good enough; Apple remains default forever.
- On model **select**, **keep the model warm** for the Listen session (unload after idle / memory warning).
- Hybrid audio: Save-time bake when possible + live chunk pipeline as fill-in.

### Phase 0 — no Reader backend required
You **can** still update models over the air without running your own server:

| Mechanism | Role |
|-----------|------|
| Hugging Face Hub (or static CDN) | Host model artifacts + SHA256 |
| Tiny manifest JSON (on HF, GitHub raw, or CDN) | Pin which pack is “Lite / Standard” right now |
| App Store app update | Only needed when the **runtime** (Core ML graph contract) changes |

So: ship the app with Apple TTS + “Download on-device voice” that pulls a **pinned** pack (start with Chatterbox-Nano Core ML or a lighter pack if Nano is too heavy in practice). Manifest URL can point at HF. Rotate the pin by editing that JSON — no App Store review for weight swaps, as long as the engine code still understands the format.

**Do not** embed the full ~1 GB pack in the IPA (cellular download warnings, update pain). Optional: tiny demo voice in-app; full pack on demand.

### Phase 1 — if traction
- Own a small backend / CDN for curated rotating list, analytics on which packs succeed, kill-switches.
- Paid **hosted** TTS (subscription) as another `SpeechSynthesizing` engine.
- Richer Hub browse still gated by “we can run this” manifests.

### Explicit non-goals until Phase 1
- Running arbitrary HF TTS repos in-app
- Bundling multiple multi‑GB models in the binary

## Device gate — Chatterbox Nano = A15+ / iOS 18+ (historical; Nano retired 2026-09-24)

Gates now come from each engine's `EngineDescriptor.hardware` via `DeviceChipGate.meets(_:)`; the Nano-specific helpers below were removed.

Nano (and similar ~0.7–1 GB Core ML packs) are **not** offered below A15 or on Simulator.

- **API:** `DeviceChipGate.supportsChatterboxNano` (`Core/Device/DeviceChipGate.swift`)
- **Hardware check:** `uname` machine id → `DeviceChipGeneration` (no public Apple “A15” API; product-id map is the usual approach). Summary: `chatterboxNanoRequirementSummary` = `iPhone 13 / recent iPad · iOS 18+`.
- **Floor:** physical A15+ (iPhone 13 / 14 / SE 3+, iPad mini 6 / Air 5 / Pro M1+, etc.) **and** iOS 18+. iPhone 12 / A14 / older iPads, and **Simulator**, all fail `chipOK` the same way.
- **Why not iOS-only?** iOS 18 runs on A12+ devices; that is the Core ML `MLState` API floor, not the silicon Nano needs. Keep chip + OS.
- **Disallow + warn:** when `!supportsChatterboxNano`, Nano is disabled. Subtitle always predicts the need (`Needs iPhone 13 / recent iPad · iOS 18+`); footer is `Insufficient hardware. Needs …`. Select / download / prepare force Apple. Chip and OS are both required; we do not branch the user-facing string.
- Lighter Piper/Kokoro-class packs may use a lower floor later; pin per manifest (`minChip: a15`).

## Phase 0 implementation status (2026-09-22; historical — manifest, `LocalTTSModelStore`, `TTSProbeLite` removed 2026-09-24)

Shipped scaffolding in-app:

- Bundled pin `Resources/tts/chatterbox-nano.manifest.json` → `FluidInference/chatterbox-nano-coreml` revision `6eb3640c…`
- Download / size-check / delete via `TTSModelDownloader` (Application Support/TTSModels/chatterbox-nano/)
- A15+ gate via `DeviceChipGate.supportsChatterboxNano`
- Warm-on-select via `LocalTTSModelStore` (not on cold launch); unload ~60s / memory warning
- Probe-lite launch arg `-ReaderTTSProbeLite` (~2.3 MB) vs full SPEAK pack (~746 MB)
- Save-time bake + `ArticleAudioCache` under Application Support/TTSCache/<articleID>/
- **Clear listen audio** keeps the Saved article; deleting the article also clears its audio
- Speak/bake audio currently uses `ProbePCMRenderer` (`AVSpeechSynthesizer.write`) until Nano host speak ships; Core ML warm-load of the four SPEAK `.mlmodelc` graphs is real on the full pack

Apple remains the default engine forever.


## Phase 1 implementation status (2026-09-22, amended 2026-09-23; historical — Nano removed 2026-09-24)

| Real | Notes |
|---|---|
| FluidAudio `ChatterboxNanoManager.synthesize` on iOS 18+ | Replaces Probe on Nano path |
| SPM pin FluidAudio `from: "0.16.1"` | Beta API |
| A15+ **and** iOS 18 (iPhone + eligible iPad; Sim fails chip floor) | Chip + OS; iOS alone is not enough |
| FluidAudio ModelHub cache (`fluidaudio/`) | Prefer over dual Reader `TTSModels` warm |
| UI “Ready” = `nanoHostReady` after `initialize` | Not Reader `TTSModels` presence |
| Speak failure clears Nano → Apple | No silent Apple-while-Nano-checked |
| Serialized `prepare()` | Stops dual-download weight.bin races |
| Apple remains default | |

Do not claim device-validated Nano timbre until a **physical** A15+ / iOS 18 device bake proves non-AVSpeech audio. Simulator shows the same chip-floor gate as older phones/iPads.

## 2026-09-24 — Kokoro becomes the primary local engine

Decision (Jimmy): Chatterbox Nano is too slow for listening; **Kokoro is the default local engine**,
Apple remains the always-available fallback / default when no model is installed. (Later the same day
Nano was removed entirely: **Kokoro is the only local engine**; see "Chatterbox Nano removed" below.
The Nano column is kept for reference.)

| | Kokoro (KokoroAne) | Chatterbox Nano |
|---|---|---|
| FluidAudio API | `KokoroAneManager(variant: .english)` | `ChatterboxNanoManager(.standard)` |
| iOS floor | 17 (package floor) | 18 (MLState) |
| Reader gate | A15+ (`DeviceChipGate.supportsKokoro`; Simulator allowed) | A15+ and iOS 18 |
| Download | ≈95 MB: 7 `.mlmodelc` stages ≈82 MB (`kokoro-82m-coreml/ANE`), `af_heart.bin` 0.5 MB, BART G2P ≈1.6 MB, Misaki `us_lexicon_cache.json` ≈10 MB. No espeak. | ≈700 MB |
| Compute | Reader on iOS 26.4+: all stages GPU except vocoder on ANE (`gpuAneVocoder`, see below); other OS: FluidAudio default (RNN stages ANE, noise + tail GPU) | cpuAndGPU (decode falls back to CPU on device: GPU plan load −14) |
| Per call | ≤510 phonemes, ≤2000 frames (≈50 s) | ≤135 BPE tokens, ≤247 speech tokens ≈ 9.9 s |
| Output | full chunk, deterministic, 24 kHz | full chunk, seeded, 24 kHz |
| Voices | 54 English-usable packs; default `af_heart`; Reader exposes 5 curated (`KokoroVoiceCatalog`, Settings → Voice) | built-in voice |

Implementation: `Features/Speech/Engines/FluidAudio/KokoroHost.swift` behind `LocalSynthHost`
(`Core/TTS/Engines/LocalSynthHost.swift`), registered by `FluidAudioProvider`; download-on-select with % progress in Settings, swipe to
delete (removes `Application Support/fluidaudio/Models/{kokoro-82m-coreml,kokoro}`).

**libBNNS crash: reproduced, and mitigated by routing.** FluidAudio's advisory flags iOS/iPadOS 26.4+
for an uncatchable libBNNS crash during Kokoro synthesis (#844/#817/#328). On Jimmy's iPhone 17 Pro
(iOS 26.6.2, Release build) the **default routing** crashed 3 times: SIGSEGV in
`BNNSGraphContextExecute_v2 <- E5RT BnnsCpuInferenceOperation` on `com.apple.e5rt.concurrentExecutionQueue`,
on the 1st bake call of one session and the 5th probe call of another (`Reader-2026-09-24-1725*/1730*/1733*.ips`).
Routing sweep (launch arg `-kokoroUnits`, same probe texts):

| routing | result | 137 chars (8.65 s audio) | 399 chars (25.25 s) |
|---|---|---|---|
| FluidAudio default (RNN stages ANE) | **crashed** (1st / 5th call) | ~350-470 ms before crash | - |
| `cpuAndGpu` (all GPU) | 24 calls, no crash | 7.7 s (~1.1x) | 20.3 s (~1.2x) |
| **`gpuAneVocoder`** (all GPU, vocoder ANE) | 4 + 20 + 4 + 150 calls, no crash | 480-490 ms (~18x) | 1.37-1.38 s, first audio 435-454 ms |

Reader therefore defaults to `gpuAneVocoder` on iOS 26.4-26.x (`KokoroHost.defaultUnitsLabel`)
and keeps FluidAudio's default elsewhere. This is a **mitigation backed by about 180 crash-free calls,
not proof**. So `EngineCrashGuard` (enabled by the descriptor's `crashGuarded` flag) also writes an in-flight marker around every Kokoro call. If the
process dies inside one, the next launch switches to Apple and shows a notice in
Settings ("Tap Kokoro to try again").

## Chatterbox Nano removed (2026-09-24)

Decision (Jimmy): remove Nano entirely. **Kokoro is the only local engine; Apple is the fallback**
(default with no model, and the crash fallback after a Kokoro crash).

- Removed: `ChatterboxNanoHost`, `NanoLoadProbe`, the Nano descriptor/limits and Settings row,
  `Resources/tts/chatterbox-nano.manifest.json`, `TTSModelManifest`, `TTSProbeLite`,
  `LocalTTSModelStore`, the downloader's manifest path (`TTSModelDownloader` is now UI state only),
  `DeviceChipGate` Nano helpers, `-nanoProbe`/`-nanoOnly`.
- Renamed: `NanoTextChunker` → `TextChunker`, `Limits.nano` → `Limits.tenSecondCall`,
  `NanoHostEmpty` → `NothingSpeakable`, `warmingNano`/`usingNano` → `warmingLocal`/`usingLocal`,
  timing field `nano_ready` → `local_ready`, log tag `[NanoPlay]` → `[LocalPlay]`.
- One-time launch migration (selection remap, Nano cache + model purge, bytes-freed log): see
  `LISTEN_PLAYBACK.md` → "Chatterbox Nano retirement".
- `Vendor/FluidAudio` keeps its local Nano patches (harmless for Kokoro; see `VENDORED.md`).

## Engine dependency injection (2026-09-24)

Goal: voice libraries plug in without touching the shared listen core.

```
AppComposition (composition root: the only file that lists libraries)
  └─ EngineRegistry(providers: [AppleSpeechProvider, FluidAudioProvider, (SpeechSwiftProvider)])
       └─ injected → SpeechController(engines:) → LocalTTSCoordinator(engines:) → LocalModelSpeechEngine(engines:)

SpeechEngineProvider (one per library)      EngineDescriptor (capabilities, per engine)
  descriptors / retiredEngines                   id, names, subtitle, recommended, sort order
  makeHost(for:voice:) → LocalSynthHost       voices + default, voice defaults key, cache voice key style
  isInstalled / deleteModels                  streaming, chunk limits + notes, assets + size
                                              hardware gate, compute routing, quirks
LocalSynthHost (thin: load + ONE call)        supportsBakeCache, crashGuarded, crash notice text
  → LocalChunkRenderer (shared: normalize, gate, crash guard, re-split on inputTooLong, log, CAF)
```

Shared core (no `import FluidAudio`, no switching on engine types): `GlobalSynthQueue`
(`SynthQueueContext`), `ArticleAudioCache` keys, bake marks, `TextChunker`,
`LocalChunkRenderer`, `EngineCrashGuard`, `SynthRenderGate`, Settings voice list, engine probe.
Library code lives only under `Features/Speech/Engines/<Library>/`.

Persisted values are unchanged: engine ids (`apple`, `local.kokoro`; retired `local.chatterbox-nano`
is still recognized for migration), cache voice keys (`kokoro.<voice>`), `reader.tts.kokoroVoice`
— existing caches and settings keep matching (pinned by
`EngineRegistryTests.testPersistedIDsAndCacheKeysUnchanged`).

Test seam: `Tests/Fakes/FakeEngineProvider.swift` (tone/silence PCM, latency, per-call cap →
`inputTooLong`, hard failure) + `FakeQueueContext` (temp-dir cache). Tests cover chunking by
capabilities, overflow → re-split, fail → Apple fallback, and queue priority.

### How to add an engine/library

1. **Dependency.** Add the SPM package in `project.yml` (`packages:` + the target's
   `dependencies: - package: … product: …`), then `xcodegen generate`. Library imports stay in
   `Features/Speech/Engines/<Library>/`.
2. **Host.** Implement `LocalSynthHost`: `prepare()` (download + load; hold
   `SynthRenderGate.shared` while loading Core ML; report `onProgress`), `synthesizeOnce(text:seed:)`
   (ONE call → `SynthesizedPCM`; map the library's "input/output too long" error to
   `LocalSynthError.inputTooLong` so the shared renderer re-splits), `setVoice`, `resetPrepared`, `unload`.
3. **Descriptor.** Fill an `EngineDescriptor`: a new, never-changing `id` (e.g. `local.qwen3-tts`),
   `cacheVoiceKey: .prefixed("<short>")`, chunk `limits` sized from the per-call cap (measure
   s/char or phonemes/char on device), `hardware`, `crashGuarded` if the library can die uncatchably.
4. **Provider.** A `SpeechEngineProvider` returning the descriptor(s), `makeHost`, `isInstalled`,
   `deleteModels` (and `retiredEngines` if it removes an engine: id, done flag, replacement, file
   deleter; the coordinator remaps the selection and purges that engine's cache once).
5. **Register.** One line in `AppComposition.makeProviders()`.
6. **Verify.** `EngineRegistryTests` style test for ids/keys; Release device run of
   `-engineProbe -probeOnly <ShortName>` (init, first audio, wall vs audio); then pick it in Settings.

The Settings row, download/progress/delete UI, bake marks, cache, BG bake, never-skip fallback and
probe all come from the registry automatically.

### Example: speech-swift Qwen3-TTS (skeleton already in the repo)

`Features/Speech/Engines/SpeechSwift/SpeechSwiftProvider.swift` holds a compiled-out
(`#if canImport(Qwen3TTSCoreML)`) provider + host, and `AppComposition` registers it behind the same
`#if`. To turn it on:

```yaml
# project.yml
packages:
  SpeechSwift:
    url: https://github.com/soniqo/speech-swift
    from: <pinned version>      # Apache-2.0; package floor iOS 18 / macOS 15
targets:
  Reader:
    dependencies:
      - package: SpeechSwift
        product: Qwen3TTSCoreML
```

```swift
// Features/Speech/Engines/SpeechSwift/SpeechSwiftProvider.swift (abridged)
import Qwen3TTSCoreML
extension SpeechEngineID { static let qwen3TTS = SpeechEngineID("local.qwen3-tts") }

final class Qwen3Host: LocalSynthHost {
    func prepare() async throws {            // hold SynthRenderGate while loading
        model = try await Qwen3TTSCoreMLModel.fromPretrained(progressHandler: { p, _ in onProgress?(p) })
    }
    func synthesizeOnce(text: String, seed: UInt64) async throws -> SynthesizedPCM {
        // ≤125 codec tokens ≈ 10 s per call; map its "too long" error → LocalSynthError.inputTooLong
        SynthesizedPCM(samples: try model.synthesize(text: text, language: "english"), sampleRate: 24_000)
    }
}
// + SpeechSwiftProvider: descriptor (limits .tenSecondCall until measured, cacheVoiceKey .prefixed("qwen3"),
//   hardware iOS 18 / A17+ guess), makeHost, isInstalled/deleteModels (HF cache dir).
```

Then fill in `isInstalled` / `deleteModels` (speech-swift's HuggingFace cache dir), measure on device,
and set real `limits`, `approxDownloadBytes`, `subtitle` and `hardware`. Note: vendoring both
FluidAudio and speech-swift may duplicate model downloads/caches; check the combined app size.

## CPU route (ONNX Runtime) — debug benchmark only (2026-09-24)

Not an engine yet: no `EngineDescriptor` / provider. `KokoroONNXSession` (ORT, CPU EP) +
`KokoroCPURouteFrontend` (implemented by `KokoroHost`, so FluidAudio stays confined to the
FluidAudio folder) back the Listen debug panel's "CPU route benchmark". If it graduates to a
background renderer it should become a second host behind the Kokoro descriptor (same voices,
same phonemes), selected only when `AppRunState` is background. See docs/LISTEN_PLAYBACK.md
§ CPU route benchmark.

## Kokoro: ONNX CPU is the main route (2026-09-25)
- **Default route = ONNX Runtime on CPU** (`KokoroCPUHost`, onnx-community Kokoro-82M fp16, ~163 MB,
  3 threads). Core ML's CPU path (E5RT → libBNNS) crashes on iOS 26.4+; ORT has its own CPU kernels.
- Frontend = `KokoroAneCPUFrontend` (vendored FluidAudio patch): lexicon + pure-Swift BART G2P that
  reads the Core ML G2P weights as data — **no Core ML anywhere on the ONNX route**.
- Core ML GPU route (`KokoroHost`) is a debug toggle: Listen debug panel → "Kokoro fast GPU route
  (may crash on iOS 26.4+)". Foreground only; unused Core ML stages are deleted at launch when off.
- Route selection: `KokoroRouteSettings` / `KokoroRoutePolicy` (Core/TTS/Engines/KokoroRoute.swift);
  `FluidAudioProvider.makeHost` returns the route's host.
- Auto-recover `KokoroCrashRecovery`: Core ML crash → ONNX + resume; ONNX crash → ONNX again + resume;
  2nd ONNX crash (without 40 healthy calls between) → Apple with an explicit notice.
- Phonemizer finding: FluidAudio's G2P (`G2PModel`, BART) **is Core ML**, loaded `.cpuOnly` → runs on
  E5RT/BNNS on iOS 26.4+, per OOV word (1 encoder + ≤64 decoder predictions). On the Core ML route it
  is instrumented with the `CoreMLBreadcrumb` patch; on the ONNX route it is never loaded.

## Kokoro ONNX NaN fix + chunk joins (2026-09-25)
The onnx-community fp16 Kokoro model can output an all-NaN chunk (exact fp16 0/0 inside the
generator's `atan2` = `Atan(Div(imag, real))`). `KokoroONNXModelPatch` guards every `Atan` input
with `Where(IsNaN(x), 0, x)` once after download; `CPURouteModelStore.ensurePatchedModel()` swaps
the file. Chunk joins are trimmed to boundary-sized pauses (`ChunkEdgeTrim`) and chunking is
hierarchical (sentences → clauses). Details: `LISTEN_PLAYBACK.md` → "Run-on paragraphs".
