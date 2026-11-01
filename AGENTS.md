# Meridian Reader

A personal iOS app for listening to (and reading) web articles: browse in the app, extract a clean
copy with Readability, save it, and listen offline with Phonon or Kokoro running on the device.
Single user, no backend. SwiftUI, SwiftData, iOS 18+, iPhone and iPad (`TARGETED_DEVICE_FAMILY` `1,2`).

iPad is a regular-width layout gated on `horizontalSizeClass == .regular`; compact chrome is unchanged. Detail: [`Features/Shell/AGENTS.md`](Features/Shell/AGENTS.md).

## Build and verify

The Xcode project is generated: edit `project.yml`, never `MeridianReader.xcodeproj` by hand. After
adding, moving or deleting a Swift file, run `xcodegen generate` and commit the regenerated project
with the change.

Phonon's model bundle ships in the app but is git-ignored (~170 MB): run
`tools/fetch-phonon-bundle.sh` once per checkout (it puts it at `Resources/PhononBundle/`); the
build fails without it (`docs/RELEASE.md`, "The Phonon model bundle").

```sh
tools/fetch-phonon-bundle.sh   # once per checkout
xcodegen generate
xcodebuild build -project MeridianReader.xcodeproj -scheme MeridianReader -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd>
xcodebuild test -project MeridianReader.xcodeproj -scheme MeridianReader \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd> \
  -collect-test-diagnostics never
```

The scheme runs the unit tests only; there are no UI tests (see Tests below).

- **A change is verified by probing the real app and an AI review.** Run it on the Simulator or
  the phone, drive the flows the change touches, look at the result (screenshots, the unified log,
  `ListenTiming`), then have the diff reviewed. Tests passing is not the evidence.
- **All automated tests together run in under 60 seconds** of sequential time on the Simulator
  (unit tests only, `test-without-building` wall clock: about 5 s). **Test policy (C133): critical
  tests only**, guarding costly regressions: the
  engine crash guard and C129 recovery (`EngineCrashGuardTests`), cache integrity (audio in the
  wrong voice never counts as prepared, `PrepareOverviewTests`), a failed save never losing
  an article (`PlayedNotSavedTests`), no text dropped from audio (`TextChunkerTests`), and, at the
  owner's request, the compact chrome's state, layout and scroll controller (`ChromeTests`). Add a
  test only for data loss, crashes, store migration or cache integrity; verify everything else on
  the running app.
