# Technical spec

How Meridian Reader is built. What it does: `FUNCTIONAL_REQUIREMENTS.md`; screens and gestures:
`NAVIGATION.md`; listening: `LISTEN_PLAYBACK.md`, `TTS_ENGINES.md`; article keys:
`ARTICLE_IDENTITY.md`. Build commands and how changes are verified: `AGENTS.md` at the repo root.

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
| Persistence | SwiftData, two store files: the library (`Folder`, `Article`) and the local store (`RecentVisit`; `SavedArticle`, frozen); small JSON files and UserDefaults for the rest |
| Speech | `AVSpeechSynthesizer`; Kokoro via vendored FluidAudio (`Vendor/FluidAudio`) and ONNX Runtime (SPM `onnxruntime` 1.24.2) |
| Language | `NaturalLanguage` (article language), `Speech` (address-bar dictation) |
| Project | XcodeGen (`project.yml` → `MeridianReader.xcodeproj`) |

## Layout

```
App/        @main, composition root (AppComposition), launch work (AppLaunch), Debug-only launch hooks
Core/
  Device/       chip / OS gates
  Domain/       ReaderArticle, PageOrigin, ParagraphDocument, ParagraphSplitter, ArticleIdentity, ReaderScrubMap, WordCount
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
  Library/  the Library surface and screens (home, folder), rows, the Move tree, Favorites' sheet and ☆, the import sheet
  Saved/    save coordinator, Now Playing's content and progress store
  Speech/   SpeechController, playback session and engines, settings, voice libraries (Engines/)
Tests/      the few unit tests (MeridianReaderTests); Tests/Fakes builds a library over its own files
UITests/    three end-to-end flows (MeridianReaderUITests)
```

## Architecture

- **Composition root.** `AppComposition` is the only place that lists voice libraries; it builds
  the `EngineRegistry`, the one `SpeechController`, the `ShellState`, the `LibraryStore`, the one
  extractor, `DeveloperSettings`, Block Ads, Follow and Downloads, which `ReaderApp` injects through
  the environment; it wires Downloads to the render queue's changes and the library's edits
  (`makeDownloads`) and connects the speech stack to the library
  (`attachLibrary`: the library resolves Now Playing's text, and the `ListeningProgressRecorder`
  writes listening progress to it).
  `AppLaunch.run` does the launch work once: the library's launch maintenance
  (`maintainLibrary`, which then lets the render queue adopt and render), with the Debug launch
  hooks before and after it, then crash resume. Views only render. A Debug build hosting the unit
  tests builds none of it (`AppMain`): tests build their own stacks over their own files
  (`LibraryTestEnvironment`).
- **Navigation.** `ShellState` owns what you see: the surface (browser or library), the Reader
  sheet and what it sits over (`ReaderOrigin`), whether Now Playing is up, the one other sheet.
  It asks the playback session what you hear (`isHearing`) and stores nothing about it. A reading
  sheet's full screen is its own view state (`ReadingChrome`, held by `ReaderSheet` and
  `NowPlayingSheet`, fed by the reading web view's drags and taps), not the shell's. The reading
  web view's coordinator decides what the text shows (its hold: a fresh page's top, a handed-over
  place, the saved spot, a scrub; the spoken sentence while following) and one of two layouts
  (`ReadingTextLayout`) puts it on screen and keeps the reader's place through new layouts:
  Scroll (`HTMLReadingView+Scroll.swift`) or Pages (`HTMLReadingView+Pages.swift`), where the
  page's script measures its line boxes, `ReadingPagination` breaks them into pages of whole
  lines, and native views in the page's colour cover what of the pages around the one shown
  would show. Browse and the library share
  one `SearchSession` model.
- **Listening.** `SpeechController` binds an engine per utterance and derives what every screen
  shows of what you hear (`nowPlaying`, `playState(of:)`); `PlaybackSessionState` owns what you
  hear and its position; `LocalTTSCoordinator` owns the on-device engine, render queue and audio cache.
  Details in `LISTEN_PLAYBACK.md`.
