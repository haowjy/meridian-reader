# Speech: deferred

- `Core/TTS/TextChunker.swift`: the head-start ramp isn't guaranteed on ordinary paragraphs. A
  second or third chunk that is a whole sentence with no clause boundary inside the budget stays
  whole (e.g. 204 units after a 40-unit first chunk), so its render can outrun the audio ahead of
  it. `FirstChunkBoundaryTests.testHeadStartRampStillHoldsForThePieces` checks only the pieces of
  split paragraphs. Options: cut at the first clause past the budget, or let the head-start rule
  hand that paragraph to Apple.
- `Features/Speech/CPURoute/CPURouteBenchInputs.swift`: `KokoroCPUBenchText.long` (and its
  phonemes) is text from a third-party web novel. Replacing it means changing the Mac ORT
  benchmark's input in lockstep and re-pinning `KokoroCPUInputsTests` (501 / 190 phonemes) and
  `KokoroONNXSessionTests` (sample count, RMS).
