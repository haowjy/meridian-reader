# Navigation rule

**If a screen shows ‹, you can swipe back from the left edge. If it shows ✕ (or is a sheet with a
grabber), you can pull it down.** Either gesture must do exactly what tapping the button does.

The two reading sheets have no ✕: the Reader closes with its labelled back pill ("‹ Browser",
"‹ Library"), Now Playing with ⌄. Both carry a grabber and pull down from their header, or from
their text when it is at its top, which does exactly what that button does.

| Button | Presentation | Gesture | Provided by |
|--------|--------------|---------|-------------|
| ‹ | real push in a `NavigationStack` (`NavigationLink` / `navigationDestination`) | left-edge swipe-back | UIKit with the system back button; `.edgeSwipeBack()` (`App/SwipeBackSupport.swift`) with a custom one |
| ✕ | modal: `.sheet`, or the design system's `Sheet` (the Reader, Now Playing) | swipe down | `.sheet` does it natively; `Sheet` implements it (see below) |

## ‹ = push + swipe-back

- Never show a ‹ screen with `.sheet` / `.fullScreenCover`; push it.
- A custom back control is fine: hide only the system back button
  (`.navigationBarBackButtonHidden(true)`), put your row in the bar
  (`ToolbarItem(placement: .principal)`), and add `.edgeSwipeBack()` to the screen. UIKit disables
  swipe-back once the back button is hidden; `.edgeSwipeBack()` re-enables it for that screen only:
  the edge gesture begins only at stack depth > 1 and not mid-transition, and scroll views yield
  to it only at the very left edge. iOS 26's full-width content swipe is off on that screen, so
  sideways drags (the reader's scrubber, text selection) never pop it.
- **Don't hide the whole navigation bar on a pushed screen** (`.toolbar(.hidden, for: .navigationBar)`)
  when the screen below shows one. The bar is shared by the stack, so mid-swipe the parent's bar
  (large title, search field, toolbar buttons) pops in full-width on top of the page you're leaving.
  Keep the bar visible and stable; that gives the standard push/pop look. (The Library home, the
  stack's root, has no bar: its title is the first thing in its list. The screens pushed over it
  keep theirs.)
- Don't build swipe-back by hand. Push with `NavigationStack`; with the system back button it just
  works, with a custom one add `.edgeSwipeBack()`.
- A custom back control should just `dismiss()`; put "leaving" side effects in `onDisappear` so
  the swipe and the tap stay identical. No screen saves the listening position: the playback
  session does, through `ListeningProgressRecorder` (`LISTEN_PLAYBACK.md`).

## ✕ = modal + swipe-down

- `.sheet`: swipe-down is built in (show the grabber), from the header or from a scrolling body at
  its top: the Favorites sheet, the Move tree, the import sheet (except while it works), History,
  Voice Settings. A Done/Cancel/✕ button is optional.
- The Reader and Now Playing are the design system's `Sheet` (in place, not a `.sheet` or
  `fullScreenCover`): pulling the header (grabber, back pill or ⌄ row) down calls the same close
  action as its button. Closing never stops audio: the Now Playing bar shows what is playing. The
  header and the bottom row never hide, so the header is always there to pull.
- **The text pulls the sheet too, from its top**, so a sheet closes one-handed from the lower half
  of the screen (`SheetPullHandoff`). A drag on the text that begins with the text at its top and
  goes down moves the sheet instead of bouncing the text, which stays put; moving back up lowers
  the sheet first, then scrolls the text again. A drag that begins anywhere else in the text only
  scrolls, even once the text reaches its top: reading back up never closes the sheet. Sideways
  drags, text selection and ☝︎ taps are untouched, and the scrubber and the bottom row aren't
  text, so they never pull. In Now Playing a pull alone keeps following the audio (it moves
  nothing); once the drag moves the text, following stops as for any drag.
- It moves like a system sheet: it rises from the bottom and leaves the same way. The surface
  stays as it is underneath (the page or start page, the Library's screen), so the pull reveals
  where you're going back to: the sheet follows the finger (up only with rubber-band resistance;
  a drag that starts sideways leaves it in place), shrinks slightly, and the dim behind it lifts.
  Released far enough (72 pt) or flung (where a quarter second more at the release speed would
  take it past 180 pt; about 700 pt/s from rest), it carries on off the bottom at the finger's
  speed; otherwise it springs back (`Motion.settle`). The header and the text use the same rule.
  Under Reduce Motion it fades in and out instead. What is under a sheet takes no touches until it
  has gone.

## Two surfaces: the Library and the browser (no tab bar)

There is no tab bar. The app has two surfaces, swapped by slot 4 (📚 on the browser, 🌐 on the
Library): the **Library**, the folder tree, and the **browser**, a web page or the start page.
`BrowseStartView` hosts both (`ShellState.surface`); all chrome is one bottom bar, and each
surface uses everything between the status bar and it (safe area respected).

