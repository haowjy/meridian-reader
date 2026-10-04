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
| Persistence | SwiftData (`SavedArticle`, `RecentVisit`); small JSON files and UserDefaults for the rest |
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
  Persistence/  SwiftData models, ArticleLibrary (save, migrations), BookmarkStore
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
  the `EngineRegistry`, the one `SpeechController` and the `ShellState`, which `ReaderApp` injects
  through the environment, and connects the speech stack to the saved-article store
  (`attachLibrary`: Now Playing's content resolver and the `ListeningProgressRecorder`). `AppLaunch.run` does the launch work once: the saved-article migrations (with the
  Debug launch hooks before and after them), then crash resume. Views only render.
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

**`SavedArticle`** (SwiftData):

| Field | Purpose |
|-------|---------|
| `id` | Article key (`ARTICLE_IDENTITY.md`); unique |
| `urlString`, `canonicalURL` | The page; canonical form for dedupe |
| `title`, `siteDomain`, `excerpt`, `faviconData` | Library rows, Now Playing |
| `savedAt` | Sort |
| `cleanedHTML`, `plainText` | Offline reading; the listen text comes from the HTML |
| `wordCount`, `estimatedMinutes` | Row metadata |
| `playbackParagraphIndex`, `playbackUTF16Offset` | Resume position (paragraph + offset inside the document) |
| `listenBlocksData`, `listenBlocksVersion` | Cached listen paragraphs and the layout version they were built with |
| `detectedLanguageCode` | Article language (`NLLanguageRecognizer`) |

**`RecentVisit`** (SwiftData): browser history, the last 30 top-level http(s) pages (canonical
URL, title, host, visit time, favicon), deduped by URL, recorded when a load finishes.

Elsewhere:

| What | Where |
|------|-------|
| Bookmarks (site links: URL, title, favicon) | `Application Support/Bookmarks/bookmarks.json` (`BookmarkStore`) |
| Recent searches | UserDefaults `browse.recentSearches` |
| Last listened / finished per article | UserDefaults (`ListenHistory`) |
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
