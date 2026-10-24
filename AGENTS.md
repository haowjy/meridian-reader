# Meridian Reader

A personal iOS app for listening to (and reading) web articles: browse in the app, extract a clean
copy with Readability, save it, and listen offline with Apple TTS, Kokoro, or Phonon running on the device.
Single user, no backend. SwiftUI, SwiftData, iOS 18+, iPhone and iPad (`TARGETED_DEVICE_FAMILY` `1,2`).

iPad is a regular-width layout gated on `horizontalSizeClass == .regular`; compact chrome is unchanged. Detail: [`Features/Shell/AGENTS.md`](Features/Shell/AGENTS.md).

## Build and verify

The Xcode project is generated: edit `project.yml`, never `MeridianReader.xcodeproj` by hand. After
adding, moving or deleting a Swift file, run `xcodegen generate` and commit the regenerated project
with the change.

```sh
xcodegen generate
xcodebuild build -project MeridianReader.xcodeproj -scheme MeridianReader -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd>
xcodebuild test -project MeridianReader.xcodeproj -scheme MeridianReader \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd> \
  -collect-test-diagnostics never
```

- **A change is verified by probing the real app and an AI review.** Run it on the Simulator or
  the phone, drive the flows the change touches, look at the result (screenshots, the unified log,
  `ListenTiming`), then have the diff reviewed. Tests passing is not the evidence.
- **All automated tests together run in under 60 seconds** of sequential time on the Simulator
  (unit and UI, `test-without-building` wall clock: about 5 s and 35 s; without
  `-collect-test-diagnostics never`, xcodebuild can sit minutes in `simctl diagnose` after the
  UI tests). **Test policy (C133): critical tests only**, guarding costly regressions: the
  engine crash guard and C129 recovery (`EngineCrashGuardTests`), cache integrity (audio in the
  wrong voice never counts as prepared, `PrepareOverviewTests`), a failed save never losing
  an article (`PlayedNotSavedTests`), no text dropped from audio (`TextChunkerTests`), and one
  smoke UI test (`CoreFlowsUITests.testSaveAndPlayABrowsedArticle`). Add a test only for data
  loss, crashes, store migration or cache integrity; verify everything else on the running app.
- **Nothing gates on tests**: no git hooks, CI or merge scripts run them.
- One scheme, `MeridianReader`, with two test targets: `MeridianReaderTests` (unit, `Tests/`) and
  `MeridianReaderUITests` (`UITests/`).
- **The machine is memory-starved.** Use one Simulator, and run builds and tests under `gtimeout`.
- Probes and the UI tests drive the app with launch arguments (`App/LaunchOptions.swift`, Debug
  builds only), on the Simulator as `xcrun simctl launch <device> com.jimmyyao.Reader <args>`, on
  the phone after `--` (`xcrun devicectl device process launch … com.jimmyyao.Reader -- <args>`).
  `-uiTesting` (test markers on, still playing bars, Google suggestions off), `-resetLibrary` (an
  empty library and the stored settings cleared, as on a fresh install), `-selectEngine apple` (or
  `test.voice`, `local.kokoro`). The seeds add to that: `-seedDemoArticle` (`-seedDemoPlainText`,
  `-seedPlayedPages N`), `-seedDemoBook` (a demo book; `-seedDemoBookPlace N` puts it part-way,
  `-chainDemoChapters` plays it), `-seedDemoFolders`, `-seedBookmarks`, `-seedHistory` (visits in the browser's History). Other options:
  `-importTestEPUB` (*Import Book…* takes a synthetic EPUB instead of the Files picker;
  `-playTestEPUB` imports it at launch and plays it), `-browseTestPages` (offline `reader-test://`
  pages; page one links to an article with no title and to a story to follow, `-testStoryChapters N` lengthens its contents and
  `-testStoryThrottles` makes its chapter 6 fail once, for Follow's back-off), `-openLibrary`, `-openDemoInBrowseReader`, `-restoreSurface` (a relaunch reopens where
  the last launch left), `-failLibrarySaves` (every library save fails), `-testVoice` (an offline
  on-device test voice for prepared audio; `-selectEngine test.voice`). Keep probes and tests offline;
  use the test pages, not live sites. `LaunchOptions` parses every launch argument, the
  diagnostics' too (`-engineProbe`, `-KokoroStress`, `-kokoroUnits`; `docs/LISTEN_PLAYBACK.md` →
  "Diagnostics"); Features and the speech stack get the values from App (`AppComposition`,
  `LaunchTestHooks`), never from `LaunchOptions` or the process arguments. The exceptions are stored settings a launch overrides through UserDefaults' argument
  domain (`-reader.developerOptions YES`, `-reader.listenDebugEnabled YES`,
  `-reader.rateMultiplier 2`).