**The app reopens on the surface you left** (decision D10): the Library at the folder you were in
(`ShellState.libraryPath`, folders that no longer exist dropped), or the browser on its last page,
reloaded. A fresh install opens the Library. Kept on the device in UserDefaults
`shell.lastSurface` (`SurfaceMemory`). Reopened on the Library, the browser's last page loads the
first time you go there (🌐), and stays remembered until then, across relaunches. UI-test launches
start on the browser unless `-restoreSurface`.

```
╭ [art] Now playing title              ⏸ ╮   ← the Now Playing bar (once something has played)
╰ site   N min left ━━━━━━━━──────────────╯
( 📄 address …                        🎧 )   ← 📄 / 🎧 on readable pages; 🎤 only while searching
[ ‹ ]   [ › ]   [ 🔍 ]   [ 📚 ]   [ ⋯ ]    ← 5 equal slots (slot 4 = Library↔Browser)
```

**One bottom-chrome design**, shared by the browser, the Library, the Reader and Now Playing so
the bottom of the screen barely changes between them (`Features/DesignSystem/Chrome/BottomChrome.swift`): the band
(`bottomChromeBand`: 12 pt margins, 8 pt top padding, system bar material through the home
indicator), the field capsule (`bottomChromeField`: 44 pt, chrome-coloured capsule; 36 pt body-size controls
inside, like 🎤), and the toolbar row (`BottomToolbarLayout` + `toolbarIconFrame`: 44 pt, plain
19 pt glyphs). With larger text the capsule and its controls grow (up to 1.5×) instead of
clipping; toolbar glyphs keep their size and show in the large content viewer on long press.
Every control takes taps in at least 44 × 44 pt (`tapTarget`), whatever its drawn size: the
address-field 📄 and 🎧, the ✕ beside a search field, the Now Playing bar's play/pause, the
capsule's 36 pt controls. **Five equal slots, evenly spaced, one grid for every row:** Browse is
`[‹][›][Search][Library][⋯]`, the Library surface `[＋][★][Search][Browser][⋯]`, the Reader
`[🔖][ ▶ Listen  9 min ][⋯]` (the pill spans slots 2–4) and Now Playing `[1×][⏮][▶︎][⏭][⋯]`. Slot 4 is the Library↔Browser swap (📚 on Browse, 🌐 on Library — same
muscle memory as the morph-menu Reader↔Website near ⋯). Leading items fill slots 1, 2, 3…; the
last item (⋯) always sits in slot 5, so every icon in slot N is at the same x and the ⋯ menu
grows from the same spot. ⋯ is never replaced. The Now Playing bar's play/pause is centered over
the ⋯ slot too.

- **Search** (🔍, middle): focuses the address field, empty, for a new search (Recent Searches
  show full-bleed, Safari-style); ✕ cancels and restores the page's address. Swipe down lowers
  the keyboard but stays in search mode (typed text and ✕ kept). The page stays loaded underneath.
- ‹ / › are web history (disabled when WebKit can't go back / forward; KVO on the web view, so
  same-document history counts too). The web view's own edge swipes still work.
- No Reader button in the toolbar. The **reader icon** (📄, like Safari's page-format icon) sits
  at the leading edge of the address field only when the page is readable (the same Mozilla
  `isProbablyReaderable` check extraction uses, run after each load / same-document URL change);
  otherwise the lock / search glyph is there. Tapping it opens the Reader sheet (a spinner
  replaces it while the article is extracted); on the page that is playing it opens Now Playing.
- **🎧** (headphones, trailing end of the address field) also shows only on readable pages. It is
  the page's own play button: grey when the page isn't what you hear (tap: listen now: a spinner
  while the page is extracted, what's playing keeps playing until this page is ready, then it
  replaces it, at the page's spot if it has one, or from the top if it was heard to the end; if
  extraction fails or finds too little text, 🎧 goes back to grey and a toast says "Nothing to
  listen to on this page"; Stop Listening, any other ▶ / ⏸ or another 🎧 while it extracts
  cancels it, silently); jade with moving bars when this page is playing
  (tap: pause); jade with still bars when it is loaded and paused (tap: resume). It never
  navigates.
- **⋯** opens a Safari-style menu panel that grows out of the button (covers the ⋯, no arrow):
  rows *New Search, Save to Library… / Remove from Library (🔖), Add to Favorites / Remove from
  Favorites (☆), Share, Reload, Voice Settings, Debug ›* (Debug only with developer options on —
  see "Developer options" below), then a row of big buttons **Favorites**, **History**, and
  **Reader** (rightmost, nearest the thumb, like Safari's All Tabs). *Save to Library…* opens the
  Move tree and saves the page into the folder picked. The Reader toggle is disabled on the start
  page and on pages that aren't readable; on a readable page tapping it switches into reader
  mode. Actions that present something (Share, Voice Settings, Favorites, History, the Move tree)
  run after the panel has closed.
- **The ⋯ panel** (`MorphMenuOverlay`: one overlay for the browser toolbar ⋯, the library
  toolbar ⋯, the Reader's ⋯ and Now Playing's ⋯; its rows come from the surface that opened it,
  `MenuContext`) is not a popover: it is placed so the bottom-right button's icon (Reader,
  or Website in the Reader and Now Playing — marked with `morphMenuFocus`) sits slightly up and to
  the left of the ⋯ glyph (Safari's feel: **12 pt left, 10 pt up**), not dead-on on top of it (UI
  tests check the offset within 1 pt on Browse, the Reader and Now Playing). It covers
  the button and the toolbar around it, so the bottom row lands under the thumb, and grows out of
  that point (the glass grows from the button's circle to the panel's frame and corners, never
  stretched; the rows fade / un-blur in) while the ⋯ glyph
  fades, and the rest of the screen dims. Tapping the dimmed area,
  swiping the panel down, or Escape (VoiceOver scrub / hardware Esc) collapses it back into the
  button (a swipe-down collapses it at the release speed). While dragged, the panel follows the
  finger down and resists going up (rubber band); the drag's axis is fixed by its first movement,
  so a horizontal drag leaves the panel in place and a drag that drifts sideways doesn't make it
  jump. The sheets' pull-down follows the same rules. Light glass on iOS 26 (thick material
  before). Debug › is a native `Menu`.
