# Meridian Reader

A personal iOS app for listening to (and reading) web articles: browse in the app, extract a clean
copy with Readability, save it, and listen offline with Apple TTS or Kokoro running on the device.
Single user, no backend. SwiftUI, SwiftData, iOS 17+, iPhone portrait.

## Build and test

The Xcode project is generated: edit `project.yml`, never `Reader.xcodeproj` by hand. After adding,
moving or deleting a Swift file, run `xcodegen generate` and commit the regenerated project with
the change.

```sh
xcodegen generate
xcodebuild test -project Reader.xcodeproj -scheme Reader -only-testing:ReaderTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd>
xcodebuild build -project Reader.xcodeproj -scheme Reader -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd>
```

- One scheme, `Reader`, with two test targets: `ReaderTests` (unit, `Tests/`) and `ReaderUITests`
  (`UITests/`). Use a separate `-derivedDataPath` per worktree.
- **The machine is memory-starved.** While working, run only the test classes you touched
  (`-only-testing:ReaderTests/<Class>`). Run the full `ReaderTests` once at the end, then the full
  `ReaderUITests` once, under `gtimeout`. A UI test that stalls with the app idle: rerun it alone,
  once.
- Known flake: `PlaybackRateAndChromeTests.testSpeedChangeAppliesInPlaceWithoutRestartingTheUnit`;
  rerun it alone.
- UI tests drive the app with launch arguments (`App/LaunchOptions.swift`, Debug builds only):
  `-uiTesting` (test markers on, Google suggestions off), `-seedDemoArticle`, `-browseTestPages`
  (offline `reader-test://` pages), `-selectEngine apple`. Keep UI tests offline; use the test
  pages, not live sites.
- `ScreenshotCaptureTests` is skipped unless `TEST_RUNNER_READER_SCREENSHOTS_DIR=<dir>` is set in
  xcodebuild's environment.
- `KokoroNaNProbeTests` and `KokoroONNXSessionTests` run only when the Mac research model is at
  `~/Developer/tts-audition/bg-research/models/`; otherwise they skip.
- Release must keep building: test hooks live behind `#if DEBUG`.
- Timing and speech behavior are measured on a device with a Release build (FluidAudio in Debug
  is ~3× slower). The Simulator can't reproduce the iOS 26.4+ libBNNS crash.

## Layout

| Path | What lives there |
|------|------------------|
| `App/` | `@main`, the composition root (`AppComposition`), launch work (`AppLaunch`), Debug-only launch hooks |
| `Core/` | No UI: `Domain` (article and paragraph values), `Extraction`, `Persistence` (SwiftData, `ArticleLibrary`), `TTS` (chunking, render queue, audio cache; no voice-library imports), `Web`, `Device` |
| `Features/` | `Shell` (navigation state, bottom chrome, ⋯ menu, motion), `Browse`, `Reader`, `Saved`, `Speech` (playback, engines, settings) |
| `Tests/`, `UITests/` | Unit tests (fakes in `Tests/Fakes/`), UI tests |
| `Vendor/FluidAudio` | Vendored FluidAudio with local patches (`Vendor/FluidAudio/VENDORED.md`); Reader uses only Kokoro |
| `Resources/` | Readability scripts, voice previews, assets |
| `docs/` | How the app behaves and why (below) |

## Rules that cut across directories

- **`ShellState` owns navigation**: which surface shows (browser or library), the one sheet,
  the reader overlay and where it was opened from. Views ask it; they don't keep their own
  presentation flags.
- **`PlaybackSessionState` owns the listening position** (paragraph + UTF-16 offset) and phase.
  Engines report events; the session decides. Nothing else stores or guesses a playhead.
- **One save path**: `ArticleSaveCoordinator` → `ArticleLibrary.save`. One article per
  canonical URL (`ArticleIdentity`); Save never moves audio or restarts playback.
- **Motion tokens**: animations use `Motion` (`standard`, `snappy`, `settle`, `dismiss`) and its
  Reduce Motion transitions, not ad-hoc springs.
- **Bottom chrome**: build controls from `BottomChrome` helpers (`bottomChromeField`,
  `fieldControlFrame`, `toolbarIconFrame`, `tapTarget`) so sizing, Dynamic Type and 44 pt taps stay
  consistent.
- **Voice libraries stay in `Features/Speech/Engines/<Library>/`**, registered in
  `AppComposition`. Shared code never imports one or switches on engine types.
- Persisted ids and keys (engine ids, cache voice keys, UserDefaults keys, SwiftData fields) never
  change; a rename needs a migration.
- No real people's content in the repo: fixtures are synthetic or public domain, URLs use
  `example.com`.
- `BackgroundAudioBakeScheduler` and its `BGProcessingTask` are an open product decision: don't
  change them without asking.

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
`Features/Speech/.context/`, `Features/Shell/.context/`.
