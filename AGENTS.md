# Meridian Reader

A personal iOS app for listening to, and reading, web articles, serials and books: browse in the
app, extract a clean copy with Readability, save it, and listen offline with Phonon or Kokoro
running on the device. SwiftUI, SwiftData, iOS 18+, iPhone and iPad. No backend.

Read a directory's `AGENTS.md` and `.context/` before changing it; deferred work sits in its
`.context/FUTURE.md`.

## Who It's For

- **The listener.** One person, often with the screen off and away from a network, listening to
  long text in a voice they chose. The app also ships free on the App Store, collects nothing, and
  has no account.

## Invariants

These hold however the code changes; changing one is the owner's call, proposed as its own step.
How the code keeps each, what checks it and where it falls short:
[.context/invariants.md](.context/invariants.md).

- **Closing a screen never stops audio.** Pulling Listen down, leaving a reader or switching
  destination leaves playback running: reading and hearing are separate, and looking at something
  else must not end what you are listening to.
- **An article plays in one voice.** Playback never plays audio rendered in another voice, so a
  listen never changes voice paragraph by paragraph.
- **Playback never changes the voice on its own.** When the article's voice can't go on (behind,
  loading, failed, crashed, can't run here, in the background or in this language), playback waits
  or pauses and says why; no fallback to another engine or voice. Only the user changes a voice. A
  different voice mid-listen is jarring.
- **Saved text and on-device voices work with no network.** Phonon from the first launch, Kokoro
  once its model has downloaded: the app is for listening offline.
- **A navigation gesture does exactly what its button does.** ‹ is a push with an edge
  swipe-back; ✕ or a grabber is a pull down. Otherwise one intent behaves two ways
  (`docs/NAVIGATION.md`, its top rule).
- **No system tab bar.** The bottom chrome is the app's own.

## Build and Verify

The Xcode project is generated: edit `project.yml`, never `MeridianReader.xcodeproj`. After adding,
moving or deleting a Swift file, run `xcodegen generate` and commit the regenerated project with
the change. Phonon's model bundle (~170 MB) is git-ignored and the build fails without it.

```sh
tools/fetch-phonon-bundle.sh   # once per checkout: Resources/PhononBundle/
xcodegen generate
xcodebuild build -project MeridianReader.xcodeproj -scheme MeridianReader -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd>
xcodebuild test -project MeridianReader.xcodeproj -scheme MeridianReader \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd> \
  -collect-test-diagnostics never
```

- **A change is verified by probing the real app and an AI review**, not by tests passing: run it
  on the Simulator or the phone, drive the flows it touches, look at the result (screenshots, the
  unified log, `ListenTiming`), then have the diff reviewed. What to check by hand, and the launch
  arguments that seed and drive the app: [.context/verifying.md](.context/verifying.md).
- **Critical tests only.** The unit tests (`Tests/`, about 5 s) guard costly regressions. Add one
  only for data loss, crashes, store migration or cache integrity. There are no UI tests, and
  nothing gates on tests.
- **The machine is memory-starved.** Use one Simulator; run builds and tests under `gtimeout`.
- Test hooks live behind `#if DEBUG`; Release must keep building.
- Measure timing and speech on a device with a Release build (FluidAudio in Debug is ~3× slower).
  The Simulator can't reproduce the iOS 26.4+ libBNNS crash.

## Where Things Live

`App/` is the composition root (`AppComposition`) and Debug-only launch hooks; `Core/` has no UI;
`Features/` holds the screens and the speech stack. Places that mislead:

- `Vendor/FluidAudio` is vendored with local patches (`Vendor/FluidAudio/VENDORED.md`); only its
  Kokoro is used.
- Phonon's bundle is our own export at a 200-token prefill, released on haowjy/xn-ptts, not
  upstream's 48-token one (`docs/TTS_ENGINES.md`, "Phonon").
- `SavedArticle` and `bookmarks.json` are frozen: a migration copied them and nothing writes them.
- Features and the speech stack get launch-argument values from App (`AppComposition`,
  `LaunchTestHooks`), never from `LaunchOptions` or the process arguments.

## Rules That Cut Across Directories

- **`ShellState` owns what you see**: surface, the Library's path and tab, the Reader and what it
  sits over, whether Listen is up, the one other sheet, the toast. Views ask it; they keep no
  presentation flags of their own.
- **`PlaybackSessionState` owns what you hear**: the playing article, its position (paragraph +
  UTF-16 offset) and phase. Engines report events; the session decides. Every ▶ / ⏸ asks
  `SpeechController.playState(of:)`, the bar and Listen read `nowPlaying`, and
  `ListeningProgressRecorder` saves the position; nothing else stores or guesses a playhead.
- **One save path**: `ArticleSaveCoordinator` → `LibraryStore.save`, one article per canonical URL
  (`ArticleIdentity`). Save never restarts playback; it may move audio between keys
  (`docs/ARTICLE_IDENTITY.md`). Every library read and write goes through `LibraryStore`, lists
  through `LibraryQueries`.
- **Screens are built from `Features/DesignSystem/`**: no ad-hoc padding, colour, radius, font
  size, symbol or animation in feature code. A value the scale lacks is a token change, made there.
  Shared components take plain values and closures, never `SpeechController`, SwiftData or
  `ShellState`, and carry previews in light, dark and the largest text size.
- **Swipe actions**: one whose row can stay in the list (it asks first, deletes what the row only
  shows, or saves a change that can fail) takes `.tint(Palette.destructive)`, never
  `role: .destructive`. The role has the List remove the row at once; the List and its data then
  disagree and UIKit aborts on the next change. Which lists an article is in is decided only in
  `LibraryQueries`; an action that takes a row out must take it out of every list there.
- **One menu per item kind**: `ArticleMenu`, `FolderMenu`, `PrepareMenu`, each one ordered
  `[MenuRow]` drawn by every entry point. Change rows there, never at an entry point. A row is
  hidden only when it can never apply, dimmed when it can't run now (`MenuAvailability`); no bare
  `if` around a row. Labels from `Verbs`. Detail: `docs/MENUS.md`.
- **Button rows never wrap**: two or more buttons side by side go in an `ActionButtonRow`, and
  every button in one has a symbol.
- **Nothing in the bottom lip**: no control or label below the top of the home indicator's strip.
  Lay a bottom piece out in the safe area, or above the measured strip (`ChromeHome.inset`;
  `ReadingChrome.homeIndicator` on a reading page), never at a fixed distance from the screen's
  edge. The folded chrome bubble is the one exception.
- **Compact width has one chrome host** over Library, Browser and Settings; Listen slides up over
  it. Change the host, never one screen; on regular width change `SurfaceBand`. Rules:
  [Features/Shell/AGENTS.md](Features/Shell/AGENTS.md); the user-visible spec:
  `docs/NAVIGATION.md`, "Bottom chrome".
- **Voice libraries stay in `Features/Speech/Engines/<Library>/`**, registered in
  `AppComposition`. Shared code never imports or names one or switches on engine types; a
  library's launch steps and debug sections come from its provider's hooks (`launchMigrations`,
  `debugSections`).
- **Persisted ids and keys** (engine ids, cache voice keys, UserDefaults keys, SwiftData fields)
  never change; a rename needs a migration. A stored setting's key goes in its owner's
  `storedKeys`, so `-resetLibrary` clears it.
- No real people's content in the repo: fixtures are synthetic or public domain, URLs use
  `example.com`.

## How Work Lands

One feature branch at a time off main, no parallel worktrees: branch → push → PR from
`.github/pull_request_template.md`, its Changes section the technical changelog → merge → delete
the branch. Main holds release versions; a release adds `release-notes/<version>.md`
(`docs/RELEASE.md`).

Merge your own PR once its body is complete, data changes and migrations included. Hold it for the
owner only when it touches release steps (release workflow, signing, App Store Connect, version
cuts), is a large design the owner hasn't seen, or leaves its task unfinished. Docs-only changes
(`AGENTS.md`, `.context/`, `docs/`) skip the PR and go straight to main.

The repo is public: every push publishes. Before pushing, check the commits for secrets and private
content (keys, tokens, signing material, absolute home paths); if any is there, stop and tell the
owner.

## Writing

- Comments state current truth and the non-obvious why: no history, design-round codenames or
  review-finding ids.
- `docs/` describes shipped behavior only; update the affected sentences in the same commit as the
  change.
- Keep files under ~1,000 lines; split by responsibility. Delete rather than wrap: no
  compatibility shims.
