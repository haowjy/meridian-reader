# Technical spec

How Meridian Reader is built. What it does: `FUNCTIONAL_REQUIREMENTS.md`; screens and gestures:
`NAVIGATION.md`; listening: `LISTEN_PLAYBACK.md`, `TTS_ENGINES.md`; article keys:
`ARTICLE_IDENTITY.md`. Build and test commands: `AGENTS.md` at the repo root.

## Constraints

- iPhone, portrait, iOS 17+. Native Swift and SwiftUI only.
- No backend, accounts or sync. Article text and audio stay on the device.
- Offline first: saved articles read and play with no network (Apple voices, or Kokoro once
  downloaded).
- Apple TTS is the default and the fallback; on-device Kokoro is optional.
- Extraction sits behind a protocol, so the engine can be swapped.

## Stack

| Layer | Choice |
|-------|--------|
| UI | SwiftUI, `@Observable` state objects; UIKit only where SwiftUI has no equivalent (edge swipe-back, web views) |
| Browser | `WKWebView` |
| Extraction | Mozilla Readability.js, bundled (`Resources/Readability/`) |
| Persistence | SwiftData, two store files: the library (`Folder`, `Page`) and the local store (`RecentVisit`; `SavedArticle`, frozen); small JSON files and UserDefaults for the rest |
| Speech | `AVSpeechSynthesizer`; Kokoro via vendored FluidAudio (`Vendor/FluidAudio`) and ONNX Runtime (SPM `onnxruntime` 1.24.2) |
| Language | `NaturalLanguage` (article language), `Speech` (address-bar dictation) |
| Project | XcodeGen (`project.yml` → `Reader.xcodeproj`) |

## Layout

```
App/        @main, composition root (AppComposition), launch work (AppLaunch), Debug-only launch hooks
Core/
  Device/       chip / OS gates
  Domain/       ReaderArticle, ParagraphDocument, ParagraphSplitter, ArticleIdentity, ReaderScrubMap
  Extraction/   ArticleExtracting, Readability runner, reader scripts
  Persistence/  SwiftData models; Library/ (Folder, Page, LibraryStore, LibraryQueries, migration); frozen legacy readers
  TTS/          chunking, render queue, audio cache, run state, engine plumbing (no library imports)
  Web/          WebView + store, URL helpers, favicons, Google suggestions
Features/
  Shell/    ShellState, bottom chrome, ⋯ morph menu, search session, motion tokens
  Browse/   start page, browser chrome, page actions (PageArticleService), dictation
  Reader/   the Reader sheet, Now Playing (text that follows the audio, scrub row, controls)
  Saved/    library surface, list, save coordinator, Now Playing's content and progress store
  Speech/   SpeechController, playback session and engines, settings, voice libraries (Engines/)
Tests/      unit tests (ReaderTests), Tests/Fakes
UITests/    UI tests (ReaderUITests)
```

## Architecture

- **Composition root.** `AppComposition` is the only place that lists voice libraries; it builds
  the `EngineRegistry`, the one `SpeechController`, the `ShellState` and the `LibraryStore`, which
  `ReaderApp` injects through the environment, and connects the speech stack to the library
  (`attachLibrary`: Now Playing's content resolver and the `ListeningProgressRecorder`).
  `AppLaunch.run` does the launch work once: the library's launch maintenance
  (`maintainLibrary`, which then lets the render queue adopt and render), with the Debug launch
  hooks before and after it, then crash resume. Views only render.
- **Navigation.** `ShellState` owns what you see: the surface (browser or library), the Reader
  sheet and what it sits over (`ReaderOrigin`), whether Now Playing is up, the one other sheet.
  It asks the playback session what you hear (`isHearing`) and stores nothing about it. Browse and the library share
  one `SearchSession` model.
- **Listening.** `SpeechController` binds an engine per utterance and derives what every screen
  shows of what you hear (`nowPlaying`, `playState(of:)`); `PlaybackSessionState` owns what you
  hear and its position; `LocalTTSCoordinator` owns the on-device engine, render queue and audio cache.
  Details in `LISTEN_PLAYBACK.md`.
- **Dependency direction.** Features → Core. Core never imports a voice library (FluidAudio and
  ONNX Runtime live in `Features/Speech/Engines/`). Features never name a concrete extractor.

## Extraction

1. The browser keeps a live `WKWebView` (`WebViewStore`). Reader mode and Save take a snapshot of
   the page's visible DOM (`ReaderVisibleSnapshot.js` drops short invisible text such as anti-copy
   lines).
2. `ReadabilityArticleExtractor` loads that HTML into an **off-screen** `WKWebView` (the page URL
   as base for web pages) with the page's JavaScript off, injects Readability.js and the
   readerable helper, and runs `new Readability(document.cloneNode(true)).parse()`, then
   normalizes the result (`ReaderNormalize.js`).
