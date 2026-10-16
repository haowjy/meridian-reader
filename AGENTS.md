# Meridian Reader

A personal iOS app for listening to (and reading) web articles: browse in the app, extract a clean
copy with Readability, save it, and listen offline with Apple TTS or Kokoro running on the device.
Single user, no backend. SwiftUI, SwiftData, iOS 17+, iPhone portrait.

## Build and test

The Xcode project is generated: edit `project.yml`, never `MeridianReader.xcodeproj` by hand. After
adding, moving or deleting a Swift file, run `xcodegen generate` and commit the regenerated project
with the change.

```sh
xcodegen generate
xcodebuild test -project MeridianReader.xcodeproj -scheme MeridianReader \
  -only-testing:MeridianReaderTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd>
xcodebuild build -project MeridianReader.xcodeproj -scheme MeridianReader -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd>
```

- One scheme, `MeridianReader`, with two test targets: `MeridianReaderTests` (unit, `Tests/`) and
  `MeridianReaderUITests` (`UITests/`). Use a separate `-derivedDataPath` per worktree.
- **The machine is memory-starved.** While working, run only the test classes you touched
  (`-only-testing:MeridianReaderTests/<Class>`). Run the full `MeridianReaderTests` once at the end,
  then the full `MeridianReaderUITests` once, under `gtimeout`. A UI test that stalls with the app
  idle: rerun it alone, once.
- Known flake: `PlaybackRateAndChromeTests.testSpeedChangeAppliesInPlaceWithoutRestartingTheUnit`;
  rerun it alone.
- UI tests drive the app with launch arguments (`App/LaunchOptions.swift`, Debug builds only):
  `-uiTesting` (test markers on, Google suggestions off), `-seedDemoArticle`, `-seedDemoBook`
  (a demo book; `-chainDemoChapters` plays it), `-importTestEPUB` (*Import Book…* takes a
  synthetic EPUB instead of the Files picker; `-playTestEPUB` imports it at launch and plays it), `-pickTestCover` (*Edit Details*' *Choose from
  Files* takes a synthetic picture), `-browseTestPages` (offline `reader-test://` pages),
  `-selectEngine apple`, `-testVoice` (an offline on-device test voice for downloads; `-selectEngine
  test.voice`), `-resetDownloads`. Keep UI tests offline; use the test pages, not live sites.
  `LaunchOptions` parses every launch argument, the diagnostics' too (`-engineProbe`,
  `-KokoroStress`, `-kokoroUnits`; `docs/LISTEN_PLAYBACK.md` → "Diagnostics"); the speech stack
  gets the values from `AppComposition`, never from the process arguments.
- `ScreenshotCaptureTests` is skipped unless `TEST_RUNNER_READER_SCREENSHOTS_DIR=<dir>` is set in
  xcodebuild's environment.
- `KokoroNaNProbeTests` and `KokoroONNXSessionTests` run only when the Mac research model is at
  `~/Developer/tts-audition/bg-research/models/`; otherwise they skip. `KokoroONNXThreadSweepTests`
  also needs `TEST_RUNNER_READER_ONNX_SWEEP=1`: it prints × real time per ONNX thread count on the
  Mac's CPU (a proxy; measure the phone with the CPU route benchmark).
- `EPUBLocalBooksTests` is skipped unless `TEST_RUNNER_READER_EPUB_DIR=<dir>` is set: it reads every
  `.epub` there (real books stay out of the repo) and writes `<dir>/epub-report.txt`.
- Release must keep building: test hooks live behind `#if DEBUG`.
- Timing and speech behavior are measured on a device with a Release build (FluidAudio in Debug
  is ~3× slower). The Simulator can't reproduce the iOS 26.4+ libBNNS crash.

## Layout

| Path | What lives there |
|------|------------------|
| `App/` | `@main`, the composition root (`AppComposition`), launch work (`AppLaunch`), Debug-only launch hooks |
| `Core/` | No UI: `Domain` (article and paragraph values), `EPUB` (reading an `.epub` into chapters, book keys), `Extraction` (Readability, the listen normalizer), `Sources` (`PageSource`s, the book import), `Persistence` (SwiftData; `Library/`: `Folder`, `Page`, `LibraryStore`, `LibraryQueries`, the migration; `Downloads/`: the download list and what it shows), `TTS` (chunking, render queue, audio cache; no voice-library imports), `Web`, `Device` |
| `Features/` | `DesignSystem` (tokens, motion, bottom chrome, the ⋯ morph, shared components with previews), `Shell` (navigation state, the ⋯ menu's content, the Now Playing bar), `Library` (the Library's screens, rows, the Move tree, Favorites), `Downloads` (`DownloadCenter`, the Downloads list, the progress line), `Browse`, `Reader`, `Saved` (the save path), `Speech` (playback, engines, settings) |
| `Tests/`, `UITests/` | Unit tests (fakes in `Tests/Fakes/`), UI tests |
| `Vendor/FluidAudio` | Vendored FluidAudio with local patches (`Vendor/FluidAudio/VENDORED.md`); Meridian Reader uses only Kokoro |
| `Resources/` | Readability scripts, voice previews, assets |
| `docs/` | How the app behaves and why (below) |

