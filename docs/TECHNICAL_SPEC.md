# Technical Spec — Reader (iOS) v1

**Status:** Locked from design-tree decisions (2026-09-17)  
**Companion:** `FUNCTIONAL_REQUIREMENTS.md`

---

## 1. Goals and constraints

- iOS-only native app
- No backend, accounts, or sync
- Offline-first for Saved + Speak; network only for live Browse
- Extraction must be **swappable** behind a protocol
- Default extractor: Mozilla Readability on the **live WKWebView DOM**, validated by a **site-test spike** before main UI depends on it

---

## 2. Stack

| Layer | Choice |
|-------|--------|
| Language | Swift |
| UI | SwiftUI |
| Live browser | `WKWebView` |
| Extraction (default) | Mozilla Readability on live DOM (e.g. `swift-readability` or bundled Readability.js) |
| Persistence | SwiftData |
| TTS | `AVSpeechSynthesizer` + system voices |
| Concurrency | Swift concurrency (async/await) |
| Search from Browse bar | Google Search URL for non-URL queries |

**Not used in v1:** server APIs, cloud TTS, Share Extension target (unless added later), cross-platform frameworks.

---

## 3. High-level architecture

Feature modules + thin Core. Avoid forcing MVVM onto SwiftData lists.

```
ReaderApp/
  App/                    # @main, ModelContainer, dependency wiring
  Features/
    Saved/                # library list, offline reader, row play button
    Browse/               # start screen, WKWebView chrome, Reader toggle, Save
    Speech/               # playback UI + SpeechController
  Core/
    Domain/               # Article value types, pure helpers
    Extraction/           # ArticleExtracting protocol + Readability implementation
    Persistence/          # SwiftData models, ArticleStore
    Web/                  # WKWebView wrappers, navigation events
  Resources/              # reader CSS/templates if needed
```

### 3.1 UI patterns

- **Saved:** SwiftUI views + SwiftData `@Query` (Apple-aligned). Search via query predicate / filter.
- **Browse / Speech:** small `@Observable` controllers for WebView state and long-lived synthesizer.
- **Extraction:** service behind `ArticleExtracting`; features never import a concrete engine directly.
- **Tabs:** `TabView` — **Saved** (default) | **Browse**.
- **Navigation:** ‹ = push with edge swipe-back, ✕ = modal with swipe-down. See `NAVIGATION.md`.

### 3.2 Dependency direction

```
Features → Core.Domain / Core.Extraction / Core.Persistence / Core.Web
Concrete ReadabilityAdapter → ArticleExtracting
App wires adapters at launch
```

---

## 4. Extraction design (swappable)

### 4.1 Protocol (illustrative)

```swift
protocol ArticleExtracting: Sendable {
    func availability(for context: ExtractionContext) async -> ArticleAvailability
    func extract(from context: ExtractionContext) async throws -> ExtractedArticle
}

struct ExtractionContext: Sendable {
    let url: URL
    // Handle or ID for the live WKWebView / DOM access — keep WebKit types out of Domain if possible
}

struct ExtractedArticle: Sendable {
    var title: String
    var siteName: String?
    var cleanedHTML: String
    var plainText: String
    var excerpt: String
}

enum ArticleAvailability: Sendable {
    case available
    case unavailable(reason: String)
}

enum ExtractionError: Error {
    case unavailable(reason: String)
    case emptyContent
    case engineFailed(underlying: Error)
}
```

### 4.2 Default engine

- Run Readability against the **rendered** page in `WKWebView` after navigation settles.
- Prefer libraries/patterns that expose availability (enable/disable Reader affordance when possible).
- **Do not** use fetch-only HTML as the primary path (fails on JS-rendered articles).

### 4.3 Success / failure rules

Save / Reader persist path must require non-empty **title** and **body** (plain text or HTML body). Otherwise:

- Throw / return failure with a user-facing reason
- **Persist nothing**

### 4.4 Spike (required before main UI hard-depends on extractor)

Test a fixed set of URLs (news, blog, Substack-like, medium-like, and a homepage that should fail). Record pass/fail for availability + extract quality. Only then lock the concrete package and wire Browse UI tightly to it.

### 4.5 Swap path

New engine = new type conforming to `ArticleExtracting`. Change composition root only. No rewrites of Saved/Speech.

---

## 5. Data model (SwiftData)

`SavedArticle` (name flexible):

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `UUID` | Primary key |
| `url` | `String` / `URL` | Original page URL |
| `title` | `String` | List + reader title |
| `siteDomain` | `String` | List + Home domain chips |
| `savedAt` | `Date` | Sort / display |
| `cleanedHTML` | `String` | Offline reading |
| `plainText` | `String` | TTS source |
| `wordCount` | `Int` | Stats |
| `estimatedMinutes` | `Int` or `Double` | List metadata (derive from wordCount) |
| `playbackPosition` | See below | Resume |
| `excerpt` | `String` | List preview snippet |