3. The address bar's reader icon and the ⋯ Reader toggle use the same
   `isProbablyReaderable` check, run after each load and same-document URL change.

Snapshot plus off-screen, rather than injecting into the visible page: the user's page is never
mutated, injected scripts don't fight the page's CSP, and content rendered by JavaScript is
already in the snapshot. That is also why the off-screen view keeps page scripts off
(`allowsContentJavaScript = false`): the snapshot's `<script>` tags and inline handlers would run
a second time, fetch, and change the DOM before Readability reads it. The app's own
`evaluateJavaScript` calls still run.

**Success and failure.** Save and the reader need a non-empty title and body. Otherwise
extraction fails with a reason the user sees, and nothing is stored (no bookmark-only save, no
raw snapshot).

**Swapping the engine.** A new type conforming to `ArticleExtracting`, set in `ReaderApp`; the
library and speech don't change. `FakeArticleExtractor` backs the Debug "Fake extraction failure"
toggle.

**Manual check.** A news article and a long blog post extract a clean title and body; a home
page (e.g. `https://example.com`) fails with a reason and saves nothing.

## Data

Two SwiftData stores in one container (`LibraryStoreConfiguration`): **library**
(`Application Support/library.store`: `Folder`, `Page`, the migration's
`LibraryMigrationReceipt`s and pending `LibraryAudioWork`) and **local**
(`Application Support/default.store`, the file the app always used: `RecentVisit`, and
`SavedArticle`, frozen). The library has its own file because an older build reopening a shared
store would drop entities it doesn't know; a file it never opens survives a rollback. Library
models are CloudKit-shaped: every property optional or defaulted, no `.unique`, relationships
optional with `.nullify`; one page per canonical URL is kept by `LibraryStore` and the launch
dedupe pass. Every library read and write goes through `LibraryStore`; lists use
`LibraryQueries`.

**`Page`** (library):

| Field | Purpose |
|-------|---------|
| `key` | Audio cache / listen key (`ARTICLE_IDENTITY.md`); copied verbatim from `SavedArticle.id` at migration, never recomputed |
| `urlString`, `canonicalURL` | The page; one page per canonical URL |
| `title`, `byline`, `excerpt`, `artworkData` | Rows, Now Playing (`byline` = site domain for web pages) |
| `contentStateRaw` | `link` (a favorite; any text is a cache) or `saved` |
| `addedAt` | When it joined the Library; nil = played without saving (kept 7 days after its last play) |
| `folder`, `folderID`, `sortKey` | Its folder (none = the pages in no folder) and order there; `folderID` mirrors the relationship for predicates |
| `bodyHTML`, `plainTextData` | Offline reading; the listen text comes from the HTML |
| `wordCount`, `paragraphCount` | Row metadata; "audio ready" compares the cache against `paragraphCount` |
| `positionParagraph`, `positionUTF16` | Resume position (paragraph + offset inside the document) |
| `lastPlayedAt`, `finishedAt` | Continue listening |
| `listenBlocksData`, `listenBlocksVersion` | Cached listen paragraphs and the layout version they were built with |
| `detectedLanguageCode` | Article language (`NLLanguageRecognizer`) |
| `locator`, `skipsInPlayback`, `fetchStateRaw` | Book chapters and series (not used yet) |

**`Folder`** (library): `name`, `kindRaw` (`plain`, `book`, `series`, `favorites`), `sortKey`,
`parent` / `children` (any depth), `pages`, `pageSortRaw`, and for books and series their details
and place (`currentPageKey`, `lastPlayedAt`, `finishedAt`). One Favorites folder holds the
bookmarks; it can't be deleted, renamed or moved below the top level.

