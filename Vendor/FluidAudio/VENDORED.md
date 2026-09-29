# Vendored FluidAudio (v0.16.1, b811a615)

Copied from https://github.com/FluidInference/FluidAudio (Apache-2.0) so Reader can patch it.
Tests/Documentation removed; test targets dropped from Package*.swift.

## Local patches
- `Sources/FluidAudio/TTS/Chatterbox/Nano/ChatterboxNanoModels.swift`: each model loads with
  `.cpuAndGPU` and falls back to `.cpuOnly` if Core ML refuses. On iPhone 17 Pro / iOS 26.6.2 the
  stateful `T3Nano-Decode-M1536-fp16-stateful` model fails GPU plan build with error -14 but loads
  on CPU (verified with Reader's `-nanoProbe` launch arg, 2026-09-24).
- `Package.swift` / `Package@swift-6.2.swift`: FluidAudio target gets `-O` in Debug too
  (`unsafeFlags`, allowed for a local path package). Upstream docs: Debug builds spend ~12 ms/token
  in unoptimized sampling, tripling Nano decode time.

## Reader no longer uses Chatterbox Nano (2026-09-24)
Reader removed the Nano engine; Kokoro (`KokoroAneManager`) is the only FluidAudio model it loads.
The Nano patch above is left as-is (it only touches `ChatterboxNanoModels.swift`, which Kokoro never
calls). The Debug `-O` patch still matters for Kokoro. Reader's `-nanoProbe` launch arg no longer exists.

## Kokoro ONNX-main patches (2026-09-25)
- `Sources/FluidAudio/TTS/KokoroAne/CPUFrontend/` (new): `KokoroAneCPUFrontend` (public actor) =
  the Kokoro English frontend (NeMo/regex normalizer → Misaki lexicon → OOV words) **without Core ML**.
  OOV words go through `KokoroSwiftG2P`, a pure-Swift port of the 1-layer BART G2P that reads the
  fp16 weights straight from `G2PEncoder.mlmodelc`/`G2PDecoder.mlmodelc` (`model.mil` + `weights/weight.bin`);
  the Core ML models are never loaded. Validated against Core ML `G2PModel` in the simulator:
  1179/1180 words token-identical (99.92%; the one miss, "graduates", is an fp16 near-tie and is in
  the lexicon anyway). Reader's ONNX CPU Kokoro route uses this frontend.
- `Sources/FluidAudio/Shared/CoreMLBreadcrumb.swift` (new) + calls in `TTS/G2P/G2PModel.swift`
  (before the encoder, before the decoder loop, after decoding) and
  `TTS/KokoroAne/Pipeline/KokoroAneSynthesizer.swift` (`predict(stage:)`: before and after every stage):
  crash attribution. E5RT runs Core ML on its own queue, so a libBNNS crash report doesn't show which
  model was running; Reader installs a handler that atomically writes `ListenTiming/coreml_breadcrumb.json`
  and reports it with `engine_crash_detected` on the next launch.
