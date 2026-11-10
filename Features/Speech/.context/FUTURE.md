# Speech: deferred

- `Core/TTS/TextChunker.swift`: the head-start ramp isn't guaranteed on ordinary paragraphs. A
  second or third chunk that is a whole sentence with no clause boundary inside the budget stays
  whole (e.g. 204 units after a 40-unit first chunk), so its render can outrun the audio ahead of
  it. Option: cut at the first clause past the budget (playback waits
  meanwhile; it never changes voice).
- `Features/Speech/Engines/FluidAudio/CPURoute/CPURouteBenchInputs.swift`: `KokoroCPUBenchText.long` (and its
  phonemes) is text from a third-party web novel. Replacing it means changing the Mac ORT
  benchmark's input in lockstep (501 / 190 phonemes).
- Background baking: the app registers no `BGProcessingTask`, so saved articles bake only while
  the app is open. Rebuild it around the library's queue (`PendingBakeJobStore` →
  `GlobalSynthQueue`): render saved articles overnight while the phone charges. Prepared Audio want
  the same window (`../../Prepared Audio/.context/FUTURE.md`).
- A session older than its article plays on unrecorded. Progress is written only on an article holding
  the text playing (`LibraryStore.holds`), so a session whose article has other text by then plays
  its own text to the end and records nothing: a paused session resumed after the article was
  refreshed on open, a staged next chapter a *Replace* revised, a chapter kept playing through a
  *Replace* that brought another chapter back under its key (Now Playing then shows that
  chapter's text). Only Stop and playing the article again bind its current text: Listen on the
  refreshed article keeps the bound session (`prepare` returns early for the same key). Options:
  `prepare` rebinds when the document differs; `advance` loads the chapter again when the staged
  session's text is no longer its article's; *Replace* stops a session on any key it gives other
  text, not only revised, dropped and merge-target keys.
- A web page's title, when it has one, is its first listen block. `ReadabilityRunner` wraps the
  extracted article in a whole HTML document with the title as an `<h1>`
  (`Core/Extraction/ReadabilityRunner.swift`, the `wrapped` document), but `ParagraphDocument.stripLeadingTitleHeading`
  (`Core/Domain/ParagraphDocument.swift`), which is meant to drop that duplicate title, matches
  only an `<h1>` at the very start of the HTML, and the wrapped document starts with
  `<!DOCTYPE html>`. Pages from the browser and from `URLPageFetcher` get the same block, so the
  two still agree. Decide first whether the title should be spoken. Changing it renumbers the
  paragraphs of every article extracted from the web, and they are persisted (positions,
  per-paragraph audio): bump `ListenHTMLBlocks.version` and remap as
  `LibraryStore.migrateParagraphLayout` does, with a test on the wrapped document.
- The Voice picker as a voice library: the owner's references are Speechify's Voice Library and
  iOS's Spoken Content voices. Group voices by language, with a header per language. Let a few
  chosen voices be pinned as shortcuts at the top. Once any voice needs the network, add a
  filter between voices on the device and ones that aren't: today every voice runs on the device,
  so there is nothing to filter yet.
- Other languages. Both shipped engines read English only. Options:
  - **Phonon 40m** (ptts, the same Swift API, `Phonon.Language`): `fr`, `de`, `es` and `pt`
    as one model each, or `phonon-40m-multilingual` for all five. CC BY-NC 4.0 and gated on
    Hugging Face; the owner decides on the licence before shipping it.
  - **Kokoro:** voices for Spanish (`ef_`/`em_`), French (`ff_`), Hindi (`hf_`/`hm_`),
    Italian (`if_`/`im_`), Brazilian Portuguese (`pf_`/`pm_`), Japanese (`jf_`/`jm_`) and
    Mandarin (`zf_`/`zm_`). Apache 2.0, so no licence question. The vendored FluidAudio already
    has the G2P pieces: a multilingual CharsiuG2P model (`TTS/G2P/MultilingualG2PLanguage.swift`
    maps each voice prefix to its language) and separate Mandarin and Japanese Kokoro variants
    (`KokoroAne`, `ANE-zh/`, `ANE-ja/`). The app's Kokoro route (ONNX on the CPU,
    `KokoroCPUHost`) uses English phonemes only; with it, a `zf_`/`jf_` pack speaks English in
    that voice's timbre. Wiring a language means its G2P in front of that route (or its variant),
    the provider's `supportedLanguages`, and the voices in the catalog.

  Once there are languages, the picker becomes language, then voice, with one chosen voice per
  language. For mixed-language documents, detect each paragraph's language on the device
  (`NLLanguageRecognizer`, no LLM) and play it in that language's chosen voice. This keeps "playback
  never changes the voice on its own": the user picked a voice per language. `ListenLanguage` and
  the providers' `supportedLanguages` are where it starts.
- An LLM preprocessing pass, a cloud feature: the app has no backend today. The owner's idea is
  an LLM that reads an article before it is spoken and controls how it is spoken. It would tag
  each span's language and pick the voice for it, normalise what the engines' own normalisers
  get wrong (abbreviations, numbers in context, names), and mark what to skip (captions,
  footnotes, boilerplate). Its output would be the spoken text and per-paragraph voice choices,
  feeding the same chunker and render queue. It must keep the paragraph map that positions and
  per-paragraph audio depend on. Offline, the on-device path (`NLLanguageRecognizer`, the
  engines' normalisers) stays the fallback, and offline playback must never wait on the network.
