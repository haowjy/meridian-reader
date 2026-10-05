# Functional requirements

Meridian Reader is a personal tool for **listening to web articles**: find a page in the in-app
browser, get a clean copy, and listen to it (or read it) on the device, offline once saved. How
the screens look and move: `NAVIGATION.md`. How it is built: `TECHNICAL_SPEC.md`.

## Surfaces

| Surface | Role |
|--------|------|
| **Browser** | The app's home: a start page or a web page, with one bottom bar (address field + toolbar). No tab bar. |
| **Library** | Every saved article, in place of the browser (same bottom bar shape); toolbar slot 4 swaps between them. |
| **Reader** | A sheet for reading any page, over the browser or the Library, with its own Listen. |
| **Now Playing** | A sheet over everything for what you hear: a player in deep jade (light and dark alike) with a title card, the Reader's text in lyrics style following the audio, and the player's controls. |
| **Now Playing bar** | What you hear, on the browser, the start page, the Library and the Reader sheet, from the first play until *Stop Listening* (long-press); it keeps a finished page with ▶. Tap or swipe up → Now Playing. |

## Browser

| ID | Requirement |
|----|-------------|
| B1 | The address field takes a URL (loaded in the in-app web view) or search text (a Google search). |
| B2 | Pages open only by user action; links navigate normally. ‹ / › are web history. |
| B3 | The start page shows bookmarks (an icon grid), **Continue listening** (articles part-way through, saved or listened to in the last 7 days without saving, most recent first, with time left), recent **Saved** articles not bookmarked, and Recent Searches. |
| B4 | While typing: local matches (history, saved articles) first, then live Google suggestions (unofficial endpoint, debounced). If Google fails, only local matches show, with no error. |
| B5 | History keeps the last 30 visited pages (title, host, favicon), deduped by canonical URL. Clearing history never deletes saved articles. |
| B6 | Bookmarks are site links (URL, title, favicon): bookmarking never saves, saving never bookmarks. One page per address: bookmarking a saved article moves it from the library list to the bookmarks, still saved; unsaving a bookmarked article keeps the bookmark. |
| B7 | Dictation fills the address field while searching, on-device where the language allows; nothing is submitted automatically, and listening pauses while the mic is open. |
| B8 | Loading pages needs the network. |
| B9 | A readable page shows 🎧 at the end of the address field: grey when it isn't what you hear (tap: listen now, replacing what plays once this page is extracted; "Nothing to listen to on this page" when it has too little text), accent with bars when it is (tap: pause / resume). |

## Reader

| ID | Requirement |
|----|-------------|
| R1 | Reader mode is manual: the address field's reader icon or ⋯ → Reader, only on pages that look readable, or a start-page / Library row. It never turns on by itself. Opening the Reader of the page you hear opens Now Playing instead. |
| R2 | The Reader shows the cleaned article on paper in the serif reading style, under its title and source. It never scrolls by itself. |
| R3 | Its Listen ("Listen · 9 min", "Resume · 6 min left", "Listen Again") starts the page at its saved spot and turns the Reader into Now Playing; ☝︎ then a tap on a paragraph listens from there. The Reader has no speed or skip buttons. |
| R4 | Save / unsave from the Reader or Now Playing keeps the screen and playback as they are. |
| R5 | The Reader's back pill ("‹ Browser", "‹ Library"), its grabber and a pull down close it to exactly where you were. Closing never stops audio. |
| R6 | Now Playing follows the audio: the spoken paragraph is in full ink (the others dimmed) and near the middle, its sentence underlined; scrolling stops following and offers *Back to audio*. Controls: play / pause, previous / next paragraph, speed (0.75×–2×), a sentence-precise scrubber with fine scrubbing, ☝︎. Its header says where it plays from; ⊕ saves. At the end it stays, with "✓ Finished" and ▶. ⌄ or a pull down shrinks it into the bar. |

## Save and library

| ID | Requirement |
|----|-------------|
| S1 | Save is available from the browser and the reader, and always runs extraction. |
| S2 | On success the full article is stored on the device (text, cleaned HTML, metadata). |
| S3 | On failure Save is blocked with the reason, and nothing is stored. |
| S4 | One page per canonical URL: saving, bookmarking or listening to the same page twice (tracking parameters, fragments) keeps one page. |
| S5 | The library lists title, site and date; search filters it; swipe deletes (with its audio). A row's play button plays without opening. |

## Listening

| ID | Requirement |
|----|-------------|
| P1 | Apple TTS is the default and always available. Kokoro (on-device, English, A15+) is optional: downloaded on selection, deletable, and used only once ready. Apple speaks whenever Kokoro can't (not downloaded, loading, failed, crashed, another language, a chunk it can't render). |
| P2 | Playback never goes silent or freezes mid-article: anything the selected engine can't produce is spoken with Apple. |
| P3 | Each article keeps one voice's audio; switching voice re-renders it, and the old voice plays until each paragraph is replaced. |
| P4 | The position is remembered per article and resumed later, for an article listened to without saving too (kept 7 days after it was last played); after a Kokoro crash the app reopens the article at the paragraph that was playing. |
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