### 5.1 Playback position

Store a resume cursor compatible with paragraph skip, e.g.:

- `playbackParagraphIndex: Int`
- optional `playbackUtf16Offset: Int` within plain text as refinement

Update on pause/stop/skip and on significant progress callbacks from `AVSpeechSynthesizer` delegate if used.



### RecentVisit (Browse history)

SwiftData model, capped list (default 30):

| Field | Type | Notes |
|-------|------|-------|
| `urlString` | `String` (unique canonical) | No fragment; http(s) only |
| `title` | `String` | From `document.title` / host fallback |
| `host` | `String` | Display subtitle |
| `visitedAt` | `Date` | Recency sort; update on revisit |
| `faviconData` | `Data?` (external storage) | Fetched from page icon links or `/favicon.ico` |

Recording: after top-level navigation `isLoading` → false. Dedupes by `urlString`. Tabs are out of scope.

### 5.2 Domain chips

Derive unique domains from `siteDomain` (or host of `url`) over Saved articles, sorted by recency of last save from that domain. Tap → load `https://{domain}` (or last saved path policy — v1: origin/home of domain is enough unless spike says otherwise).

---

## 6. Feature behaviors (technical)

### 6.1 Browse start

- Google-style field:
  - Detect URL (add scheme if missing when clearly a host/path)
  - Else `https://www.google.com/search?q=...`
- Domain chips from persistence query
- Nothing auto-opens

### 6.2 Browse WebView

- Standard back/forward as feasible in chrome
- Actions: Reader (manual), Save
- Save calls `ArticleExtracting.extract` using live WebView context

### 6.3 Reader Mode

- Manual toggle
- Displays cleaned HTML (engine overlay or load extracted HTML into a reader WebView / native text view — implementation choice during build; prefer one clear approach in spike)
- Does not auto-engage

### 6.4 Saved

- `@Query` ordered by `savedAt` descending
- Search: filter title/site/excerpt/plainText
- Row tap → offline viewer loading `cleanedHTML` (baseURL = original URL for relative links if any remain)
- Play button → `SpeechController` with that article’s `plainText` + stored position
- Swipe delete → delete model

### 6.5 SpeechController

- Owns a **long-lived** `AVSpeechSynthesizer` (do not allocate per tap)
- Speaks `plainText` segmented by **paragraph** (split on blank lines / block boundaries from extraction)
- Paragraphs over 1,200 chars are split at sentence ends into balanced pieces (~500–900 chars) for display, navigation and audio alike (`ParagraphSplitter`, listen layout v3; see LISTEN_PLAYBACK.md)
- Play / pause / stop
- Skip ±1 paragraph
- Rate mapped to ~0.75x–2x (`AVSpeechUtterance.rate` mapped carefully; document mapping in code)
- Persist position into SwiftData article
- No MPRemoteCommandCenter in v1

---

## 7. Offline behavior

| Feature | Offline |
|---------|---------|
| Saved list / search / delete | Yes |
| Offline article view | Yes (`cleanedHTML`) |
| Speak | Yes (`plainText` + system voices) |
| Browse load | No — needs network |
| Save new page | Needs network + successful extract from live page |

---

## 8. Security / privacy (v1)

- All article content stays on device
- No analytics backend required by product
- Sanitize extracted HTML before display where scripts could remain (e.g. DOMPurify in reader pipeline if using HTML WebView) — treat as implementation requirement when rendering `cleanedHTML`
- Network only for user-initiated Browse loads and Google search navigations

---

## 9. Testing plan (minimum)

1. **Extraction spike:** fixture URLs, availability + extract quality, failure on homepage
2. **Save failure UX:** non-article page → blocked save, nothing in DB
3. **Offline:** airplane mode → Saved list, open article, speak, resume
4. **Speech:** paragraph skip, speed, pause/resume position
5. **Browse bar:** URL vs Google query
6. **Domain chips:** appear after saves; tap opens site

---

## 10. Implementation sequence (suggested)

1. SwiftData model + Saved list UI (empty states)
2. Extraction protocol + Readability adapter + **spike**
3. Browse WebView + start screen (Google bar + chips)
4. Manual Reader + Save wiring (success/fail)
5. Offline article viewer
6. SpeechController + row play button + position persistence
7. Polish: search, delete, speed control, error copy

---

## 11. Open items (allowed to resolve during build)

- Exact Swift package vs vendored Readability.js
- Reader presentation: in-WebView overlay vs separate offline WebView
- Precise URL detection heuristics for the search bar
- Paragraph segmentation rules on plain text
- `AVSpeechUtterance.rate` ↔ UI speed label mapping

These must not break the locked product rules in `FUNCTIONAL_REQUIREMENTS.md`.
