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
- A web page's title is its first listen block. `ReadabilityRunner` wraps the extracted article
  in a whole HTML document with the title as an `<h1>` (`Core/Extraction/ReadabilityRunner.swift`,
  the `wrapped` document), but `ParagraphDocument.stripLeadingTitleHeading`
  (`Core/Domain/ParagraphDocument.swift`), which is meant to drop that duplicate title, matches
  only an `<h1>` at the very start of the HTML, and the wrapped document starts with
  `<!DOCTYPE html>`. Pages from the browser and from `URLPageFetcher` get the same block, so the
  two still agree. Decide first whether the title should be spoken. Changing it renumbers the
  paragraphs of every page extracted from the web, and they are persisted (positions,
  per-paragraph audio): bump `ListenHTMLBlocks.version` and remap as
  `LibraryStore.migrateParagraphLayout` does, with a test on the wrapped document.
