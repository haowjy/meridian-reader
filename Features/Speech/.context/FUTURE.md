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
- Background baking: the app registers no `BGProcessingTask`, so saved articles bake only while
  the app is open. Rebuild it around the library's queue (`PendingBakeJobStore` →
  `GlobalSynthQueue`): render saved articles overnight while the phone charges.
- A session older than its page plays on unrecorded. Progress is written only on a page holding
  the text playing (`LibraryStore.holds`), so a session whose page has other text by then plays
  its own text to the end and records nothing: a paused session resumed after the page was
  refreshed on open, a staged next chapter a *Replace* revised, a chapter kept playing through a
  *Replace* that brought another chapter back under its key (Now Playing then shows that
  chapter's text). Only Stop and playing the page again bind its current text: Listen on the
  refreshed article keeps the bound session (`prepare` returns early for the same key). Options:
  `prepare` rebinds when the document differs; `advance` loads the chapter again when the staged
  session's text is no longer its page's; *Replace* stops a session on any key it gives other
  text, not only revised, dropped and merge-target keys.