## Rules that cut across directories

- **`ShellState` owns navigation** (what you see): which surface shows (browser or library) and
  the Library's path and its home's tab (Everything or Favorites), the Reader sheet and what it
  sits over, whether Now Playing is up, the one other sheet (and the debug panel over it), the toast. It remembers the surface for the next launch. Views ask it;
  they don't keep their own presentation flags.
- **`PlaybackSessionState` owns what you hear**: the playing page, its position (paragraph +
  UTF-16 offset) and phase. Engines report events; the session decides. Nothing else stores or
  guesses the playing page or a playhead: every ▶ / ⏸ asks `SpeechController.playState(of:)`, the
  bar and Now Playing read `nowPlaying`, and `ListeningProgressRecorder` saves the position.
- **One save path**: `ArticleSaveCoordinator` → `LibraryStore.save`. One page per canonical URL
  (`ArticleIdentity`), app-wide. Save never restarts playback. Saving the page that is playing,
  under its own key, only marks its audio saved. Otherwise Save can move audio: under an older
  page's key when one holds the address (rekeying the live session), and, for a page that isn't
  playing, into its key from a legacy v1 cache and onto its saved text
  (`prepareListenIdentity`). Every library read
  and write goes through `LibraryStore` (lists through `LibraryQueries`); `SavedArticle` and
  `bookmarks.json` are frozen (the migration copied them; nothing writes them).
- **Screens are built from `Features/DesignSystem/`**: no ad-hoc padding, colour, radius or font
  size in feature code. Spacing and margins come from `Spacing`, corners from `Radius`, text from
  `typeStyle(_:)` (`TypeStyle`, Dynamic Type scaled), colour from `Palette` (light and dark), SF
  Symbols from `Icons` (one per concept). Shared
  pieces (`PlayStateButton`, `PillButton`, `ListRow`, `NowPlayingBar`, `Sheet`, …) take plain values
  and closures, never `SpeechController`, SwiftData or `ShellState`, and carry previews in light,
  dark and the largest text size. A value the scale lacks is a token change, made there.
- **Swipe actions**: one whose row can stay in the list (it asks first, deletes what the row
  only shows, or saves a change that can fail) takes `.tint(Palette.destructive)`, never
  `role: .destructive`. The role has the List remove the row at once; the List and its data then
  disagree, and UIKit aborts on the next change ("attempt to delete item … before the update").
  Which lists a page is in is decided only in `LibraryQueries`; an action that takes a row out
  must take it out of every list there.
- **Button rows never wrap** (decision D21): two or more buttons side by side go in an
  `ActionButtonRow`, which falls back from full labels to short titles, then no details, then
  symbols alone. Give every button in one a symbol.
- **Motion tokens**: animations use `Motion` (`standard`, `snappy`, `settle`, `dismiss`) and its
  Reduce Motion transitions, not ad-hoc springs.
- **Bottom chrome**: build controls from `BottomChrome` helpers (`bottomChromeField`,
  `fieldControlFrame`, `toolbarIconFrame`, `tapTarget`) and the toolbar layouts
  (`BottomToolbarLayout`, `BottomToolbarSpanLayout`) so sizing, Dynamic Type and 44 pt taps stay
  consistent.
- **Voice libraries stay in `Features/Speech/Engines/<Library>/`**, registered in
  `AppComposition`. Shared code never imports one or switches on engine types.
- Persisted ids and keys (engine ids, cache voice keys, UserDefaults keys, SwiftData fields) never
  change; a rename needs a migration.
- No real people's content in the repo: fixtures are synthetic or public domain, URLs use
  `example.com`.

## Writing

- Comments state current truth and the non-obvious why. No history ("used to", "formerly"), no
  design-round codenames, no review-finding ids.
- `docs/` describes shipped behavior only; update the affected sentences in the same commit as the
  change.
- Keep files under ~1,000 lines; split by responsibility.
- Delete rather than wrap: no compatibility shims or "kept for old callers" code.

## Docs and deeper context

- `docs/NAVIGATION.md`: screens, gestures, bottom chrome, the reader UI.
- `docs/LISTEN_PLAYBACK.md`: playback session, engines at runtime, render queue, chunking, audio
  cache, background listening, diagnostics.
- `docs/TTS_ENGINES.md`: the engine registry, Apple, Kokoro routes, adding an engine.
- `docs/ARTICLE_IDENTITY.md`: canonical URLs, article keys, per-paragraph audio reuse.
- `docs/TECHNICAL_SPEC.md`, `docs/FUNCTIONAL_REQUIREMENTS.md`: how it is built, what it does.

Directory-scoped working notes live next to the code in `<dir>/.context/CONTEXT.md` (deferred
items in `<dir>/.context/FUTURE.md`); read them before changing that directory:
`Features/Speech/.context/`, `Features/Shell/.context/`, `Features/Library/.context/`,
`Features/Downloads/.context/`.
