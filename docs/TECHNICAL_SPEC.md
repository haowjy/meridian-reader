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
  Domain/       ReaderArticle, PageOrigin, ParagraphDocument, ParagraphSplitter, ArticleIdentity, ReaderScrubMap
  EPUB/         EPUB reading: zip container, package, contents, chapter cutting, BookIdentity
  Extraction/   ArticleExtracting, Readability runner, ListenContentNormalizer, reader scripts
  Sources/      PageSource (SingleWebPageSource, EPUBSource), BookImporter, chapter settling, cover thumbnails, Imports/ files
  Persistence/  SwiftData models; Library/ (Folder, Page, LibraryStore, LibraryQueries, migration); frozen legacy readers
  TTS/          chunking, render queue, audio cache, run state, engine plumbing (no library imports)
  Web/          WebView + store, URL helpers, favicons, Google suggestions
Features/
  Shell/    ShellState, bottom chrome, ⋯ morph menu, search session, motion tokens
  Browse/   start page, browser chrome, page actions (PageArticleService), dictation
  Reader/   the Reader sheet, Now Playing (text that follows the audio, scrub row, controls)
  Library/  the Library surface and screens (home, folder, book), rows, the Move tree, Favorites' sheet and ☆, the import sheet
  Saved/    save coordinator, Now Playing's content and progress store
  Speech/   SpeechController, playback session and engines, settings, voice libraries (Engines/)
Tests/      unit tests (ReaderTests), Tests/Fakes
UITests/    UI tests (ReaderUITests)
```

## Architecture

- **Composition root.** `AppComposition` is the only place that lists voice libraries; it builds
  the `EngineRegistry`, the one `SpeechController`, the `ShellState` and the `LibraryStore`, which
  `ReaderApp` injects through the environment, and connects the speech stack to the library
  (`attachLibrary`: the library resolves Now Playing's text, and the `ListeningProgressRecorder`
  writes listening progress to it).
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
   the page's visible DOM (`PageSnapshot`: `ReaderVisibleSnapshot.js` drops short invisible text
   such as anti-copy lines).
2. `ReadabilityArticleExtractor` loads that HTML into an **off-screen** `WKWebView`
   (`OffscreenWebView`; the page URL as base for web pages) with the page's JavaScript off,
   injects Readability.js and the readerable helper, and runs
   `new Readability(document.cloneNode(true)).parse()`. `ListenContentNormalizer` then runs
   `ReaderNormalize.js` on the result in the same web view, so every piece of readable text sits
   in a listen block (loose text in a `<div>`, lines between `<br><br>`, the lead-in of a list
   item or quote holding blocks). The browser's page reaches the Reader, 🎧 and Save as a
   `SingleWebPageSource`: one page in no folder, its content normalized like every source's.
3. The address bar's reader icon and the ⋯ Reader toggle use the same
   `isProbablyReaderable` check, run after each load and same-document URL change.

**Fetching a page out of sight** (`URLPageFetcher`; nothing reaches it yet but the Debug hook
`-probeLockedFetch`): a fresh `WKWebView` the size of the app's window, placed off its left edge
(the page lays out at the browser's width, in a view WebKit counts as on screen), with the
browser's cookies (the default website data store) and page scripts off. It
loads the page, takes the same snapshot and extracts it through `SingleWebPageSource`, so a page
reads the same as from the browser (`URLPageFetcherTests`). Loading, the snapshot and extraction
each give up after a time limit, since WebKit's processes can be suspended in the background.

Snapshot plus off-screen, rather than injecting into the visible page: the user's page is never
mutated, injected scripts don't fight the page's CSP, and content rendered by JavaScript is
already in the snapshot. That is also why the off-screen view keeps page scripts off
(`allowsContentJavaScript = false`): the snapshot's `<script>` tags and inline handlers would run
a second time, fetch, and change the DOM before Readability reads it. The app's own
`evaluateJavaScript` calls still run.

**Success and failure.** Save and the reader need a non-empty title and body. Otherwise
extraction fails with a reason the user sees, and nothing is stored (no bookmark-only save, no
raw snapshot).

**Book chapters** skip Readability: each chapter's XHTML goes through the normalizer alone, in
one reused off-screen web view holding a blank standards-mode page, after `ReaderBookChapter.js`
takes out pictures, embedded media, footnote asides, note references and links back from notes,
and unwraps links (parsed in an inert document, so nothing loads). A book's endnotes stay, on
their own back-matter page. See "Book import" below.

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
`LibraryQueries`. An edit someone asks for (a save, including one into a folder; a move; a
folder made, renamed, sorted or reordered; a mark; a remove of one or several pages, an unsave or
a delete; a favorite added, renamed or removed; a book imported or replaced) is one save, made at
once (`LibraryStore.edit`): a save SwiftData refuses is rolled back (`rollBack`, which fetches the
models it touched again, so the screens' models read the stored values, relationships included)
and throws `LibraryStoreError.saveFailed`. So a failed edit never shows as done, and never waits
in the context for a later save to store or a later rollback to drop. The rollback drops every
other change still unsaved too, except listening progress: `LibraryStore` keeps what playback
wrote and hasn't stored (`PendingListening`) and writes it again after the rollback, making again
a page only a play had made, so the next save stores it while the edit stays undone. It is written
again only on a page holding the text it was made in (`LibraryStore.holds`), as playback writes
it only on a page holding the text playing (`LISTEN_PLAYBACK.md`). Nothing is
saved while an edit is being staged: deleting the playing page stops it, and the position
stopping records waits for the delete's save instead of storing the delete half made. The screens
run these through `ShellState.attempt`, which shows the failure as a toast (the import sheet
shows a failed import or *Replace* as its one-line failure); what follows success (Edit's
selection cleared, a moved folder's screen following it, the Move tree closed, "Added to
Favorites", a saved article's audio moved under the page's key when that is an older key, and
baked ahead in `ArticleSaveCoordinator`, an imported book's screen) runs only after it.

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
| `lastPlayedAt`, `finishedAt` | Continue, and a row's "✓ Finished" |
| `listenBlocksData`, `listenBlocksVersion` | Cached listen paragraphs and the layout version they were built with |
| `detectedLanguageCode` | Article language (`NLLanguageRecognizer`) |
| `skipsInPlayback`, `fetchStateRaw` | Book chapters and series: what playback carries on to (`ChapterAdvance`, `LISTEN_PLAYBACK.md`) |
| `locator` | Book chapters: where the chapter starts in the book, `href#fragment` |