- Release must keep building: test hooks live behind `#if DEBUG`.
- Timing and speech behavior are measured on a device with a Release build (FluidAudio in Debug
  is ~3× slower). The Simulator can't reproduce the iOS 26.4+ libBNNS crash.

## Layout

| Path | What lives there |
|------|------------------|
| `App/` | `@main`, the composition root (`AppComposition`), launch work (`AppLaunch`), Debug-only launch hooks and test fixtures (`App/Fixtures/`) |
| `Core/` | No UI: `Domain` (article and paragraph values), `EPUB` (reading an `.epub` into chapters, book keys), `PDF` (PDFKit text extract into pages), `Extraction` (Readability, the listen normalizer), `Sources` (`ArticleSource`s, the book import for EPUB/PDF), `Persistence` (SwiftData; `Library/`: `Folder`, `Article`, `LibraryStore`, `LibraryQueries`, the migration; `Downloads/`: the download list and what it shows), `TTS` (chunking, render queue, audio cache; no voice-library imports), `Web` (the browser's web view, the out-of-sight fetcher and its paced `FetchQueue`), `Device` |
| `Features/` | `DesignSystem` (tokens incl. `RegularLayout`, motion, bottom chrome, the ⋯ morph, shared components with previews), `Shell` (navigation state, the ⋯ menu's content, the Now Playing bar, the iPad sidebar and clustered dock), `Library` (the Library's screens, rows, the Move tree, Favorites), `Prepared Audio` (`PrepareCenter`, the Prepared Audio list, the progress line), `Follow` (`FollowCenter`, the Follow and Following sheets, a story's status), `Browse`, `Reader`, `Saved` (the save path), `Settings` (the Settings screen, `DeveloperSettings`), `Speech` (playback, engines: `SpeechEngineProvider`, the registry and one directory per voice library) |
| `Tests/`, `UITests/` | The few unit tests (`Tests/Fakes/LibraryTestSupport.swift` builds a library) and UI flows |
| `Vendor/FluidAudio` | Vendored FluidAudio with local patches (`Vendor/FluidAudio/VENDORED.md`); Meridian Reader uses only Kokoro |
| `ptts` (SPM 0.4.0) | Gradium Phonon 31m English Core ML (`Features/Speech/Engines/Phonon/`); models download at runtime |
| `Resources/` | Readability scripts, voice previews, assets |
| `docs/` | How the app behaves and why (below) |

## Rules that cut across directories

- **`ShellState` owns navigation** (what you see): which surface shows (browser or library) and
  the Library's path and its home's tab (Everything, Favorites or Recent), the Reader sheet and what it
  sits over, whether Now Playing is up, the one other sheet (and the debug panel over it), the toast. It remembers the surface for the next launch. Views ask it;
  they don't keep their own presentation flags.
- **`PlaybackSessionState` owns what you hear**: the playing article, its position (paragraph +
  UTF-16 offset) and phase. Engines report events; the session decides. Nothing else stores or
  guesses the playing article or a playhead: every ▶ / ⏸ asks `SpeechController.playState(of:)`, the
  bar and Now Playing read `nowPlaying`, and `ListeningProgressRecorder` saves the position.
- **One save path**: `ArticleSaveCoordinator` → `LibraryStore.save`. One article per canonical URL
  (`ArticleIdentity`), app-wide. Save never restarts playback. Saving the article that is playing,
  under its own key, only marks its audio saved. Otherwise Save can move audio: under an older
  article's key when one holds the address (rekeying the live session), and, for an article that isn't
  playing, into its key from a legacy v1 cache and onto its saved text
  (`prepareListenIdentity`). Every library read
  and write goes through `LibraryStore` (lists through `LibraryQueries`); `SavedArticle` and
  `bookmarks.json` are frozen (the migration copied them; nothing writes them).
- **Screens are built from `Features/DesignSystem/`**: no ad-hoc padding, colour, radius or font
  size in feature code. Spacing and margins come from `Spacing`, corners from `Radius`, text from
  `typeStyle(_:)` (`TypeStyle`, Dynamic Type scaled), colour from `Palette` (light and dark), SF
  Symbols from `Icons` (one per concept). Shared pieces (`PlayStateButton`, `PillButton`,
  `ListRow`, `SymbolRow`, `ArtworkTile`, `NowPlayingBar`, `Sheet`, …) take plain values and
  closures, never `SpeechController`, SwiftData or `ShellState`, and carry previews in light, dark
  and the largest text size. A value the scale lacks is a token change, made there.
- **Swipe actions**: one whose row can stay in the list (it asks first, deletes what the row
  only shows, or saves a change that can fail) takes `.tint(Palette.destructive)`, never
  `role: .destructive`. The role has the List remove the row at once; the List and its data then
  disagree, and UIKit aborts on the next change ("attempt to delete item … before the update").
  Which lists an article is in is decided only in `LibraryQueries`; an action that takes a row out
  must take it out of every list there.
- **One menu per item kind** (decisions C4, DR-09): an article's (`ArticleMenu`), a folder's
  (`FolderMenu`) and a prepare's (`PrepareMenu`) are each one ordered `[MenuRow]`, drawn by every
  entry point (`MenuRows` in a ⋯ or long press, `MoreMenuPanel` in the ⋯ panel). Add or change a
  row there, never at an entry point; a place's own rows go in a block after the item's. A row
  is hidden only when it can never apply to that kind of item there, dimmed when it can't run now
  (`MenuAvailability`); no bare `if` around a menu row. Labels from `Verbs` (its case and ellipsis
  rules), symbols from `Icons`.
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
  `AppComposition`. Shared code never imports or names one, or switches on engine types: a
  library's launch steps and Listen debug panel sections come from its provider's hooks
  (`launchMigrations`, `debugSections`).
- Persisted ids and keys (engine ids, cache voice keys, UserDefaults keys, SwiftData fields) never
  change; a rename needs a migration. A stored setting's key goes in its owner's `storedKeys`
  (a voice library's in its provider's); `-resetLibrary` clears their union
  (`LaunchHooks.resetStoredSettings`).
- No real people's content in the repo: fixtures are synthetic or public domain, URLs use
  `example.com`.

## Process

Single-lane: one feature branch at a time off main → push → PR (body from the template) → merge
into main → delete the branch. No parallel worktrees. Main holds release versions.

**Merge your own PRs.** Agents merge most PRs themselves once the PR body is complete; don't wait
for approval, data changes and migrations included. Hold a PR for the owner only when it (1) touches
release steps (release workflow, signing, App Store Connect, version cuts), (2) is a large design the
owner hasn't seen, or (3) leaves its task unfinished. Judge "done" against what the owner asked for.

Work goes through PRs: write the PR body (`.github/pull_request_template.md`), write the PR's
Changes section as the technical changelog, and add `release-notes/<version>.md` when cutting a
release. The release workflow (`docs/RELEASE.md`) validates the notes file exists.

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
- `docs/TTS_ENGINES.md`: the engine registry, Apple, Kokoro, Phonon, adding an engine.
- `docs/ARTICLE_IDENTITY.md`: canonical URLs, article keys, per-paragraph audio reuse.
- `docs/TECHNICAL_SPEC.md`, `docs/FUNCTIONAL_REQUIREMENTS.md`: how it is built, what it does.
- `docs/RELEASE.md`: cutting a release, secrets, App Store Connect setup.

Directory-scoped working notes live next to the code in `<dir>/.context/CONTEXT.md` (deferred
items in `<dir>/.context/FUTURE.md`); read them before changing that directory:
`Features/Speech/.context/`, `Features/Shell/.context/`, `Features/Library/.context/`,
`Features/PreparedAudio/.context/`, `Features/Follow/.context/`, and `Core/Persistence/.context/` (deferred items only).