- **Dependency direction.** App → Features → Core: Core names no Features or App type (the
  library reaches the speech stack through `LibraryAudioEffects`, the render queue through
  `SynthQueueContext`), and the design system names nothing outside itself and Core. Core never
  imports a voice library (FluidAudio and ONNX Runtime live in `Features/Speech/Engines/`).
  Features never name a concrete extractor. The Debug test fixtures (the demo book, the
  synthetic EPUB, the offline test pages' `TestPageSchemeHandler`) live in
  `App/Fixtures/`; App hands Core, the design system and Features what a launch asks for: the
  test pages' handler to the browser's web view (`webViewSchemeHandlers`) and to the
  `URLPageFetcher` behind Follow's `FetchQueue`, the ⋯ panel's test marker and slowed morph
  (`morphMenuMarksFocus`, `morphMenuAnimation`), Google suggestions off under `-uiTesting` and the
  scrub-bubble screenshot (environment values from `LaunchTestHooks`), the test EPUB in place of
  the Files picker (`BookImportActions.importsTestBook`, set in `AppMain`). No Feature reads
  `LaunchOptions`.

## Extraction

1. The browser keeps a live `WKWebView` (`WebViewStore`). Reader mode and Save take a snapshot of
   the page's visible DOM (`PageSnapshot`: `ReaderVisibleSnapshot.js` drops short invisible text
   such as anti-copy lines).
   When WebKit ends the view's content process (a crash, or memory taken), the view's delegate
   handles it (`WebViewStore.contentProcessEnded`), so WebKit doesn't reload once and stop: the
   page reloads at once (in the background, once the app is in front), then after 2 s and 5 s,
   and is left blank after a fourth end within a minute (`ContentProcessRecovery`). A reload
   still waiting is dropped when the view has moved to another page or is loading one.
2. `ReadabilityArticleExtractor` loads that HTML into an **off-screen** `WKWebView`
   (`OffscreenWebView`; the page URL as base for web pages) with the page's JavaScript off (its
   load gives up after 30 s, when WebKit's content process ends, or when the caller is
   cancelled: `NavigationWait`, shared with `URLPageFetcher`), injects Readability.js and the readerable helper, and runs
   `new Readability(document.cloneNode(true)).parse()`. `ListenContentNormalizer` then runs
   `ReaderNormalize.js` on the result in the same web view, so every piece of readable text sits
   in a listen block (loose text in a `<div>`, lines between `<br><br>`, the lead-in of a list
   item or quote holding blocks). The browser's page reaches the Reader, 🎧 and Save as a
   `SingleWebPageSource`: one page in no folder, its content normalized like every source's.
3. The address bar's reader icon and the ⋯ Reader toggle use the same
   `isProbablyReaderable` check, run after each load and same-document URL change.