**`Folder`** (library): `name`, `kindRaw` (`plain`, `book`, `series`, `favorites`), `sortKey`,
`parent` / `children` (any depth), `pages`, `pageSortRaw`, and for books and series their details
(`byline`, `coverData`, `sourceIdentifier`, `sourceStateData`, `languageCode`) and place
(`currentPageKey`, `lastPlayedAt`, `finishedAt`, written as their chapters play). One
Favorites folder holds the bookmarks; it can't be deleted, renamed or moved below the top level.

**Book import** (`BookImporter`, run for the import sheet by `BookImportFlow`):
0. The file is the import's own copy in `Application Support/Imports/<uuid>/<name>.epub`
   (`BookImportFiles`): a picked file is copied there under its security-scoped access, and an
   `.epub` link is downloaded there (`WKDownload`: a main-frame response served as
   `application/epub+zip`, or named `.epub` and not a web page). The copy is deleted when the
   import ends, however it ends; launch clears what a killed import left.
1. `EPUBBookReader` reads and cuts the file off the main thread: DRM and fixed layout are
   refused, then the package, the contents and every spine file are read and cut at contents
   anchors, choosing the depth per branch; front and back matter are flagged.
2. Each chapter is normalized, one at a time, in one hidden web view (above). Progress is a value
   (`BookImportProgress`: reading, chapters prepared of all of them, storing). Cancelling the
   importing task stops it between chapters and before anything is stored, keeping nothing.
3. The chapters are settled on their listen blocks (`BookChapterFinalizer`) before any key is
   kept: a chapter with nothing to read is dropped; a book with no body chapter left plays every
   chapter; a body chapter under 100 words joins the body chapter after it, else the one before,
   within 30,000 words; a body chapter still over 30,000 words makes the book be cut again with a
   lower cap, at most three cuts. An untitled chapter is named by its first words.
4. Before anything is stored, the chapters are held to the size policy on the listen blocks that
   will be stored (`BookChapterFinalizer.check`): a book with nothing left to read is refused as
   unreadable; a body chapter still over 30,000 words after the last cut, or one under 100 that a
   neighbouring body chapter could take, is refused as text that couldn't be prepared. A body
   chapter under 100 words stays only where no body neighbour can take it within 30,000: its
   neighbours are full, or it has none (a book under 100 words, a short section between skipped
   matter). Skipped chapters may be any length.
5. `LibraryStore.addBook` stores one `Folder(kind: .book)` (title, authors, a 600 px cover
   thumbnail, language, the book key as `sourceIdentifier`, the file's SHA-256 in
   `sourceStateData`) at the destination, looked up again then (a destination deleted while the
   book was read fails the import), with one saved page per chapter in order (key
   `BookIdentity.chapterKey`, front matter `skipsInPlayback`), all in one save: a failed save
   keeps nothing.
6. A book already in the Library (same book key) is left alone, or, with *Replace* (D13),
   rebuilt in the same folder by `LibraryStore.replaceBook` (`ARTICLE_IDENTITY.md`), in one
   save; a dropped chapter's audio goes only once that save succeeds.

