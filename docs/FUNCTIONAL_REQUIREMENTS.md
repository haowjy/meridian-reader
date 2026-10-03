# Functional requirements

Meridian Reader is a personal tool for **listening to web articles**: find a page in the in-app
browser, get a clean copy, and listen to it (or read it) on the device, offline once saved. How
the screens look and move: `NAVIGATION.md`. How it is built: `TECHNICAL_SPEC.md`.

## Surfaces

| Surface | Role |
|--------|------|
| **Browser** | The app's home: a start page or a web page, with one bottom bar (address field + toolbar). No tab bar. |
| **Library** | Every saved article, in place of the browser (same bottom bar shape); toolbar slot 4 swaps between them. |
| **Reader** | One reader screen for any article: over the browser, or pushed inside the library. |
| **Mini player** | Above the browser toolbar whenever an article is loaded for playback and the reader isn't showing. |

## Browser

| ID | Requirement |
|----|-------------|
| B1 | The address field takes a URL (loaded in the in-app web view) or search text (a Google search). |
| B2 | Pages open only by user action; links navigate normally. ‹ / › are web history. |
| B3 | The start page shows bookmarks (an icon grid), **Continue listening** (saved articles part-way through, most recent first, with time left), recent **Saved** articles, and Recent Searches. |
| B4 | While typing: local matches (history, saved articles) first, then live Google suggestions (unofficial endpoint, debounced). If Google fails, only local matches show, with no error. |
| B5 | History keeps the last 30 visited pages (title, host, favicon), deduped by canonical URL. Clearing history never deletes saved articles. |
| B6 | Bookmarks are site links (URL, title, favicon), independent of saved articles: bookmarking never saves, saving never bookmarks. |
| B7 | Dictation fills the address field while searching, on-device where the language allows; nothing is submitted automatically, and listening pauses while the mic is open. |
| B8 | Loading pages needs the network. |

## Reader

| ID | Requirement |
|----|-------------|
| R1 | Reader mode is manual: the address field's reader icon or ⋯ → Reader, only on pages that look readable. It never turns on by itself. |
| R2 | It shows the cleaned article; the paragraph being spoken (or where Play starts) is tinted. The text never scrolls on its own except to follow the user's scrub. |
| R3 | Listen controls: play / pause, previous / next paragraph, speed (0.75×–2×), a sentence-precise scrubber with fine scrubbing, and "select paragraph" (tap a paragraph to play from it). |
| R4 | Save / unsave from the reader keeps the screen and playback as they are. |
| R5 | One close control (bottom left) goes back to where the reader was opened from (web page, start page or library); the pull-down and the edge swipe do the same. Closing never stops audio. |

## Save and library

| ID | Requirement |
|----|-------------|
| S1 | Save is available from the browser and the reader, and always runs extraction. |
| S2 | On success the full article is stored on the device (text, cleaned HTML, metadata). |
| S3 | On failure Save is blocked with the reason, and nothing is stored. |
| S4 | One article per canonical URL: saving the same page twice (tracking parameters, fragments) keeps one row. |
| S5 | The library lists title, site and date; search filters it; swipe deletes (with its audio). A row's play button plays without opening. |

## Listening

| ID | Requirement |
|----|-------------|
| P1 | Apple TTS is the default and always available. Kokoro (on-device, English, A15+) is optional: downloaded on selection, deletable, and used only once ready. Apple speaks whenever Kokoro can't (not downloaded, loading, failed, crashed, another language, a chunk it can't render). |
| P2 | Playback never goes silent or freezes mid-article: anything the selected engine can't produce is spoken with Apple. |
| P3 | Each article keeps one voice's audio; switching voice re-renders it, and the old voice plays until each paragraph is replaced. |
| P4 | The position is remembered per article and resumed later; after a Kokoro crash the app reopens the article at the paragraph that was playing. |
| P5 | Listening continues in the background, with lock-screen / Control Center controls (play, pause, next / previous paragraph, rate). Calls and unplugged headphones pause; a resumable interruption resumes. |
| P6 | The article's language is detected; an article the selected engine can't speak uses an Apple voice for its language, without changing settings. |
| P7 | Saved articles play fully offline. |

## Not in the app

- Accounts, a backend, sync.
- Tabs; a share extension or open-in as an entry point.
- Auto reader mode, auto-opening links, saving failed extractions.
- Cloud voices.
- Folders, tags, highlights.
- Chapter-to-chapter auto-advance (planned).