**Fetching a page out of sight** (`URLPageFetcher`, for Follow and Downloads): a fresh `WKWebView`
the size of the app's window, placed off its left edge (the page lays out at the browser's width,
in a view WebKit counts as on screen), with the browser's cookies (the default website data
store, so a site you are signed in to in the browser serves the same pages) and page scripts off.
It loads the page, takes the same snapshot and extracts it through `SingleWebPageSource`, so a page
reads the same as from the browser; or it reads the page's links with the app's own script
(`links(of:)`, a `LinkPage`: each link's text and the list it sits in), for a story's table of
contents. A reply with an HTTP error (`NavigationWait` reads the main document's response) throws
`FetchError.status` with its `Retry-After` instead of being extracted. Loading, the snapshot and
extraction each give up after a time limit, since WebKit's processes can be suspended in the
background.

Every such fetch goes through one `FetchQueue`, strictly one at a time: each request waits for
the one before it and then for its site's pause (`FetchPacing`: 4 s, 12 s after a reply that took
6 s or more; a 429, a 5xx or no answer doubles the wait from 1 min up to 30 min, never under the
reply's `Retry-After`; each answer halves it back down). Of the requests whose site is ready, one a
tap asked for (Review's read, ▶ on a waiting chapter) goes first, then the oldest
(the chapter loop, the daily checks, downloads). Nothing loads in the background (the view needs
the app's window): requests wait for the app to come to the front, and a load the background cut
short is tried again then without counting against its site.

**Every web view starts from one configuration** (`WKWebViewConfiguration.appWebView`: the
browser and Follow's preview, the hidden fetcher, extraction, the Reader's text). Each view sets
only whether the page's own JavaScript runs and the URL schemes it serves itself. The rest is shared: the
default website data store (the browser's cookies), media that waits for a tap (no autoplay), and
**Block Ads** (`ContentBlocker`): the rule lists of one `ContentRuleListProvider` go on every
view's content controller once ready, and on and off with Settings › Browsing › *Block Ads*
(UserDefaults `browse.blockAds`, on by default); WebKit applies a change to loads that start
after it. `AppComposition.makeContentBlocker` picks the provider and sets the blocker on
`WKWebViewConfiguration.appContentBlocker` at launch, before the first web view; Settings gets
it from the environment. Another list or blocking library is another provider, named there. The
provider is `BundledRuleList`: a bundled WebKit content-blocker list
(`Resources/ContentBlocking/BlockAds.json`: rules each blocking requests to one ad or tracker
host and its subdomains, the page itself too, so a link through an ad host doesn't open). It is compiled once into WebKit's rule-list store under an identifier
carrying the JSON's hash: a launch looks it up (an edited list compiles anew and the older ones are
removed). A site's own ads (served from its own host, such as
Royal Road's promotions of its fictions) are not blocked.

**Follow** (`FollowCenter`, `LibraryStore+Follow`): a story's table of contents
(`TableOfContents.read`, through an ordered list of readers, the first that matches an address
reading it: Royal Road's story page by its chapters table, any other site by the list with the
most chapter-like links on its own site; a Royal Road chapter's address leads to its story page;
each reader also names its site) becomes a `series` folder of link pages, one per chapter kept in Review, in the
story's order, with its state in `sourceStateData` (`FollowState`: following or not, the last
check, the last chapters added, and every chapter address the contents have listed, kept or not).
Review's preview of a chapter is not an out-of-sight fetch: it loads the chapter in sight, in the
browser's `WebView` with a `WebViewStore(staysOnPage: true)` (links, forms and back / forward to
another address cancelled), and the 📄 at the end of its header's address label (`AddressLabel`)
extracts that loaded page for the Reader text, as the browser's Reader does.
The chapters' text is fetched one at a time while the app is in front (the chapter ▶ asked for,
else the one after the page playing, else the oldest story's first waiting chapter) and stored in
place (`storeFetchedText`; nothing renders: the folder's Download toggle decides that). A
chapter's address the library already has stays one page: one filed in a folder stays there, one
loose at the top level or out of the Library joins the story. A chapter
whose site refuses or doesn't answer is tried again after the back-off, four times, then waits for
the next launch or ▶. About once a day while the app is in front (a check is due 24 h after the
last; the app looks every 15 min and when it comes to the front), each followed story's contents
are read again and chapters not listed before go at the end of its folder; *Check Now* does the
same at once. Unfollow stops the checks; the chapters stay and their text is still fetched.

Snapshot plus off-screen, rather than injecting into the visible page: the user's page is never
mutated, injected scripts don't fight the page's CSP, and content rendered by JavaScript is
already in the snapshot. That is also why the off-screen view keeps page scripts off
(`allowsContentJavaScript = false`): the snapshot's `<script>` tags and inline handlers would run
a second time, fetch, and change the DOM before Readability reads it. The app's own
`evaluateJavaScript` calls still run.

**Success and failure.** Save and the reader need a non-empty body. Otherwise extraction fails
with a reason the user sees, and nothing is stored (no bookmark-only save, no raw snapshot). A
page without a title of its own (no `<title>`, heading or title metadata) is read and saved with
none (`ArticleRowTitle`): the Reader shows its source line alone, and rows, the bar and the lock screen
name it by its site.

**Book chapters** skip Readability: each chapter's XHTML goes through the normalizer alone, in
one reused off-screen web view holding a blank standards-mode page, after `ReaderBookChapter.js`
takes out pictures, embedded media, footnote asides, note references and links back from notes,
and unwraps links (parsed in an inert document, so nothing loads). A book's endnotes stay, on
their own back-matter page. See "Book import" below.

**Swapping the engine.** A new type conforming to `ArticleExtracting`, as the base of
`AppComposition.extractor`, the app's one extractor: the browser (through the environment),
Follow and Downloads (through `FetchQueue`'s `URLPageFetcher`) all use it; the library and speech
don't change. `DeveloperSwitchedExtractor` wraps it so that every extraction fails while Settings ›
Developer › Fake Extraction Failure is on.

**Manual check.** A news article and a long blog post extract a clean title and body; a home
page (e.g. `https://example.com`) fails with a reason and saves nothing.

## Data

Two SwiftData stores in one container (`LibraryStoreConfiguration`): **library**
(`Application Support/library.store`: `Folder`, `Article`, the migration's
`LibraryMigrationReceipt`s and pending `LibraryAudioWork`) and **local**
(`Application Support/default.store`, the file the app always used: `RecentVisit`, and
`SavedArticle`, frozen). The library has its own file because an older build reopening a shared
store would drop entities it doesn't know; a file it never opens survives a rollback. Library
models are CloudKit-shaped: every property optional or defaulted, no `.unique`, relationships
optional with `.nullify`; one page per canonical URL is kept by `LibraryStore` and the launch
dedupe pass. Every library read and write goes through `LibraryStore`; lists use
`LibraryQueries`. An edit someone asks for (a save, including one into a folder; a move; a
folder made, renamed, sorted or reordered; a mark; a remove of one or several pages or a
delete; a favorite added, renamed or removed; a book imported or replaced) is one save, made at
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

**`Article`** (library):

| Field | Purpose |
|-------|---------|
| `key` | Audio cache / listen key (`ARTICLE_IDENTITY.md`); copied verbatim from `SavedArticle.id` at migration, never recomputed |
| `urlString`, `canonicalURL` | The page; one page per canonical URL |
| `title`, `byline`, `excerpt`, `artworkData` | Rows, Now Playing (`byline` = site domain for web pages; `title` "" = the page has none, read as `givenTitle`, and a row names it by `lineOne`) |
| `contentStateRaw` | `link` (a favorite, a followed story's chapter waiting for its text; any text is a cache) or `saved` |
| `addedAt` | When it joined the Library; nil = played without saving or removed (kept 7 days after its last play; a removed page never played, until the next launch) |
| `removedAt` | When *Remove from Library* took it out, cleared when you listen to it again from its article (`recordPlayback`). Out of the Library with it set, a page is in no list, not even Recent, nor the bar's resume; read only while `addedAt` is nil |
| `folder`, `folderID`, `sortKey` | Its folder (none = the pages in no folder) and order there; `folderID` mirrors the relationship for predicates |
| `bodyHTML`, `plainTextData` | Offline reading; the listen text comes from the HTML |
| `wordCount`, `paragraphCount` | Row metadata; "audio ready" compares the cache against `paragraphCount`. Words are counted by one rule, `WordCount`, for web pages and chapters alike (each Chinese or Japanese character is a word); every text write goes through `Article.setText` |
| `positionParagraph`, `positionUTF16` | Resume position (paragraph + offset inside the document) |
| `lastPlayedAt`, `finishedAt` | Recent's order, the prune and the bar's resume, and a row's "◉ Finished" |
| `listenBlocksData`, `listenBlocksVersion` | Cached listen paragraphs and the layout version they were built with |
| `detectedLanguageCode` | Article language (`NLLanguageRecognizer`) |
| `skipsInPlayback` | Pages in folders (book front matter, *Skip in Playback*): what playback carries on to (`ChapterAdvance`, `LISTEN_PLAYBACK.md`) |
| `fetchStateRaw` | Kept as older builds stored it; nothing writes or reads it |
| `locator` | Book chapters: where the chapter starts in the book, `href#fragment` |

**Which lists a page is in** is decided in one place, `LibraryQueries`, from three standings and
the star: in the Library (`addedAt` set: its folder or the home's top level, search, address
suggestions); played without saving (out of the Library, played, `removedAt` nil: the home's Recent
tab and its search); removed (out of the Library, `removedAt` set: none of
those). A starred page is in Favorites whatever its standing, and the prune keeps it. *Remove from Library* (`LibraryStore.remove`, the one remove for every path: a
row, Edit, 🔖 and the ⋯ of the browser, the Reader and Now Playing, the Now Playing bar) takes a
page out of its folder and every Library list it was in at once, keeps its star (and with it its
place in Favorites) and deletes nothing (the launch prune does). Once that is saved, the page you
hear stops, and so does a session a waiting merge would move onto it (`keysWaitingToMerge`),
through the hook a delete stops them by (`LibraryStore.stopPlaybackIfPlaying` →
`SpeechController.stopIfPlaying`: no gap-fill render, and its queued render goes). A save puts it
back, and so does listening to it again from its article (🎧, the Reader's Listen, which
clears `removedAt`, through a rollback too: `PendingListening`). The Downloads list keeps downloads of what
is in the Library (`DownloadCenter`, after each stored edit, `LibraryStore.editStored`). The bar's
resume (`LibraryQueries.lastPlayed`) reads pages in the Library or played without saving, by when
they were played, and the prune keeps the one it offers.

**`Folder`** (library): `name`, `kindRaw` (`plain`, `book`, `series`, `favorites`), `sortKey`,
`parent` / `children` (any depth), `articles`, `articleSortRaw`, its details (`byline`, `coverData`:
a book's from its file; *Edit Details* changes `name`, `byline` and `coverData`
of any folder through `LibraryStore.setDetails`; a folder with a byline or cover,
`hasDetails`, shows the detailed header), for books and series their source
(`sourceIdentifier`, `sourceURLString`, `sourceStateData`: a book's `BookSourceState`, its file's
SHA-256 and the keys of the chapters its file gave, in order), and for every folder its place
(`currentArticleKey`, the page that last started: every folder plays page to page in its sort).
Whether a folder is finished isn't stored: `FolderProgress.isFinished` works it out from its pages.
`languageCode`, `lastPlayedAt` and `finishedAt` are kept as older builds stored them and nothing
writes or reads them. **Every folder follows the same rules (decision D19)**: books and
series take pages and subfolders, their chapters move out and reorder, their sort is the user's
(*Manual*, in the source's order, until changed). `kind` says only where a folder came from:
*Replace* finds a book by its key (`book(key:)`), a followed story (`series`) is read again and
its link chapters fetched by Follow, and playback stops before one still waiting for its text, a
book's or story's pages show as chapters and name it as their source in the Now
Playing bar (`PlaybackFolder.isBookOrSeries`), its finished chapters lose their audio (D7), and
  launch dedupe merges two copies of one source. Favorites are independent flags on pages and
  folders, independent of the Library too: Favorites lists every starred page
  (`LibraryQueries.favoriteArticles`), starring never files a page, *Remove from Library* keeps the
  flag (only unstarring clears it), and the prune keeps a starred page. A legacy Favorites folder an older build left in the store is migrated on launch
  (`migrateFavoritesFolder`): its direct children are starred (its pages return to the root, its
  subfolders move to the top level with their contents as they were, nothing deeper starred), and
  the container is removed.

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
   lower cap, at most three cuts. A chapter neither its contents entry nor a heading names has
   no title: rows and the bar name it by its book.
4. Before anything is stored, the chapters are held to the size policy on the listen blocks that
   will be stored (`BookChapterFinalizer.check`): a book with nothing left to read is refused as
   unreadable; a body chapter still over 30,000 words after the last cut, or one under 100 that a
   neighbouring body chapter could take, is refused as text that couldn't be prepared. A body
   chapter under 100 words stays only where no body neighbour can take it within 30,000: its
   neighbours are full, or it has none (a book under 100 words, a short section between skipped
   matter). Skipped chapters may be any length.
5. `LibraryStore.addBook` stores one `Folder(kind: .book)` (title, authors, a 600 px cover
   thumbnail, language, the book key as `sourceIdentifier`, the file's SHA-256 and the chapter
   keys in order in `sourceStateData`) at the destination (any folder, a book too), looked up
   again then (a destination deleted while the book was read fails the import), with one saved
   page per chapter in order (key `BookIdentity.chapterKey`, front matter `skipsInPlayback`), all
   in one save: a failed save keeps nothing. A chapter key the library already has (a chapter
   moved out of a deleted copy of the book) is brought up to date where it is, not made twice.
6. A book already in the Library (same book key) is left alone, or, with *Replace* (D13),
   rebuilt in the same folder by `LibraryStore.replaceBook` (`ARTICLE_IDENTITY.md`), in one
   save; a dropped chapter's audio goes only once that save succeeds. The book's chapters are
   the pages its record names, wherever they have been moved (D19); pages moved into the book
   are never touched; the folder's order is kept, a new chapter going in just after the chapter
   before it in the file (else just before the next one in the book, else at the end).
7. At launch, before anything else can move pages, a book stored before books kept that record
   gets one from the pages in it, in their order (`LibraryStore.recordBookChapters`); its
   chapters, order, details and listening are untouched. No SwiftData field changed for D19.

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
listen history becomes `lastPlayedAt` / `finishedAt`), bookmarks become starred link pages in no
folder in file order, and a bookmark for a page the library has stars that page where it is (one
in a folder stays there; one out of the Library joins it as a link). The paragraph layout pass then moves copied pages on older listen blocks to today's
layout, and only then does dedupe merge duplicates, so positions and audio are compared on the
same paragraphs. The pages and a receipt for every item copied are saved together: a failed save
leaves neither, so the next launch copies again, and a page deleted after the copy never comes
back. Receipts that can't be read stop the copy. A bookmarks file that doesn't decode is logged
and left as it is: nothing is copied or recorded from it, so it is copied if it becomes readable.
A launch with nothing to copy (every launch after the first) changes nothing and saves nothing.
Nothing legacy is written again: the rows, the
bookmarks file and the listen history stay as they were, so the previous build still works after
a rollback, and pages keep their rows' audio keys. Then the paragraph layout pass, the dedupe pass
and the prune of pages not in the Library run. Each saves on its own; a save that fails is rolled
back with the audio work it planned, so no later save can store that work against pages that
have changed since, and the next launch plans it again (dedupe waits for a layout pass that
couldn't save). Debug: `-rerunLibraryMigration` empties the library and its receipts and copies
again.

**Audio work waits for the save.** Deleting pages (*Delete Folder and
Contents*: the page's audio directory, pending render and queued renders go,
unless a page with its key exists again by then), pages leaving the Library (*Remove from
Library*: the audio is kept, back on the ephemeral TTL), Save (the audio marked saved and
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
merge runs, so a *Replace* that revises or drops the kept page, a delete of it or its *Remove
from Library*, stops that session with the kept page's own (`keysWaitingToMerge`, which applies
the merge's rule: no page holds the merged key and no later record names it). Otherwise the
merge would move it onto revised text it isn't playing or onto a page in no list, or leave it on
a key no page holds. Under those stops, which follow the sequences a *Replace* can make, sits
the rule that holds for all of them: the merge moves the session only onto a kept page holding
the text it plays and otherwise stops it (`SpeechController.rekeyActiveSession`, given the kept
page's text by `keyMerged`), and listening is written only on a page holding the text playing,
so no order of later *Replace*s (a key brought back with other text, a kept key that comes back
after its text moved on) puts one text's positions on another.

**`SavedArticle`** (local, frozen): the saved articles as stored before the library (`id`,
`urlString`, `canonicalURL`, `title`, `siteDomain`, `savedAt`, `cleanedHTML`, `plainText`,
`wordCount`, `estimatedMinutes`, `playbackParagraphIndex`, `playbackUTF16Offset`, `faviconData`,
`listenBlocksData`, `listenBlocksVersion`, `detectedLanguageCode`). Only the migration reads it.

**`RecentVisit`** (SwiftData): browser history, the last 30 top-level http(s) pages (canonical
URL, title, host, visit time, favicon), one per canonical URL (`ArticleIdentity`), recorded when a
load finishes (`LibraryStore.recordVisit`, stored through `commit`).

Elsewhere (`AppDirectories` names every file under Application Support):

| What | Where |
|------|-------|
| Bookmarks before the library (frozen; copied into Favorites) | `Application Support/Bookmarks/bookmarks.json` (`LegacyBookmarks`) |
| Recent searches | UserDefaults `browse.recentSearches` |
| Last listened / finished before the library (frozen; folded into `Article`) | UserDefaults `reader.listenHistory.v1` (`ListenHistory`) |
| Crash-resume point (key, paragraph, text fingerprint, time) | `Application Support/ListenTiming/listen_resume.json` (`ListenResumePointStore`) |
| Rendered audio | `Application Support/TTSCache/<article key>/` (`ArticleAudioCache`) |
| Pending render jobs | `Application Support/PendingBakeJobs.json` |
| Downloads (decision D16: what was asked for, each page's state, a kept voice) | `Application Support/Downloads.json` (`DownloadListStore`) |
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
script and the listeners it installs (tap-to-seek, taps for page turns and full screen, and
Pages mode's layout changes, through the `readerBridge` message handler), and `evaluateJavaScript` calls for highlight and
scroll. The reader's web view never navigates: a tapped link is cancelled and handed to the app,
which opens it in the browser; a fragment link only scrolls, and `javascript:` links do nothing.
The visible
browser keeps JavaScript on; sites need it.

## Article rename and store migration (C121)

The library's item model is `Article` (it was `Page`), alongside `Folder`. Its store entity was named `Page`, and SwiftData can't rename an entity, so `LibraryEntityRename` (`LibraryStoreConfiguration.swift`) runs before the container opens. It checks the store's metadata, and if it still has `Page`, it copies the files to `Application Support/LibraryBackup-C121` and runs Core Data's inferred lightweight migration in place. The source is the model cached in the store; `Page` and Folder's `pageSortRaw`, `currentPageKey` and `pages` are the renaming identifiers. If that fails, the launch stops rather than opening the store. `DownloadRecord.Target` still writes `page` in Downloads.json. Pages mode and web pages keep the word "page".

## New Folder everywhere and the header disc (C122, C124)

`MenuRegistry` has `.folderNewFolder` at `.header` and `.newFolder` at `.add` and the new `.edit` place, all hidden when `Facts.isFixedOrder` (an imported EPUB or followed story). `LibraryEditBar` shows `.newFolder` in slot 3 when the registry offers it; `LibraryScreenState.makeFolder(in:with:)` keeps the selection in `NewFolder.items`, and the alert's OK files them into the made folder with `library.move(_:to:)`, then clears the selection. `Verbs.newFolderInside` is gone. `FolderHeader` plays with `PlayStateButton.Look.headerDisc` (`BottomChrome.headerDiscSize` 56, glyph 23); `CentredSidesLayout` puts each side control's 44 pt glyph middle on the disc's middle, with its caption hanging below.

## The create group (C126)

`LibraryCreateMenu` (`LibraryScreenMenu.swift`) builds the one create group from `MenuRegistry` (`.newFolder`, `.importFile`, `.saveFromWebsite`, `.pasteText`, `.follow` at `.add` and `.edit`, each hidden when `isFixedOrder`). ＋ uses it as `createRows`, `FolderMenu` at `.header` appends it as a second block (`.folderNewFolder` is gone), and `LibraryEditBar` slot 3 is a ＋ `Menu` with it at `.edit`, `filing` the selection. *Save from Website…* (`LibraryScreenState.saveFromWebsite(into:)`, address alert) calls `LibraryStore.saveLink(_:in:)`: an article the library has moves into the folder and is saved; a new one is a `.link` article, fetched when it first plays or downloads.

## One row height in Edit and out (C123)

Library rows are one component, `ListRow`, in Edit and out; Edit only drops the ⋯ (`menu: nil`). Its vertical padding is `ListRow.verticalPadding`, (56 − 44) / 2 = 6 pt, so the ⋯'s 44 pt square fills the 56 pt `RowHeight.content` exactly and a row is 56 pt either way (it was 60 with ⋯, 56 in Edit). `ListRowHeightTests` checks both heights.

## Paste Text (C127)

*Paste Text…* opens `PasteTextSheet` (`LibraryScreenState.pasteText(into:)`, prefilled from `UIPasteboard.general.string` when `hasStrings`). *Save* calls `LibraryStore.saveText(title:text:in:)`: a new `.saved` article with no web address (`ArticleOrigin.book`, locator `text:<key>`, byline "Pasted text"), one `<p>` per line, its listen paragraphs built as any article's, at the end of the folder. A blank title becomes `LibraryStore.defaultTitle(for:)`: the first line up to its first sentence end, at most 80 characters.

## Jump to Audio and full screen (C128)

`ReadingChrome.showsJumpToAudio(awayFromAudio:)` is the one rule for both layouts: `awayFromAudio && !hidden`. `NowPlayingSheet` shows the pill through it, so in full screen (Scroll or Pages) only `FloatingPlayButton` floats over the text, with its look, place and `floatingDuration` fade unchanged. `JumpToAudioRuleTests` checks it.

## Engine stop recovery (C129)

- `EngineCrashGuard.beginCall` stamps the in-flight marker with `buildStamp` (executable size and
  mtime). A leftover marker from another build is verdict `reinstalled` and dismissed: an install
  replacing the app mid-call (the 2026-10-20 21:06 EDT Napoleon banner) is not a crash.
- `KokoroCrashRecovery`: Core ML crash or ONNX crash #1 gives `.stay(notice: nil)` (same voice,
  ONNX CPU, no banner); ONNX crash #2 in a row gives `.pauseForRetry` (amended): the coordinator sets
  `isPausedForRetry` and `GlobalSynthQueue.isPausedForRetry` stops the render worker (downloads,
  render-ahead); playback goes on through rendered audio. `LocalListenPlayer`'s producer stops at
  the first chunk not ready (`held_for_retry`), lets the buffer drain, then the engine pauses and
  `playbackReachedUnrendered` shows the banner with *Retry* (`retryAfterEngineStop`: fresh host
  via `reloadEngine`, then the queue resumes; pressing play or dismissing also retries). Each ONNX crash steps `cpuThreads` down one (minimum 2). There is no
  path from a Kokoro crash to Apple any more.
- Live-gap Apple units stay temp files (`UnitSource.appleFallback`, deleted when played); bake
  cache keys are `kokoro.<voice>`, so mismatched audio can't be cached.
- `VoiceCatalog.bestVoice(forLanguage:gender:)` ranks Premium > Enhanced > default, then the
  Kokoro voice's gender (`gender(ofKokoroVoice:)`), then region. Launch logs `apple_voices`
  (English voices, quality, and a Siri count) to the timing log.
