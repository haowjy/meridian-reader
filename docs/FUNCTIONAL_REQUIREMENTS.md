# Functional requirements

Meridian Reader is a personal tool for **listening to web articles**: find a page in the in-app
browser, get a clean copy, and listen to it (or read it) on the device, offline once saved. How
the screens look and move: `NAVIGATION.md`. How it is built: `TECHNICAL_SPEC.md`.

## Surfaces

| Surface | Role |
|--------|------|
| **Library** | The folder tree: the home is the top level, with Everything (its folders, books and series among them, then the pages in no folder, pages played without saving on top, in the top level's sort) and Favorites (starred folders and pages from anywhere) tabs, then folder → folder at any depth. The same bottom band as the browser (D22, D23): the Now Playing bar across the top, the swap then the search field, then ‹ › ＋ 🕘 ⋯ in the browser's ‹ › 🔖 🕘 ⋯ slots. No tab bar. |
| **Browser** | A start page (Favorites, Recent Searches) or a web page, with one bottom bar (address field + toolbar). |
| **Reader** | A sheet for reading any page, over the browser or the Library, with its own Listen. |
| **Now Playing** | A sheet over everything for what you hear, in the Reader's reading theme and type: a title card, the text following the audio (the spoken paragraph highlighted, the others dimmed), and the player's controls. |
| **Settings** | ⋯ › Settings, the last row of every ⋯ panel: Appearance (System / Light / Dark, five app colours), Reading (theme, font, size, spacing; the same as Aa), Listening (engine, voice, language, speed), Downloads & Storage, and Developer (developer options only). |
| **Now Playing bar** | What you hear, on the browser, the start page, every Library screen and the Reader sheet, from the first play until *Stop Listening* (long-press); it keeps a finished page with ▶. Tap or swipe up → Now Playing. |

The app reopens on the surface you left: the Library at the folder you were in, or the browser on
its last page (reloaded). A fresh install opens the Library.

## Browser

| ID | Requirement |
|----|-------------|
| B1 | The address field takes a URL (loaded in the in-app web view) or search text (a Google search). |
| B2 | Pages open only by user action; links navigate normally. ‹ / › are web history. |
| B3 | The start page shows starred pages and folders as a Favorites icon grid, along with Recent Searches; Show All opens the Library's Favorites tab. |
| B4 | While typing: local matches (history, saved articles) first, then live Google suggestions (unofficial endpoint, debounced). If Google fails, only local matches show, with no error. |
| B5 | History keeps the last 30 visited pages (title, host, favicon), deduped by canonical URL. Clearing history never deletes saved articles. |
| B6 | ☆ *Add to Favorites* sets an independent star flag without moving the page. A new favorite may be a link (URL, title, favicon) without being saved; a page stays where it is, in the Library or not (starring never files it). Favorites lists every starred page, in the Library or not, and a starred page is never pruned. Unstarring only clears the star. *Remove from Library* never clears it: the page leaves every Library list and stays in Favorites. One page per address; a chapter can be starred like any other page. |
| B7 | Dictation fills the address field while searching, on-device where the language allows; nothing is submitted automatically, and listening pauses while the mic is open. |
| B8 | Loading pages needs the network. |
| B9 | A readable page shows 🎧 at the end of the address field: grey when it isn't what you hear (tap: listen now, replacing what plays once this page is extracted; "Nothing to listen to on this page" when it has too little text), accent with bars when it is (tap: pause / resume). |

## Reader

| ID | Requirement |
|----|-------------|
| R1 | Reader mode is manual: the address field's reader icon or ⋯ → Reader, only on pages that look readable, or a Favorites tile or a Library row. It never turns on by itself. Opening the Reader of the page you hear opens Now Playing instead. |
| R2 | The Reader shows the cleaned article on paper in the serif reading style, under its title and source. A page part-way through opens with the sentence at its saved listening spot in the middle, underlined; after that the text never scrolls by itself. |
| R3 | Its Listen ("Listen" with "9 min", "Resume" with "6 min left", "Listen Again") starts the page at its saved spot and turns the Reader into Now Playing; ☝︎ then a tap on a paragraph listens from there. The Reader has no speed or skip buttons. |
| R4 | Save / *Remove from Library* from the Reader or Now Playing keeps the screen and playback as they are, and removes as a Library row does (S6). 🔖's long-press saves the page into a folder picked in the Move tree. |
| R5 | The Reader's back pill ("‹ Browser", "‹ Library"), its grabber and a pull down (on the header, or on the text from its top) close it to exactly where you were. Closing never stops audio. |
| R6 | Now Playing follows the audio: it opens with the spoken sentence near the middle and keeps it there, the spoken paragraph in full ink on the theme's highlight (the others dimmed), the sentence underlined in the theme's accent; scrolling stops following and offers *Jump to Audio*, which brings the spoken sentence back to the middle. Controls: play / pause, previous / next paragraph, speed (0.75×–2×), a sentence-precise scrubber with fine scrubbing, Aa, ☝︎. It shares the Reader's top bar, 🔖, ⋯ and reading appearance (D24): its close pill says where it plays from, ⋯ → *Go to* opens that place, 🔖 saves or files. At the end it stays, with "✓ Finished" and ▶. The close pill or a pull down (on the header, or on the text from its top) shrinks it into the bar. |

## Save and the Library

| ID | Requirement |
|----|-------------|
| S1 | Save is available from the browser (⋯ → *Save to Folder…*, into a folder picked in the Move tree) and the Reader, and always runs extraction. |
| S2 | On success the full article is stored on the device (text, cleaned HTML, metadata). |
| S3 | On failure Save is blocked with the reason, and nothing is stored. |
| S4 | One page per canonical URL: saving, adding to Favorites or listening to the same page twice (tracking parameters, fragments) keeps one page, in at most one folder. |
| S5 | Folders nest to any depth. A folder lists its subfolders, then its pages by its sort (Manual, Newest, Title); Edit selects rows to move, mark finished or remove, and drags them when Manual. Without Edit, a row lifted with a long press is filed by dropping it on a folder, or placed by dropping it between rows (which makes the folder's sort Manual); a folder can't go into itself or a folder inside it. Books and series are folders like any other: they take drops and subfolders, and their chapters move, drag and reorder as any page. Folders can be made, renamed, moved and deleted: deleting offers only *Delete Folder and Contents*, which deletes everything inside with its audio. A delete that can't be saved leaves the pages and their audio. The home's Favorites tab and search results gather rows from across the tree: they don't drag, and a folder there opens under its parents. |
| S6 | Rows show a length, "N min left" part-way or "✓ Finished" (folders: what is in them, or their place; every length and time left in the app counts at the playback speed), a small mark when downloaded (in the current voice, or one kept), and the playing row is tinted. A tap opens a row (the Reader, Now Playing for what you hear, the browser for a link); its ▶ plays it without opening; a long-press is its menu (Move to…, Mark as Finished, Share, Download, Delete Downloads, Remove from Library; in a folder also Play from Here, Mark All Above as Finished, Skip in Playback); swipe left removes it. Removing a page, from here or anywhere else (Edit, 🔖, the ⋯ of the browser, the Reader and Now Playing), is one action: it takes the page out of every list it was in (Pages, its folder, Favorites, search, Downloads) and keeps its star, and it doesn't come back as "Not saved", even while it plays (saving it, or listening to it again with 🎧 or the Reader's Listen, does); a remove that can't be saved changes nothing and says so. |
| S7 | Nothing on the Library home appears or goes away because playback starts or ends. The row of any folder whose pages play (a book or series too) shows its place (the page it is at) and time left ("6 h 10 min left"), and its ▶ resumes it there without opening it; a part-way page's row shows the time left and its ▶ resumes it; the Now Playing bar's ▶ resumes what you last heard. Pages played without saving show at the top of *Pages*, "Not saved", with *Save* in their menu. |
| S8 | A book or series is a folder: it opens to the folder screen with its details (cover, author), a Continue / Play from Start button, and its chapters, first in the source's order (front matter skipped in playback, *Skip in Playback* per chapter); after that its order, sort and contents are the user's, as for any folder. Playing any chapter carries on through the book in its order, then stops. |
| S11 | Any other folder with pages that play plays like a book: its screen has the same Continue / Play from Start button, and playing any of its pages carries on through its pages in its order (its sort), page to page, passing over link pages, then stops. The page that last played is its place. A page in no folder plays to its end and stops. Now Playing says what it plays from: the folder, else the Library or the site. |
| S9 | Search in the Library covers titles, sites, folder names and authors across the tree, and offers *Search the web*. |
| S10 | *Import Book…* (the Library's ＋ and ⋯, the empty Library) imports a DRM-free EPUB picked in Files, or one an `.epub` link in the browser downloads (asked first), as a book: one folder with one page per chapter, front matter skipped in playback. The import shows its progress, can be cancelled (keeping nothing), and files the book in *Add to* (the folder it started from, else the Library), which can change while it runs; it then opens the book. One import runs at a time. Copy-protected, fixed-layout, too-large and unreadable files are refused with a one-line reason. A book already in the Library asks *Replace* (same folder, its order kept, places kept where chapters match; chapters moved elsewhere are found and updated where they are, new ones go after the chapter before them) or *Cancel*. |
| S12 | *Follow…* (the browser's ⋯ on a story's page, the Library's ⋯ with a typed address) reads the story's table of contents (Royal Road's story page, or any site's longest list of chapter links) into Review: every chapter with a box, *Select All*, and a preview of a chapter on tapping its row. OK makes the story's folder at once with the chapters kept, as links, whose text is then fetched in the background while the app is in front, strictly one at a time with a pause, backing off when the site asks to slow down or doesn't answer, with one status line in the folder's header. ▶ on a chapter still waiting fetches it first, then plays it; playing through the story stops before a chapter not fetched yet. About once a day while the app is in use the contents are read again and new chapters go at the end (left-out ones stay out). The Following sheet shows the last and next check and the fetch progress, with *Check Now* and *Unfollow* (the chapters stay). No feeds, no notifications. |

## Listening

| ID | Requirement |
|----|-------------|
| P1 | Apple TTS is the default and always available. Kokoro (on-device, English, A15+) is optional: downloaded on selection, deletable, and used only once ready. Apple speaks whenever Kokoro can't (not downloaded, loading, failed, crashed, another language, a chunk it can't render). |
| P2 | Playback never goes silent or freezes mid-article: anything the selected engine can't produce is spoken with Apple. |
| P3 | Each article keeps one voice's audio; switching voice re-renders it, and the old voice plays until each paragraph is replaced. |
| P4 | The position is remembered per article and resumed later, for an article listened to without saving too (kept 7 days after it was last played); after a Kokoro crash the app reopens the article at the paragraph that was playing, or at its own spot, paused, when its text has changed since. |
| P5 | Listening continues in the background, with lock-screen / Control Center controls (play, pause, next / previous paragraph, rate). Calls and unplugged headphones pause; a resumable interruption resumes. |
| P6 | The article's language is detected; an article the selected engine can't speak uses an Apple voice for its language, without changing settings. |
| P7 | Saved articles play fully offline. |
| P8 | *Download* on a page, folder, book or followed story fetches its text (keeping a link page's in place); a folder's Download is a switch that, while on, also downloads every page added to it later, and turned off keeps what is downloaded and renders its whole audio in the on-device voice ahead of time, one page at a time, behind what is playing and only while the app is in front. A slim line on the bottom chrome shows progress while downloads run; nothing is modal. ⋯ › Downloads lists them (Queued with pause and remove, Done with the storage used, Different Voice), each with its voice; after a voice change a download offers *Re-download* or *Keep*. |

## Not in the app

- Accounts, a backend, sync.
- Tabs; a share extension or open-in as an entry point.
- Auto reader mode, auto-opening links, saving failed extractions.
- Cloud voices.
- Tags, highlights.