Refusals and failures are `BookImportError`s whose messages the sheet shows as they are (DRM,
fixed layout, over `EPUBLimits`' caps, unreadable). Once the file is read, the importer hands the
sheet a `BookImportPreview` (title, authors, cover thumbnail, chapter titles, what is skipped).
The importer takes *Add to* as a folder id it reads again in its save, so a change while the
book is read and prepared is stored in that one save; from *Saving the book…* on it can't change,
and a folder chosen and then deleted fails the import (`destinationGone`). One import sheet is up
at a time: a book arriving while one is (a second download finishing) is discarded with a toast,
and a flow closes and lands only its own sheet (`ShellState.closeImport`). D13's *Cancel* is the importer's `.cancel` choice: it
stops right after reading, and the sheet asks, then runs again with `.replace` on the same copy.

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

**Audio work waits for the save.** Deleting pages (a row's *Delete*, *Delete Folder and
Contents*, *Delete Book*: the page's audio directory, pending render and queued renders go,
unless a page with its key exists again by then), pages leaving the Library (*Remove from
Library*, unsave: the audio is kept, back on the ephemeral TTL), Save (the audio marked saved and
its queued render non-ephemeral), the layout pass (audio aligned to the new
paragraphs, the crash-resume point and pending renders remapped), dedupe (the merged page's audio filling the
kept page's paragraphs it has none for, by text, then its directory and pending render dropped;
the resume point, the crash target read at launch and the live session moved onto the kept page,
at the paragraph with the same text) and a book's *Replace* (edited chapters aligned, chapters
found by their text merged, and a dropped chapter's audio, pending render and queued renders
deleted) change nothing outside the store until the library change is saved. They record `LibraryAudioWork` in the same save; `LibraryStore.commit` does it right
after the save. A failed save is rolled back with its work, leaving the audio cache, pending
renders and the resume point as they were. A record is retired only once its postconditions hold
on disk: the destination's saved audio index aligned with its paragraphs, every file it lists
there, the merged page's directory gone, a deleted page's audio gone, and otherwise the audio
saved or ephemeral as its page is. Delete, remove and Save records act on the page holding the key
when they run, not as it was planned: by then the key can belong to a later page (saved, deleted,
then played again without saving), whose audio stays, saved only if that page is saved in the
Library. A record that fails is kept, with everything after it,
for the next launch; so is the work of a launch that dies after the save. Meanwhile the pages
those records touch (a merge's source and destination, a deleted page) are held (`ArticleAudioCache.held`):
the launch's engine purges (which then run again next launch) and the prune leave their audio
alone, their pending renders aren't adopted, and a book's playback neither stages them as the
next chapter nor trims them behind its place (D7). Records that can't be read hold all audio this
way (logged as `library_audio_work_unreadable`) until a run of the work reads them. The next
launch does them first, in `AppComposition.prepareAudioCache` before the first frame: before the
launch migrations and the prune of unsaved audio clean the cache, before anything reads it, and
before the engine adopts saved bake jobs (`finishAudioWork`), which waits for the rest of the launch's
maintenance too (`LISTEN_PLAYBACK.md`, Pending jobs). Replay doesn't depend on the source still
existing: the audio cache's changes are copy-on-write (`LISTEN_PLAYBACK.md`, Audio cache), so
work stopped at any step is done again from what is on disk, losing nothing. The resume point
moves only from where the work found it. Before it changes any audio, a record is checked against
the committed page: layout work for a page that holds other paragraphs now is dropped (the page's
audio is aligned with what it holds when it opens); a merge aligns the merged audio, and moves
the resume point, onto what the kept page holds now, and if the kept page has been deleted,
leaves that audio to the cache's age prune; a delete whose page exists again (brought back while
it waited) leaves its audio to that page. So does a merge whose merged key a page holds again (a
book's *Replace* brought the chapter back): it moves and deletes nothing under that key, drops
none of its renders, moves no resume point and rekeys no session, and the audio is saved or
ephemeral as that page is; if that page is gone again by then, the later record that names the
key (its delete or merge) decides instead. A session playing the merged key keeps it until the
merge runs, so a *Replace* that revises or drops the kept page, or a delete of it, stops that
session with the kept page's own (`keysWaitingToMerge`, which applies the merge's rule: no page
holds the merged key and no later record names it). Otherwise the merge would move it onto
revised text it isn't playing, or leave it on a key no page holds. Under those stops, which
follow the sequences a *Replace* can make, sits the rule that holds for all of them: the merge
moves the session only onto a kept page holding the text it plays and otherwise stops it
(`SpeechController.rekeyActiveSession`, given the kept page's text by `keyMerged`), and
listening is written only on a page holding the text playing, so no order of later *Replace*s (a
key brought back with other text, a kept key that comes back after its text moved on) puts one
text's positions on another.

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
| Crash-resume point (key, paragraph, text fingerprint, time) | `Application Support/ListenTiming/listen_resume.json` (`ListenResumePointStore`) |
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