- **☆ Add to Favorites**: one tap adds the page as a link at the end of Favorites, and a toast
  offers *Change Folder* (the Move tree). A page filed in another folder asks *Move it to
  Favorites?* first (one page per address); a chapter of a book or series offers *Move Book (or
  Series) to Favorites* instead, because a chapter never leaves its book. A page in Favorites or
  one of its subfolders is a favorite: ☆ then reads *Remove from Favorites*. A chapter whose
  book or series is in Favorites is a favorite too; its ☆ asks *Take Book (or Series) out of
  Favorites?* and moves the whole book to the top level, never the chapter alone.
- **One library**: everything is a page in a folder (or in none). A page is a *link* (an address
  you kept, such as a favorite: no text or audio), *saved* (text and audio kept), or played
  without saving (kept 7 days, shown at the top of the Library's *Pages* as "Not saved", and in
  the bar). There is one page per
  address: saving a favorite saves it in place; unsaving a page in a folder leaves it there as a
  link. 🔖 = saved, ☆ = favorite.
- **The Now Playing bar** (`NowPlayingBarView` → `NowPlayingBar`) is the one thing that shows what
  you hear: a floating card 8 pt above the field capsule with the page's artwork (favicon or a
  letter tile), its title, the site and the time left (two parts set apart by space, the time in lighter
  ink), a thin progress line along its bottom edge, and
  play/pause centered over the ⋯ slot. It looks the same on the browser, the start page, the
  Library and the Reader sheet. It shows from the first play; it hides on Now Playing, while you
  type in a field, under other sheets, and after *Stop Listening*. At the end of a page it stays,
  reading "✓ Finished", and ▶ plays the page again. Tap or swipe up → Now Playing; long-press →
  *Stop Listening* (unloads the page; the bar goes).

**Start page** (no page loaded), Safari-style:
1. **Favorites**: the Favorites folder as Safari shows it, a grid of its pages (favicon, or a
   coloured letter tile when there is no usable favicon, with the title below), then its
   subfolders as folder tiles; 4 per row, up to 8. Show All → the Favorites sheet. A page tile
   opens the page (a link in the browser, a saved page in the Reader); a folder tile opens the
   Favorites sheet at that folder; long-press a page tile → Rename… / Remove from Favorites.
2. **Recent Searches** (local, newest first, Clear).