- **No UI tests (dropped at the owner's request).** The `MeridianReaderUITests` target, `UITests/`
  and the smoke and compact chrome UI flows are gone. What they covered is now checked by hand on
  the running app (Simulator, one device; the phone for anything that needs real hardware): save
  and play a browsed article (open a page, save it, play, pause, stop); the compact chrome (scroll
  down folds the bottom chrome into its capsule on Browse web, Browse reader, Library Read and
  Library home; a scroll up of 24 pt or a tap on the bubble brings both rows back; Pages mode never
  folds; Library Edit stays expanded; Listen slides up over the chrome and a pull down closes it back to where you were (a pull pushed back
  up before release keeps it);
  Listen's floating pause pauses in full screen; an in-place reader's full screen is the text alone, its
  background to the screen's foot and its last line scrolling just clear of the home indicator's strip), with a
  recorded video and frames for the motion. Launch with the arguments below.
- **Nothing gates on tests**: no git hooks, CI or merge scripts run them.
- One scheme, `MeridianReader`, with one test target, `MeridianReaderTests` (unit, `Tests/`).
- **The machine is memory-starved.** Use one Simulator, and run builds and tests under `gtimeout`.
- Probes and manual checks drive the app with launch arguments (`App/LaunchOptions.swift`, Debug
  builds only), on the Simulator as `xcrun simctl launch <device> com.jimmyyao.Reader <args>`, on
  the phone after `--` (`xcrun devicectl device process launch … com.jimmyyao.Reader -- <args>`).
  `-uiTesting` (test markers on, still playing bars, Google suggestions off), `-resetLibrary` (an
  empty library and the stored settings cleared, as on a fresh install), `-selectEngine local.kokoro` (or
  `local.phonon`, `test.voice`). The seeds add to that: `-seedDemoArticle` (`-seedDemoPlainText`,
  `-seedPlayedPages N`), `-seedDemoBook` (a demo book; `-seedDemoBookPlace N` puts it part-way,
  `-chainDemoChapters` plays it), `-seedDemoFolders`, `-seedHistory` (visits on three sites in the browser's History, for the start page's Frequently Visited). Other options:
  `-importTestEPUB` (*Import Book…* takes a synthetic EPUB instead of the Files picker;
  `-playTestEPUB` imports it at launch and plays it), `-browseTestPages` (offline `reader-test://`
  pages; page one links to an article with no title and to a story to follow, `-testStoryChapters N` lengthens its contents and
  `-testStoryThrottles` makes its chapter 6 fail once, for Follow's back-off), `-openLibrary`, `-openLibraryFolder NAME` (the Library on that folder's screen), `-openDemoInBrowseReader` (the Browser's reader mode on the demo article), `-tapListen` (what a tap on the chrome's Listen does; `-closeListenAfter N` closes Listen N s later), `-tapLibraryRow TITLE` (what a tap on that Library row does), `-pasteText TEXT` (*Paste Text…*'s Save), `-importBook` (*Import from…*; with `-importTestEPUB` the test book), `-openSettings` (the pill's Settings; `-searchSettings TEXT` types in Search Settings, `-openSettingsPage voice` pushes a page), `-readDemoInLibrary` (Library Read on the demo article), `-restoreSurface` (a relaunch reopens where
  the last launch left), `-chromeFold P` (the compact chrome held at fold P: 0.5 one row, 1 the bubble), `-readerFullScreen` (the first reading page shown, in place or Listen, goes full screen 3 s after it opens), `-readerScrollToEnd` (that page's text goes to its end as a finger would; Listen stops following, so Jump to Audio shows), `-failLibrarySaves` (every library save fails), `-testVoice` (an offline
  on-device test voice for prepared audio; `-selectEngine test.voice`), `-renderPolicy lanes` (the
  two-lane render policy, `LanePolicy`: Phonon on the Neural Engine and the CPU at once in front;
  the app's default stays one call at a time on the CPU). Keep probes and tests offline;
  use the test pages, not live sites. `LaunchOptions` parses every launch argument, the
  diagnostics' too (`-engineProbe`, `-KokoroStress`; `docs/LISTEN_PLAYBACK.md` →
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
| `Core/` | No UI: `Domain` (article and paragraph values), `EPUB` (reading an `.epub` into chapters, book keys), `PDF` (PDFKit text extract into pages), `Extraction` (Readability, the listen normalizer), `Sources` (`ArticleSource`s, the book import for EPUB/PDF), `Persistence` (SwiftData; `Library/`: `Folder`, `Article`, `LibraryStore`, `LibraryQueries`, the migration; `PreparedAudio/`: the prepare list and what it shows), `TTS` (chunking, render queue, audio cache; no voice-library imports), `Web` (the browser's web view, the out-of-sight fetcher and its paced `FetchQueue`), `Device` |
| `Features/` | `DesignSystem` (tokens incl. `RegularLayout`, motion, bottom chrome, the ⋯ morph, shared components with previews), `Shell` (navigation state, the ⋯ menu's content, the Now Playing bar, the iPad sidebar and clustered dock, the compact chrome host), `Library` (the Library's screens, rows, the Move tree), `Prepared Audio` (`PrepareCenter`, the Prepared Audio list, the progress line), `Follow` (`FollowCenter`, the Follow and Following sheets, a story's status), `Browse`, `Reader`, `Saved` (the save path), `Settings` (the Settings screen, `DeveloperSettings`), `Speech` (playback, engines: `SpeechEngineProvider`, the registry and one directory per voice library) |
| `Tests/` | The few unit tests (`Tests/Fakes/LibraryTestSupport.swift` builds a library) |
| `Vendor/FluidAudio` | Vendored FluidAudio with local patches (`Vendor/FluidAudio/VENDORED.md`); Meridian Reader uses only Kokoro |
| `ptts` (SPM 0.6.0) | Gradium Phonon 31m English on Core ML's CPU path (`Features/Speech/Engines/Phonon/`); its model bundle ships in the app (`Resources/PhononBundle/`, fetched by `tools/fetch-phonon-bundle.sh`): our own export at a 200-token prefill, released on haowjy/xn-ptts, not upstream's 48-token one (`docs/TTS_ENGINES.md`, "Phonon") |
| `Resources/` | Readability scripts, voice previews, assets |
| `docs/` | How the app behaves and why (below) |

## Rules that cut across directories

- **`ShellState` owns navigation** (what you see): which surface shows (browser or library) and
  the Library's path and its home's tab (Library or History), the Reader sheet and what it
  sits over, whether Listen is up, the one other sheet (and the debug panel over it), the toast. It remembers the surface for the next launch. Views ask it;
  they don't keep their own presentation flags.
- **`PlaybackSessionState` owns what you hear**: the playing article, its position (paragraph +
  UTF-16 offset) and phase. Engines report events; the session decides. Nothing else stores or
  guesses the playing article or a playhead: every ▶ / ⏸ asks `SpeechController.playState(of:)`, the
  bar and Listen read `nowPlaying`, and `ListeningProgressRecorder` saves the position.
- **Playback never changes the voice on its own.** An article plays in its own voice
  (`LocalTTSCoordinator.selection(for:)`) or not at all: when that voice's engine is behind, still
  loading, fails, crashes, can't run on the device, can't run in the background, or can't read
  the article's language, playback waits or pauses and says why (`SpeechController.tell`, shown as
  the shell's toast; a stopped engine's carries Retry). No fallback to another engine or voice,
  for a paragraph or an article; prepared audio renders in that voice too. Only the user changes a
  voice (Settings › Voice, an article's or book's *Voice*). A launch migration may rewrite a stored
  voice that no longer exists.
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
  `typeStyle(_:)` (`TypeStyle`, Dynamic Type scaled), control and hit sizes from `Control` (36, the
  44 tap floor, 48, 62), symbol sizes from `Glyph` (16, 20, 26; `glyphSize(_:)` grows them with the
  text), colour from `Palette` (light and dark), SF Symbols from `Icons` (one per concept). Shared pieces (`PlayStateButton`, `PillButton` (a sheet's bar
  buttons are `SheetBarButton`, in `PillButton.swift`), `IconButton` (every round or toolbar-cell icon control), `ListRow` (its second
  line a `DetailLine`), `SymbolRow`, `ArtworkTile`, `NowPlayingBar`, `Sheet`, …) take plain values and
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
- **Nothing in the bottom lip**: no control, label or footer sits below the top of the home
  indicator's strip (the bottom safe area, 34 pt on a phone with one), where the display's rounded
  corners crowd it; only page text and its background run under it. Lay a bottom piece out in the
  safe area, or, in a view laid out through it (the in-place readers, the chrome), above the
  measured strip (`ChromeHome.inset`; on a reading page `ReadingChrome.homeIndicator`), never at a
  fixed distance from the screen's edge. The compact chrome's folded bubble (18 pt up, Safari's) is
  the one exception.
- **Motion tokens**: animations use `Motion` (`standard`, `snappy`, `settle`, `dismiss`) and its
  Reduce Motion transitions, not ad-hoc springs.
- **Bottom chrome**: compact width draws one floating chrome host
  (`Features/Shell/Chrome/ChromeHost.swift`) over three destinations (Library, Browser, Settings): row 1 the
  screen's field ending in the round Listen button, row 2 the `[Library | Browser | Settings]` pill alone, margin
  to margin; no ⋯, no Aa and no ▶ in it (a screen's ⋯ is on its title line, a system menu of its `MenuContext`; the
  Browser's is a press and hold on the field's leading glyph; the reading pages' are in their top group); two rows expanded, one, then a small glass bubble naming the page folded (the field shrunk; every piece folds straight down);
  no system tab bar (`docs/NAVIGATION.md`, "Bottom chrome"; later
  redesign PRs are under "Planned"). Regular width keeps `SurfaceBand`, the dock (with its ⋯) and the Settings sheet. Every piece is a capsule
  or circle (radius = height / 2; Safari's sizes: one 48 pt `Control.bar`, laid out by `ChromeMetrics` in `Features/DesignSystem/Chrome/`, one 8 pt gap between rows and between pieces, footprints 142, 86 (one row and the keyboard) and 58 (the bubble), hit areas at least 44; the pill runs margin to margin, as row 1 does), every control glyph
  `BottomChrome.chromeGlyph`, translucent glass with only a gradient fade behind (no opaque plate), one continuous scroll controller (`ChromeScroll`: a scroll down folds it, a scroll up of 24 pt (`revealDistance`) brings both rows back, as do the bubble's tap and the top of the text, offset <= 4). Listen is not a destination: it slides up over everything, chrome included, as a `Sheet` over the screen with a grabber and no close button, the screen behind dimmed above its rounded top (a pull down on the grabber or the card, still heading down at release closes it, back to what was under it; VoiceOver: escape), the article's title at the top of its text and its player card at its foot, Jump to Audio floating centred above the card while the text is away from the audio; its full screen is not a sheet (no top gap, rounded corners or dim: the page covers the screen; a pull does nothing there, the middle tap leaves it). Every reader's text, in Scroll mode, scrolls its end to just above whatever floats over it (card, chrome as drawn, Jump to Audio; the home indicator's strip in full screen), and the text on screen never moves as that changes. Every compact reading page (the Browser's reader mode, Library Read, Listen) has one top group (`ReadingTopGroup`, the chrome's glass and sizes): `( ⋯ ) … ( Aa ) ( ▶ Listen )` in place, `( ⋯ ) … ( Aa )` under Listen's grabber; ⋯ is the screen's menu, ▶ Listen (accent-filled) goes once the page is what you hear; it is the page's header (the title starts below it), gone in full screen, and in place it follows the fold. Library Read's field is `[(lit reader icon) site]`, the icon opening the live page. The in-place readers show no playhead (it is Listen's). The compact address pill ends
  in reload, not 🎧 (iPad keeps 🎧). Change the chrome host, never one screen; on regular width change
  `SurfaceBand`. Build controls from `BottomChrome` helpers (`bottomChromeField`,
  `fieldControlFrame`, `toolbarIconFrame`, `tapTarget`) and the toolbar layouts
  (`BottomToolbarLayout`) so sizing, Dynamic Type and 44 pt taps stay
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
Docs-only changes (`AGENTS.md`, `.context/`, `docs/`) skip the PR: commit them straight to main.

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
- `docs/TTS_ENGINES.md`: the engine registry, Phonon, Kokoro, adding an engine.
- `docs/ARTICLE_IDENTITY.md`: canonical URLs, article keys, per-paragraph audio reuse.
- `docs/TECHNICAL_SPEC.md`, `docs/FUNCTIONAL_REQUIREMENTS.md`: how it is built, what it does.
- `docs/RELEASE.md`: cutting a release, secrets, App Store Connect setup.

Directory-scoped working notes live next to the code in `<dir>/.context/CONTEXT.md` (deferred
items in `<dir>/.context/FUTURE.md`); read them before changing that directory:
`Features/Speech/.context/`, `Features/Shell/.context/`, `Features/Library/.context/`,
`Features/PreparedAudio/.context/`, `Features/Follow/.context/`, and `Core/Persistence/.context/` (deferred items only).