**Migration (copy-once).** At launch `LibraryStore.migrateLegacy` copies every `SavedArticle`
row and every bookmark in `bookmarks.json` without a receipt (`LibraryMigrationReceipt`, in the
library store): saved rows become saved pages in no folder (same key, text, position, icon; the
listen history becomes `lastPlayedAt` / `finishedAt`), bookmarks become link pages in Favorites
in file order, and a bookmark for a saved page moves that page into Favorites at the bookmark's
place. The paragraph layout pass then moves copied pages on older listen blocks to today's
layout, and only then does dedupe merge duplicates, so positions and audio are compared on the
same paragraphs. The pages and a receipt for every item copied are saved together: a failed save
leaves neither, so the next launch copies again, and a page deleted after the copy never comes
back. Receipts that can't be read stop the copy. A bookmarks file that doesn't decode is logged
and left as it is: nothing is copied or recorded from it, so it is copied if it becomes readable.
Nothing legacy is written again: the rows, the
bookmarks file and the listen history stay as they were, so the previous build still works after
a rollback, and pages keep their rows' audio keys. Then the paragraph layout pass, the dedupe pass
and the prune of pages not in the Library run. Each saves on its own; a save that fails is rolled
back with the audio work it planned, so no later save can store that work against pages that
have changed since, and the next launch plans it again (dedupe waits for a layout pass that
couldn't save). Debug: `-rerunLibraryMigration` empties the library and its receipts and copies
again.

**Audio work waits for the save.** The layout pass (audio aligned to the new paragraphs, the
crash-resume point and pending renders remapped) and dedupe (the merged page's audio filling the
kept page's paragraphs it has none for, by text, then its directory and pending render dropped;
the resume point, the crash target read at launch and the live session moved onto the kept page,
at the paragraph with the same text) change nothing outside the store until the library change
is saved. They record `LibraryAudioWork` in the same save; `LibraryStore.commit` does it right
after the save. A failed save is rolled back with its work, leaving the audio cache, pending
renders and the resume point as they were. A record is retired only once its postconditions hold
on disk: the destination's saved audio index aligned with its paragraphs, every file it lists
there, the merged page's directory gone. A record that fails is kept, with everything after it,
for the next launch; so is the work of a launch that dies after the save. Meanwhile the pages
those records touch (a merge's source and destination) are held (`ArticleAudioCache.heldKeys`):
the launch's engine purges (which then run again next launch) and the prune leave their audio
alone, and their pending renders aren't adopted. The next launch does
them first, in `AppComposition.prepareAudioCache` before the first frame: before the launch
migrations and the prune of unsaved audio clean the cache, before anything reads it, and before
the engine adopts saved bake jobs (`finishAudioWork`), which waits for the rest of the launch's
maintenance too (`LISTEN_PLAYBACK.md`, Pending jobs). Replay doesn't depend on the source still
existing: the audio cache's changes are copy-on-write (`LISTEN_PLAYBACK.md`, Audio cache), so
work stopped at any step is done again from what is on disk, losing nothing. The resume point
moves only from where the work found it. Before it changes any audio, a record is checked against
the committed page: layout work for a page that holds other paragraphs now is dropped (the page's
audio is aligned with what it holds when it opens); a merge aligns the merged audio with what the
kept page holds now, and if the kept page has been deleted, leaves that audio to the cache's age
prune.

**`SavedArticle`** (local, frozen): the saved articles as stored before the library (`id`,
`urlString`, `canonicalURL`, `title`, `siteDomain`, `savedAt`, `cleanedHTML`, `plainText`,
`wordCount`, `estimatedMinutes`, `playbackParagraphIndex`, `playbackUTF16Offset`, `faviconData`,
`listenBlocksData`, `listenBlocksVersion`, `detectedLanguageCode`). Only the migration reads it.

**`RecentVisit`** (SwiftData): browser history, the last 30 top-level http(s) pages (canonical
URL, title, host, visit time, favicon), deduped by URL, recorded when a load finishes.

Elsewhere:

| What | Where |
|------|-------|
| Bookmarks before the library (frozen; copied into Favorites) | `Application Support/Bookmarks/bookmarks.json` (`LegacyBookmarks`) |
| Recent searches | UserDefaults `browse.recentSearches` |
| Last listened / finished before the library (frozen; folded into `Page`) | UserDefaults `reader.listenHistory.v1` (`ListenHistory`) |
| Crash-resume point | `ListenResumePointStore` |
| Rendered audio | `Application Support/TTSCache/<article key>/` (`ArticleAudioCache`) |
| Pending render jobs | `Application Support/PendingBakeJobs.json` |
| Timing log | `Application Support/ListenTiming/` |

## Offline

| Feature | Offline |
|---------|---------|
| Library, search, delete | Yes |
| Reading a saved article | Yes (`cleanedHTML`) |
| Listening | Yes: Apple voices; Kokoro once its model is downloaded |
| Loading pages, Save of a new page | No |
| Google suggestions, favicons | No (they quietly don't show) |

## Network use

All of it is user-initiated or for the page in view: page loads, Google search and the unofficial
Google suggest endpoint (`suggestqueries.google.com`, while typing in the address field), favicons
of visited and bookmarked sites, and the one-time Kokoro model and voice-pack downloads (Hugging
Face). No analytics.

Extracted HTML is shown as Readability returns it; there is no separate sanitizer. Readability
drops `<script>` elements but keeps inline handlers (`onerror`, `onclick`) and `javascript:`
links, so the reader's web view runs with the article's JavaScript off
(`allowsContentJavaScript = false`). Only the app's own code runs there: the bootstrap user
script and the listeners it installs (tap-to-seek through the `readerBridge` message handler),
and `evaluateJavaScript` calls for highlight and scroll (`PageScriptIsolationTests`). The visible
browser keeps JavaScript on; sites need it.