**Favorites sheet** (`FavoritesSheet`): the Favorites folder screen, with its own pushes into
subfolders; its links open in the browser and its saved pages in the Reader, closing the sheet
first. Done, grabber, medium/large. Its bottom row is `[＋][ ][ ][ ][⋯]` on every screen of the
sheet: ＋ is *New Folder* in the folder on screen, and ⋯ is the Library's ⋯ for that folder
(*Sort ›, New Folder Inside*, and for a subfolder *Rename, Move…, Delete Folder…*; *Debug* with
developer options on, its panel over the sheet), shown in the sheet; its big buttons are
**Favorites** (back to the sheet's top), **History**, **Browser** (closes the sheet).

## The Library

The Library is a stack of screens in a `NavigationStack` (`LibrarySurface`, the path is
`ShellState.libraryPath`): the home, then folder → folder at any depth. ‹ and the edge swipe go
back up. It uses the **same bottom chrome** as the browser: the Now Playing bar, the search field
capsule and `[＋][★][🔍][🌐][⋯]`. ＋ is *Import Book…* and *New Folder*, both made in the folder
on screen (beside a book, on a book's screen). ★ pushes Favorites over the screen you're on (‹
comes back). 🌐 shows the browser as it was; 📚 there comes back to the same folder. The
⋯ panel follows the screen on top (below), always with big buttons **Favorites**, **History**,
**Browser**, and with developer options on a last row *Debug* (the listen debug panel); nothing
in it acts on the page under the Library. History closes the Library first; Browser is the same
swap as 🌐.

```
Library                                   title in the list, scrolls away (no navigation bar)
★  Favorites                       12  ›  Favorites first, then your folders by their order
▣  Pride and Prejudice                 ▶  a book or series: its place and its own ▶
   Ch 24   ◐ 6 h 10 min left
Pages  48                      Show All › not saved first, then pages in no folder; the first 5
[i] Notes on Tides                     ▶
    example.org   Not saved   ◐ 4 min left
```

Secondary lines (a row's second line, the bar's, a header's details) never join their parts with
a separator character: the parts sit apart by space (`DetailLine`, `Spacing.s`, growing with the
text), the first in secondary ink and the rest in the lighter tertiary ink; a playing row's status
is in the accent. The first part (the site) truncates when the line is short of room; the status
never does, and at large text sizes the parts wrap onto further lines. A section's count is its
own lighter label after the title (*Pages* then *48*). VoiceOver reads the parts joined with
commas.

- **The home** (`LibraryHomeView`): nothing on it appears or goes away because playback starts
  or ends. The bar's ▶ resumes what you last heard, and rows carry their own place and ▶
  (decision D14). First the top-level folders, with no header; a book or series
  row shows its place and time left ("Ch 24", then a ring and "6 h 10 min left") and its ▶ resumes it
  there without opening it. Then **Pages**: the pages played without saving, newest played first,
  marked "Not saved" (long-press → *Save* puts one in the Library), then the pages in no folder,
  newest first; Show All pushes them all (the not-saved ones on top), sorted by the top level's
  sort (*Manual / Newest / Title*, ⋯ → Sort; kept on the device, `library.topLevel.sort`). A row
  added while you watch (a save, a first play) animates in. ⋯: *Voice Settings, Import Book…, New
  Folder*. An empty Library shows Favorites, then one card, *Find something to listen to*: "Tap
  🌐 to find a page, or ＋ to import a book", with *Browse the web* and *Import a book*.
- **A folder** (`FolderScreen`, Favorites included): its title and counts, subfolders first (by
  their order), then pages by the folder's sort. **Edit** (top right), or *Select* in a row's
  long-press menu (Edit with that row selected), puts check circles on the rows, and drag handles
  (pages only when the sort is *Manual*); the toolbar becomes *Move…,
  Mark Finished, Remove* for the selection. *Remove* takes the selected pages out of the
  Library at once, then asks before deleting the selected folders, which stay selected until
  their delete is saved (*Cancel* keeps them selected). ⋯: *Sort ›, New Folder Inside, Import
  Book…, Rename, Move…, Delete Folder…* (Favorites: *Sort* and *New Folder Inside* only; it can't
  be renamed, moved down or deleted).
- **Importing a book** (*Import Book…*: ＋, the home's and a folder's ⋯, the empty Library's
  card) opens the Files picker for EPUBs. The picked file is copied into the app and the import
  sheet (`BookImportSheet`, medium, grows to large) comes up at once: the cover, title, author,
  file and chapter count once read; a progress line ("Reading chapters… 4 / 9"); **Add to**, the
  folder whose screen it started from (else the Library), with *Change*, which pushes the Move
  tree inside the sheet and works until the book is being saved (the book is saved there; a
  chosen folder deleted meanwhile shows as *Deleted folder* and the import stops, saying so); the
  first chapters and what is skipped for listening. It can't be pulled down
  while it works; *Cancel* stops it and keeps nothing. Done, it closes on the book's screen,
  with *▶ Play from Chapter 1*. A refusal says why in one line with OK: copy-protected (DRM),
  fixed layout, too large, or not a readable EPUB; so does an import or *Replace* whose save
  fails, which keeps nothing. A book already in the Library asks *“Title”
  is already in the Library*: *Replace* (the same folder, its name and place kept, positions
  kept where chapters match; *Add to* then shows where it is and can't change) or *Cancel*
  (decision D13). An `.epub` link in the browser downloads the book (a toast while it does) into
  the same sheet, which waits for *Import* (top right), going to the Library unless changed. One
  import at a time: a book whose download finishes while the import sheet is up isn't imported,
  and a toast over the sheet says so.
- **Deleting a folder** asks *Delete Folder Only* (its subfolders and pages move up one level,
  after what is already there) or *Delete Folder and Contents*, with what it holds ("2 folders,
  27 pages, 1 book") and, when the playing page is inside (or a waiting merge would move it onto
  a page inside, `LibraryStore.keysWaitingToMerge`), which choices stop it: "Stops what's
  playing." when every choice deletes it, else the one that does, by name ("Delete Folder and
  Contents stops what's playing."), since *Delete Folder Only* keeps the pages and keeping a
  folder's contents beside a book deletes only the book. A book or
  series always goes with its chapters, so a selection holding one never offers *Folder Only*:
  books alone ask *Delete Book* / *Delete 2 Books*; folders and books together ask *Delete Book,
  Keep Folder Contents* or *Delete Everything*, saying the books go either way
  (`FolderDeletePrompt`). Pages and their audio go together: the audio is deleted once the delete
  is saved, and a delete that can't be saved leaves both (and says so, below).
- **A book or series** (`BookScreen`): the cover, title, author, chapter count and where it came
  from; how far through ("38%", then "6 h 10 min left"); the round play button (*▶ Play from
  Chapter 1* before anything has played, *▶ **Continue** Ch 24*, or jade bars *Playing Ch 24*
  while one
  of its chapters plays: tap pauses) and *Play from Start*; then the chapters in their source
  order. No Edit. Front matter shows dimmed with "skipped" (it still opens for reading); *Jump
  to current* scrolls to the chapter Continue resumes. Playing any chapter carries on through the
  book, then stops. ⋯: *Rename, Move…, Delete Downloads, Delete Book…*. A series is the same
  screen; its chapters not fetched yet are lighter link rows ("not fetched yet").

**Rows** are `ListRow`s. A tap opens the row; its menu is a long-press (decision D11); swipe left
removes. Rows that can play keep their ▶ (`PlayStateButton`): it plays the row (replacing what
plays) or pauses / resumes it when it is what you hear, and never navigates. The playing row is
tinted, with still or moving bars. Under the title, after the site, rows show a length ("18
min"), "6 min left" with a small ring part-way, or "✓ Finished", so the title keeps the row's
width. ▶ / ⏸ and a folder's › share one trailing column, centred on the ⋯ slot as the bar's ⏸
is; a folder's count sits just before its ›. On a folder screen every row's menu starts with
*Select*.

| Row | Tap | Trailing | Menu (long-press) | Swipe left |
|---|---|---|---|---|
| Folder, Favorites | opens it (push) | count, › | *Move to…, Rename, Delete…* (Favorites: none) | Delete… |
| Book or series | opens it (push) | ▶ (resumes at its place; the place under the title) | *Continue, Play from Start, Move to…, Rename, Delete Book…* | Delete… |
| Saved page | the Reader (Now Playing if it's what you hear) | ▶ | *Move to…, Mark as Finished / Unfinished, Share, Delete Downloads* (when it has audio)*, Remove from Library* | Remove |
| Page played without saving ("Not saved", top of *Pages*) | the Reader (Now Playing if it's what you hear) | ▶ | *Save, Share* | — |
| Link page | the page, in the browser | — | *Move to…, Share, Remove from Library* | Remove |
| Chapter | the Reader (Now Playing if it's what you hear) | ▶ (not on skipped ones) | *Play from Here, Mark as Finished / Unfinished, Mark All Above as Finished, Skip in Playback / Play in Playback, Delete Downloads* | — |

**The Move tree** (`MoveTreeSheet`): one sheet for *Move to…*, *Save to Library…*, 🔖's *Save to
Folder…* and *Change Folder*; the import sheet's *Add to* pushes the same list inside it. The whole tree as one indented list (medium, grows to large): *＋
New Folder* (made at the top level, and the item goes in it), *Library (no folder)*, then
Favorites and every folder, depth first. One tap files; ✓ marks the current place; a folder's
long-press offers *New Folder Inside* (made in it, and the item goes in that). *Library (no
folder)* files the page in no folder, out of the folder it was in (a link in Favorites leaves
Favorites, saved); an ordinary 🔖 or *Save* keeps a page's folder. Books and series aren't
destinations; a folder being moved, and everything inside it, can't be picked. The tree closes
once what was picked is saved; a pick, or a *New Folder*, that can't be saved leaves it up under
the toast, to pick again or ✕ (in the import sheet, a *New Folder* that can't be saved leaves the
tree up the same way). The browser's *Save to Library…* closes it on the pick, since the
page is extracted first (⋯ spins).

**A change that can't be saved** (a move, *New Folder*, *Rename*, *Sort*, a drag to reorder, a
mark, *Remove*, a delete, ☆ or a favorite tile's *Rename* / *Remove*, saving or unsaving with 🔖,
⊕, *Save to Folder…* or ⋯ → *Save to Library…* / *Remove from Library*) isn't stored: the
library reads as it did before it, and a toast says so ("Couldn’t move", "Couldn’t save") where
a success would have shown. *Remove* of several pages is one change: all go, or none. A folder's
screen doesn't follow a move that didn't happen, the Move tree stays up, ☆ shows no "Added to
Favorites", and 🔖 / ⊕ keep what they showed. In Edit, the selection stays when its change can't
be saved; Edit's *Remove* is two changes, the pages first and then, after the question, the
folders, so a folder delete that can't be saved leaves the folders selected but doesn't bring back
pages already removed. The toast shows over the Favorites sheet, the Move tree, the import sheet
and Now Playing too. Listening goes on being kept meanwhile: where you are in a page, when you last played it and
whether you finished it are stored once saving works again, even across failed changes.

**Library search** is the same session as the browser's (`SearchSession` +
`SearchSessionChrome`): focusing the field (or toolbar Search) hides the toolbar so the field sits
above the keyboard with a round ✕; swipe-down / scroll lowers the keyboard but **stays in search
mode**; ✕ exits. While there is text, the results cover the Library's screens: folders (by name,
or a book's author) and pages (titles, sites, excerpts) across the whole tree, then *Search the
web for "…"*, which opens the browser.

**Editing the address** (a ✕ state, so it closes like one):
- The toolbar steps aside and the field sits right above the keyboard, with a round ✕ to its right.
- A full-bleed **Recent Searches** / suggestions layer covers the page (Safari): header + Clear All,
  magnifying-glass rows, and an ↑← control that fills the term into the field without navigating.
- ✕ exits search mode: keyboard down, the page's address restored.
- Scrolling the Recent Searches / suggestions list drags the keyboard down with the finger
  (interactive, like Safari); with nothing listed, a swipe down on the layer lowers it. Either way
  it **stays in search mode** — typed text and ✕ remain; tap the field to type again.
- Focusing selects the whole address, so typing replaces it. While the field is empty or still
  shows the untouched address, **Recent Searches** (local, newest first, Clear All) are shown;
  otherwise Recents / Saved / Google suggestions.
- 🎤 appears **only while searching** (the address field's `SearchSession`), not on the idle
  address bar. It dictates on-device (`SFSpeechRecognizer`, `requiresOnDeviceRecognition` when
  the locale supports it): partial text streams into the field; it stops on a second tap, on
  ~1.6 s of silence, or when you type. Listen pauses while the mic is open and resumes
  afterwards; its `.playback`/`.spokenAudio` session is restored. Nothing is submitted
  automatically.

## The Reader and Now Playing (what you see, what you hear)

What you **see** and what you **hear** are separate, in three layers: the surface (the browser or
the Library), the **Reader sheet** over it for reading any page, and **Now Playing** over
everything for what you hear. The Now Playing bar is the one bridge between them: tapping it opens
Now Playing. Navigating never changes what you hear, and a play button never navigates. The Reader
never shows the page you hear: opening the Reader of that page (📄, a Favorites tile, a Library
row) opens Now Playing instead.

### The Reader sheet

```
┌──────────────────────────────────────┐
│                 ───                  │ ← grabber
│ ( ‹ Browser )                    ☝︎  │ ← back pill names what is underneath
│ Notes on Tides                       │ ← title, then "site   9 min"
│ … serif text on paper …              │
│ ╭ Now Playing bar ──────────────╮    │ ← what you hear (always another page)
│ [🔖]  [ ▶  Listen  9 min ]  [ ⋯ ]    │ ← this page's own ▶, a pill over slots 2–4
└──────────────────────────────────────┘
```

- **A sheet over the surface that opened it** (`ReaderSheetScreen`, `ShellState.reader`). From
  the browser (📄, ⋯ → Reader, a Favorites tile) the pill reads *‹ Browser*; from the Library
  *‹ Library*. The pill, the grabber and a pull down all close it to exactly where you were.
- **Listen** reads *▶ **Listen** 9 min*, *▶ **Resume** 6 min left* for a page part-way through
  (the time in regular weight after the semibold title, left out when the pill is short of room
  at large text sizes), or *▶ Listen Again* for a finished one. It starts at the page's saved spot, makes the page what you
  hear (replacing what plays) and turns the Reader into Now Playing in place, where the Reader was
  (decision D2):
  - **At the Reader's top** (its first line of text not yet scrolled above the top of the reading
    area, so the title may be part way up), Now Playing opens at its top, the title card in full.
  - **Scrolled into the text**, the same line stays at the same place on screen, though Now
    Playing's title card is not the Reader's heading and its header is taller (more so at large
    text sizes); the card is then partly or wholly above the reading area.
  - **When that place can't be reached** (past either end of Now Playing's page), the page goes
    as far as it can that way, so the line stays in view as near its place as possible. Keeping
    the line in view wins over showing the card in full.

  Now Playing sets that position once its page is laid out and holds it while the layout
  settles (the title card measured, the header, a text size change: each keeps the same line).
  It drops it if you drag, scrub, Back to audio, the audio moves on or the page reloads first. ☝︎ in the header, then a tap on a paragraph, listens from that
  paragraph (a hint banner with Cancel floats over the text meanwhile). While ☝︎ is on, each
  paragraph is a button to VoiceOver, *Paragraph N*, hint *Plays from this paragraph*.
- **The Reader never scrolls by itself** and has no speed or skip buttons; reading text never
  moves under you. A text size change (Dynamic Type) keeps the line at the top of the reading
  area where it is, to the character; a page at its top stays at its top. Now Playing does the
  same, or, while it follows the audio, centres the spoken paragraph again.
- 🔖 saves / unsaves (tap; filled = saved), or files the page (long-press → *Save to Folder…*,
  the Move tree: saved there, or moved there when already saved); it keeps the screen and
  playback as they are.
- **⋯** (slot 5, the browser's ⋯ spot): rows *Save / Remove from Library, Move to…* (a saved
  page)*, Add to Favorites, Share, Voice Settings, Debug* (developer options only); big buttons
  **Favorites / History / Website** — *Website* (the Reader off) shows the page in the browser,
  wherever the Reader was opened from; from the library, the library closes first. Playback
  never stops.
- The text sits between the header and the bottom row, so its first line starts below the back
  pill and its last line scrolls clear of the bottom row (UI tests check both).

### Now Playing

```
┌──────────────────────────────────────┐
│  ⌄          PLAYING FROM          ⊕  │ ← ⌄ or a pull down: shrink into the bar; ⊕ Save (✓ saved)
│              example.com             │ ← tap: the page in the browser
│ ╭ [art] Title                      ╮ │ ← the title card, scrolls with the text
│ ╰       example.com   9 min left   ╯ │
│ … serif text, dimmed; the spoken     │
│   paragraph in full ink, the         │
│   sentence underlined …              │
│            ( Back to audio )         │ ← after you scroll away
│ Preparing next… / ✓ Finished         │ ← status notes, above the scrubber
│ ( ━━━━━●━━━━░░░░──  ☝︎ )             │
│ [1×]  [⏮]  (⏸)  [⏭]  [ ⋯ ]          │ ← the big round ⏸ / ▶ in the middle
└──────────────────────────────────────┘
```

- **Opens from** the bar (tap, swipe up), from opening the Reader of the page that is playing,
  from Listen in the Reader (in place, D2) and from crash resume. It presents over everything
  (`ShellState.isNowPlayingPresented`) and holds no article of its own: it shows what you hear.
  **⌄ or a pull down (on the header, or on the text at its top) shrinks it into the bar**, back on
  what was underneath (the browser, the Library, or a Reader of another page), untouched.
- **It looks like a player, not the Reader**: deep jade in light and dark mode alike (the
  `Palette.player…` tokens), with light status bar content and a heavier dim on the strip above
  it. While a finger pulls it down the dim lifts, but the strip under the status bar stays as dark
  as at rest until the sheet has gone, so the clock stays readable. A **title card** at the top of the text (it scrolls with the text) shows the artwork, the
  title, and the site and time left as two parts (*✓ Finished* at the end). The text keeps the Reader's serif and
  margins in **lyrics style**: the spoken paragraph in full ink, the others dimmed, no tint box
  (a paragraph pressed while ☝︎ is on is in full ink too).
  The *Back to audio* pill is light with dark text; the scrub capsule, the bubble and the jump
  hint sit on the player's card colour. The Reader stays on paper. A plain-text article (no
  reading HTML) shows its paragraphs on the same reading page, in both, so everything below
  applies to it too.
- **"Playing from"** says *Library* for a saved page (tap: Now Playing closes onto the Library)
  and names the site for a page you haven't saved (tap: the page in the browser).
- **The text follows the audio.** On each new paragraph it scrolls the spoken one near the middle
  (the `Motion.standard` spring; a jump under Reduce Motion). The spoken paragraph lights up to
  full ink while the one before dims (a short fade; none under Reduce Motion), and the current
  sentence is underlined in ink (per chunk on engines that report only chunk starts; no underline
  before iOS 17.2). Drag the text and following stops (a pull of the sheet from the text's top
  doesn't move the text, so following goes on); a *Back to audio* pill floats over the text just
  above the controls (no arrow: the spoken paragraph may be above or below).
  Tap it (or start another page) and following resumes. Scrubbing scrolls to the paragraph under
  the thumb.
- **At the end** it stays on the page: the text stays, all of it in full ink, a note says
  "✓ Finished", and ▶ plays the page again.
- **Controls** (today's listen rows): the scrub row and `[1×][⏮][▶︎][⏭][⋯]` in the browser's
  five-slot grid (1× under ‹, ⏮ under ›, ▶︎ under Search, ⏭ under Library, ⋯ under ⋯). ▶︎ / ⏸ is a
  64 pt round button (accent fill, dark glyph; fixed size, like the toolbar glyphs). The row stays
  44 pt, so every slot sits where it does on the other surfaces; the disc overhangs it. ⏮ ⏭ and
  headphone / lock-screen skips are paragraph skips (D4). A sideways swipe on the row skips too.
- **Status notes** ("Preparing next…", Apple-fallback / language notes, "✓ Finished", the
  developer-only Debug chip) sit **above** the scrubber so appearing text never pushes it.
- **⋯**: rows *Voice Settings, Share, Debug* (developer options only); big buttons **Favorites /
  History / Website**.
- **Scrubber** (sentence-precise): fill = progress (weighted by text length; with a local
  voice the thumb moves smoothly inside a paragraph, estimated from the player's time); the
  lighter fill ahead of it is audio already rendered (local voices; Apple speaks live so there is
  none).
  - **Grab the thumb** (±26 pt) and it moves relative to your finger — no jump; touch elsewhere on
    the track and it jumps there. The touch area is the whole capsule height plus its rounded
    leading end.
  - **Fine scrubbing**: slide your finger up away from the track to slow the thumb — < 50 pt 1×,
    50–110 pt ½, 110–170 pt ¼, above that 0.1× ("Fine scrubbing"); changing speed re-anchors, so
    the thumb never jumps, with a light tap.
  - **Snaps to sentences**: release lands on a sentence start. Haptics tick only on boundaries
    you can feel apart: a sentence or paragraph ticks when it is at least 7 pt wide on screen at
    the current speed, so at 1× a long article ticks on paragraphs and the finer speeds tick each
    sentence; either end of the track gives a firmer tick.
  - **The bubble** (a card as wide as the band) shows the speed as a chip (½×, ¼×, Fine; dark
    text on the accent),
    "¶ N of M", then "sentence k of n" in lighter ink, and the sentence's first words. It sits just above the capsule
    and, once the finger slides up, rides 44 pt above the finger so the thumb never covers it; at
    large text sizes it wraps rather than truncating.
  - **Release** seeks to the start of the sentence under the thumb: playing keeps playing from
    that sentence; paused stays paused there (Play resumes from it). A tap on the thumb itself
    isn't a seek.
  - Local voice: playback starts at the synth chunk holding the sentence, offset into its audio
    by characters (chunk boundaries found by counting letters; stitched paragraphs use the stored
    chunk durations), with a 0.25 s lead-in so the first word isn't clipped. Not rendered yet: the
    render queue does that chunk first (then the rest of the paragraph). Apple voice: speaks from
    the sentence's first character.
- **Speed** (1×): applied in place — the current sentence keeps going at the new speed.
  Local voices: a pitch-preserving time-stretch on the player (`AVAudioPlayer.enableRate` /
  `rate`; all audio, including Apple-fallback units, is rendered at 1×), so nothing is re-queued,
  re-rendered or restarted. The Apple voice (AVSpeechSynthesizer can't change a running
  utterance's rate) restarts from the word being spoken. The rate is persisted
  (`reader.rateMultiplier`) and the lock screen's playback rate follows it (and can set it).
- A page played without saving is kept for 7 days after its last play, with its text and its
  spot: after a relaunch it is at the top of the Library's *Pages*, opens in the Reader where it was, and
  Now Playing shows its text.

## Developer options

Debug tools are hidden in normal use: the ⋯ Debug rows (Browse "Debug ›" with Fake extraction
failure; Reader, Now Playing, Library and Favorites sheet "Debug" → Listen debug panel), Voice
settings → Listen debug (and Open full panel), the listen bar's Debug pill / bake overlay, and
long-press ▶︎ → Listen debug panel. The entry points that open the full panel set
`speech.showListenDebug` (Browse's Debug › only fakes an extraction failure; the Debug pill
toggles the bake overlay); the shell's root
presents the panel (`listenDebugSheet`) while no shell sheet is up, and Voice settings and the
Favorites sheet present it over themselves. They show only with **developer options** on (`DeveloperOptions`, UserDefaults `reader.developerOptions`): off by
default in Release builds, on by default in Debug builds. To toggle in any build, long-press the
**version row** at the bottom of Voice settings for 2 s (haptic + "Developer options on/off"
confirmation). A Release build clears a stored "on" once, so a Debug pill left from an older build
can't stick; long-press the version row to turn it back on. UI tests force it with
`-reader.developerOptions NO|YES`. Launch-argument hooks and test-only markers compile only in
Debug builds (`App/LaunchOptions.swift`).

## Current screens

| Screen | Button | Presentation |
|--------|--------|--------------|
| Browser (start page / web page) | — | root |
| Browser → editing the address | ✕ round, right of the field | in place; tap outside or drag down |
| Browser ⋯ / Reader ⋯ / Now Playing ⋯ / Library ⋯ | — | morph panel over the button (same design; rows per surface) |
| Browser toolbar Search | ✕ round, right of the field | in place (editing the address, empty) |
| ⋯ → Website (Reader, Now Playing) | — | closes the sheet (and leaves the library) and shows / loads the page in the browser; audio continues |
| ⋯ → Voice settings (`SpeechSettingsView`) | Done | `.sheet` |
| ⋯ → Share | — | `.sheet` (system share sheet) |
| ⋯ → History (`BrowseHistoryView`) | — (grabber) | `.sheet`, medium/large |
| ⋯ → Favorites / start page Show All / a folder tile (`FavoritesSheet`) | Done (grabber) | `.sheet`, medium/large; folders push inside it |
| Toolbar 📚 / Library (`LibrarySurface`): the home | 🌐 Browser slot | in-place surface (shared bottom chrome); leave restores browse |
| Library → a folder, a book or series, Pages · Show All (`FolderScreen`, `BookScreen`) | ‹ system | push (`navigationDestination`) |
| Move, Save to Library…, Save to Folder…, Change Folder (`MoveTreeSheet`) | ✕ (grabber) | `.sheet`, medium/large |
| Import Book… (Files picker, then `BookImportSheet`), an `.epub` link | Cancel (grabber, except while it works) | system picker, then `.sheet`, medium/large; *Add to* pushes inside it; D13 and refusals are alerts over it |
| Delete Folder…, Rename, New Folder | Cancel | confirmation dialog / alert |
| Reader sheet (`ReaderSheetScreen`): 📄, ⋯ → Reader, a Favorites tile, a Library row or card | *‹ Browser* / *‹ Library* pill, top left | `Sheet` over the surface; pull the header down |
| Now Playing (`NowPlayingScreen`): the bar, the Reader of the playing page, Listen, crash resume | ⌄, top left | `Sheet` over everything; pull the header down |
| Listen debug panel | Done | `.sheet` |
| Speed picker | — | popover |

The browser's own ‹ / › are web-history buttons (the web view also has its edge swipes), not screens.
