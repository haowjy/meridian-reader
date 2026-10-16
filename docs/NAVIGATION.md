# Navigation rule

**If a screen shows ‹, you can swipe back from the left edge. If it shows ✕ (or is a sheet with a
grabber), you can pull it down.** Either gesture must do exactly what tapping the button does.

The two reading sheets have no ✕: each closes with the labelled pill at the top left of its top
bar, the Reader's "‹ Browser" / "‹ Library", Now Playing's "⌄ Library" (named for where it plays
from). Both carry a grabber and pull down from their header, or from
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
  its top: the Move tree, the import sheet (except while it works), History,
  Voice Settings, Downloads, Edit Details. Their *Done*, *Cancel*, *Save* and *Import* are one
  pill, the neutral one the Reader's close pill is (`SheetBarButton`).
- The Reader and Now Playing are the design system's `Sheet` (in place, not a `.sheet` or
  `fullScreenCover`): pulling the header (grabber or the top bar with its close pill) down calls the same close
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

There is no tab bar. The app has two surfaces, swapped by the icon left of the Now Playing bar
(📚 on the browser, 🌐 on the Library): the **Library**, the folder tree, and the **browser**, a
web page or the start page. `BrowseStartView` hosts both (`ShellState.surface`); all chrome is
one bottom band, the same on both (decision D22), and each surface uses everything between the
status bar and it (safe area respected).

**The app reopens on the surface you left** (decision D10): the Library at the folder you were in
(`ShellState.libraryPath`, folders that no longer exist dropped), or the browser on its last page,
reloaded. A fresh install opens the Library. Kept on the device in UserDefaults
`shell.lastSurface` (`SurfaceMemory`). Reopened on the Library, the browser's last page loads the
first time you go there (🌐), and stays remembered until then, across relaunches. UI-test launches
start on the browser unless `-restoreSurface`.

```
[📚] ╭ [art] Now playing title         ⏸ ╮   ← swap over slot 1; the Now Playing bar over 2–5,
     ╰ site   N min left ━━━━━━──────────╯     always there
( 📄 address …                        🎧 )   ← 📄 / 🎧 on readable pages; 🎤 only while searching
[ ‹ ]   [ › ]   [ 🔖 ]   [ 🕘 ]   [ ⋯ ]    ← 5 equal slots, the Library's roles slot for slot
```

**The band is the same on the browser and the Library** (`SurfaceBand`, decision D22): the same
three rows at the same height, every control at the same frame, so swapping surfaces changes
what the controls say and nothing else. Row 1 is the swap (📚 / 🌐, a full slot wide, centred
over ‹) and the Now Playing bar across slots 2–5. Row 2 is the field: the address field on the
browser, *Search Library* on the Library. Row 3 is the toolbar, each slot one role on both:

| Slot | Browser | Library |
|---|---|---|
| 1 | ‹ web back | ‹ up a level (dimmed at the home) |
| 2 | › web forward | › (always dimmed: the Library has no forward) |
| 3 | 🔖 save the page / remove it (held: *Save to Folder…*) | ＋ *Import Book…*, *New Folder* |
| 4 | 🕘 History | 🕘 History |
| 5 | ⋯ | ⋯ |

A slot with nothing to do is dimmed in place, never removed, so nothing shifts.

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
`[‹][›][🔖][🕘][⋯]`, the Library surface `[‹][›][＋][🕘][⋯]`, the Reader
`[🔖][ ▶ Listen  9 min ][⋯]` (the pill spans slots 2–4) and Now Playing `[🔖][⏮][▶︎][⏭][⋯]`.
Each item names its slot (`.toolbarSlot(_:)`); a slot nothing names stays empty, so items never
slide along, every icon in slot N is at the same x and the ⋯ menu grows from the same spot. ⋯ is
never replaced. The Now Playing bar's play/pause is centered over the ⋯ slot too.

- **A new search** is a tap on the address field: it selects the page's address, so typing
  replaces it (Recent Searches show full-bleed, Safari-style); ✕ cancels and restores the page's
  address. Swipe down lowers the keyboard but stays in search mode (typed text and ✕ kept). The
  page stays loaded underneath. ⋯ → *New Search* opens the start page with an empty field.
- **🔖** (slot 3) is the Reader's 🔖 for the page on screen: tap saves it to the Library's top level
  (extracted first; 🔖 spins), or removes it when it is saved (filled, jade); held, it opens the
  Move tree (*Save to Folder…*). Dimmed on the start page. **🕘** (slot 4) opens History.
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
  rows *New Search, Save to Folder… / Remove from Library (🔖), Add to Favorites / Remove from
  Favorites (☆), Share, Reload, Voice Settings, Downloads, Debug ›* (Debug only with developer options on —
  see "Developer options" below), then a row of big buttons **Favorites**, **History**, and
  **Reader** (rightmost, nearest the thumb, like Safari's All Tabs). *Save to Folder…* opens the
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
- **☆ Add to Favorites**: one tap stars the page where it is (a flag, D20; it never moves). A
  page that is nowhere yet becomes a link in no folder; a page played without saving joins the
  Library where it is, with its played text, so it shows in Favorites and the 7-day prune of
  unsaved pages leaves it. A starred page in the Library is a favorite: ☆ then reads *Remove
  from Favorites*, which clears the star and leaves the page where it is (a link ☆ made stays).
  *Remove from Library* clears the star too. A Library row's menu stars the same way, with the
  same toasts, and stars any page in the Library, a book's chapter too.
- **One library**: everything is a page in a folder (or in none). A page is a *link* (an address
  you kept, such as a favorite: no text or audio), *saved* (text and audio kept), or played
  without saving (kept 7 days, shown at the top of the Library's *Pages* as "Not saved", and in
  the bar). *Remove from Library* takes a page out of every list it was in, "Not saved" too,
  even while it plays; it is kept 7 days for what plays and the bar, and comes back only when
  you save it or listen to it again (🎧, the Reader's Listen). There is one page per
  address: saving a favorite saves it in place; unsaving a page in a folder leaves it there as a
  link. 🔖 = saved, ☆ = favorite.
- **The Now Playing bar** (`BandNowPlayingBar` / `NowPlayingBarView` → `NowPlayingBar`) is the
  one thing that shows what you hear: a floating card 8 pt above the field capsule with the page's
  artwork (favicon or a letter tile), its title, the site and the time left (two parts set apart
  by space, the time in lighter ink; at the playback speed, written as rows write it: "9 min left",
  "6 h 10 min left"), a thin progress line along its bottom edge, and
  play/pause centered over the ⋯ slot. It looks the same on the browser, the start page, the
  Library and the Reader sheet. At the end of a page it stays, reading "✓ Finished", and ▶ plays
  the page again. Tap or swipe up → Now Playing; long-press → *Stop Listening* (unloads the page).
  **In the band it is always there, at one height:** with nothing loaded (before the first play
  of a launch, after *Stop Listening*) it shows the page played last, paused (▶ resumes it from
  its place, a tap opens it), and before anything has ever played a greyed *Nothing playing*
  card. On Now Playing, under the Reader sheet (which shows its own bar) and under other sheets
  the band keeps the bar's space empty; while you type in a field the row steps aside with the
  toolbar. The Reader's bar shows only what you hear, and hides on Now Playing, under other
  sheets and after *Stop Listening*.

**Start page** (no page loaded), Safari-style:
1. **Favorites**: starred pages and folders (favicon, or a
   coloured letter tile when there is no usable favicon, with the title below), then its
   folders as folder tiles; 4 per row, up to 8. Show All → the Library's Favorites tab. A page tile
   opens the page (a link in the browser, a saved page in the Reader); a folder tile opens it in
   the Library. Long-press a page tile → Rename… / Remove from Favorites.
2. **Recent Searches** (local, newest first, Clear).

## The Library

The Library is a stack of screens in a `NavigationStack` (`LibrarySurface`, the path is
`ShellState.libraryPath`): the home, then folder → folder at any depth. ‹ and the edge swipe go
back up, as does the band's ‹ (dimmed at the home). The home has **Everything / Favorites** tabs
at the top; *Search Library* is the band's field. Each tab filters
the same mixed list: folders and pages share a single list, with no section headings. Favorites
are independent stars. On Favorites and in search results a row in a folder shows that folder's
path in place of its site, and a folder opens in its place, under its parents, so ‹ goes to its
parent. ⋯ → **Favorites** (and the start page's Show All) opens the home on Favorites;
going to a place in the Library (Now Playing's ⋯ → *Go to …*, a favorite folder's tile, an
imported book) opens it on Everything, where every place shows; 📚 comes back to the tab you
left. The tab is remembered with the surface. The band is the browser's (above): 🌐 beside the Now Playing bar, the search
field, `[‹][›][＋][🕘][⋯]`. ＋ is *Import
Book…* and *New Folder*, both made in the folder on screen (a book's too). 🌐 shows the browser as
it was; 📚 there comes back to the same folder. The
⋯ panel follows the screen on top (below), always with big buttons **Favorites**, **History**,
**Browser**, and with developer options on a last row *Debug* (the listen debug panel); nothing
in it acts on the page under the Library. History closes the Library first; Browser is the same
swap as 🌐.

```
Library
Everything  Favorites
▣ Pride and Prejudice          ↓  ▶  cover, download state and play action
▣ Tide Tables                  ↓  ▶
▣ Finance ★                    ↓  ▶  location-independent favorite
[i] Seven-Day Yield ★          ↓  ▶
```

Secondary lines (a row's second line, the bar's, a header's details) never join their parts with
a separator character: the parts sit apart by space (`DetailLine`, `Spacing.s`, growing with the
text), the first in secondary ink and the rest in the lighter tertiary ink; a playing row's status
is in the accent. A row's second line is always one line: the first part (the site) truncates
when it is short of room, and at accessibility text sizes the row shows its status alone there
(VoiceOver still reads every part). A section's count is its
own lighter label after the title (*Pages* then *48*). VoiceOver reads the parts joined with
commas.

- **The home** (`LibraryHomeView`): Everything shows top-level folders and pages in no folder;
  played-but-unsaved pages remain visible as *Not saved*. Favorites shows all starred folders
  and pages wherever they live. Search filters folders and pages across the tree in either tab,
  folders by name, then pages by title (the newest first among equal titles); a result keeps its location and shows the path (one at the top level keeps its own second
  line). Favorites' rows carry no ★, since every one is a favorite. The old Favorites folder is migrated into star
  flags; direct pages become loose and nested folders stay nested. Rows are the compact two-line
  rows, with a Download state and Play (pages: the two-line row below). The bar's ▶ resumes what you last heard, and a folder row's ▶
  resumes its own pages without opening it (D14). A first-run empty Library shows *Find something
  to listen to*, naming the band's 🌐 and ＋ by their symbols, with *Browse the web* and *Import a
  book* on one action row. The home has no navigation bar; rows scrolled up pass under a paper
  band behind the status bar, not under the clock. The home is the
  top level: its ⋯ is *Sort ›* (the order of the pages in no folder: *Manual*, *Newest*, the
  default, or *Title*), *Import Book…, New Folder, Voice Settings, Downloads*.
- **A folder** (`FolderScreen`, books and series included): its title and counts,
  subfolders first (by their order), then pages by the folder's sort. A folder with pages that
  play has the play header (decision D15): how far through (a bar across the content width, with
  "38%" and "6 h 10 min left" on one line under it), the round play button (*▶ Play* before
  anything in it has played, *▶ **Continue** 3 of 7*, or jade bars *Playing 3 of 7*: tap pauses),
  stretched so it, *⏮ From Start* and a round icon-only Download (⬇, a ring while it downloads,
  ✓ once downloaded, the same glyph as the rows' Download) span the width on one row. The row
  never wraps (decision D21): short of room it drops the place ("3 of 7"), then shows the
  symbols alone (VoiceOver and the large content viewer keep the names); *From Start* never
  changes its name. It plays its own pages
  (not its subfolders') in the order shown, page to page, link pages skipped.
  Every block sits on the page margin, so the bar, the buttons and the cards share both edges.
  **Edit** (top right), or *Select* in a row's
  long-press menu (Edit with that row selected), puts check circles on the rows, and drag handles
  (pages only when the sort is *Manual*); the toolbar keeps its five slots and shows
  *Move to…* (📁, slot 1), *Mark as Finished* (✓, the middle) and *Remove* (🗑, ⋯'s slot) as
  symbols for the selection. *Remove* takes the selected pages out of the
  Library at once, then asks before deleting the selected folders, which stay selected until
  their delete is saved (*Cancel* keeps them selected). ⋯: *Sort ›, New Folder Inside, Import
  Book…, Rename, Edit Details, Move to…, Delete Folder…, Download Folder, Delete Downloads,
  Voice Settings, Downloads* (a book's say *Delete Book…* and *Download Book*). Every ⋯ ends
  with the same rows in the same order: *Download, Voice Settings, Downloads, Debug*.
  The screen's name shows once, in its header; the navigation bar shows it only once the header
  has scrolled under the bar. An empty folder's header has no counts; the list says
  *Move pages here, or save them here from the Reader's 🔖* (the toolbar's symbol).
  A favorite is still an ordinary page or folder and keeps the same actions and location.
- **Edit Details** (a folder's or book's ⋯, or a folder, book or series row's long-press menu)
  opens a sheet (`FolderDetailsSheet`): the cover (a letter tile without one), **Name**,
  **Author**, and *Choose from Photos*, *Choose from Files* (images) and *Remove Cover*.
  *Cancel* changes nothing; *Save* stores all three at once. A picked picture is kept as a
  600 px JPEG thumbnail, as a book's cover is. A folder with a cover or an author (a book has its
  file's) shows the detailed header: the cover beside the title, the author before the counts
  ("A. Writer   2 folders   3 pages"), then the same bar, one-line progress and buttons, on the
  same edges. Its row shows the cover in place of the folder symbol, and the author under the
  title until a page in it has played. Details change only the look: its sort, Edit, drags and
  drops are unchanged. Clearing the author and removing the cover brings back the plain header.
- **Importing a book** (*Import Book…*: ＋, the home's and a folder's ⋯, the empty Library's
  card) opens the Files picker for EPUBs. The picked file is copied into the app and the import
  sheet (`BookImportSheet`, medium, grows to large) comes up at once: the cover, title, author,
  file and chapter count once read; a progress line ("Reading chapters… 4 / 9"); **Add to**, the
  folder whose screen it started from (else the Library), with *Change*, which pushes the Move
  tree inside the sheet and works until the book is being saved (the book is saved there; a
  chosen folder deleted meanwhile shows as *Deleted folder* and the import stops, saying so); the
  first chapters and what is skipped for listening. It can't be pulled down
  while it works; *Cancel* stops it and keeps nothing. Done, it closes on the book's screen,
  with *▶ Play*, which starts the first chapter that plays. A refusal says why in one line with OK: copy-protected (DRM),
  fixed layout, too large, or not a readable EPUB; so does an import or *Replace* whose save
  fails, which keeps nothing. A book already in the Library asks *“Title”
  is already in the Library*: *Replace* (the same folder, its name, place and order kept,
  positions kept where chapters match; *Add to* then shows where it is and can't change) or
  *Cancel* (decision D13). *Replace* finds the book's chapters wherever they were moved and brings
  them up to date there; a new chapter goes into the book just after the chapter before it;
  chapters the file no longer has are deleted if they are still in the book; pages moved into
  the book from elsewhere are never touched (decision D19). An `.epub` link in the browser downloads the book (a toast while it does) into
  the same sheet, which waits for *Import* (top right), going to the Library unless changed. One
  import at a time: a book whose download finishes while the import sheet is up isn't imported,
  and a toast over the sheet says so.
- **Deleting a folder** (a book or series as any other) offers only *Delete Folder and Contents*
  and Cancel; there is no keep-contents choice. The question says what it holds ("2 folders, 27
  pages") and "Stops what's playing." when the playing page (or one a
  waiting merge would move it onto, `LibraryStore.keysWaitingToMerge`) is inside
  (`FolderDeletePrompt`). Pages and their audio go together: the audio is deleted once the delete
  is saved, and a delete that can't be saved leaves both (and says so, below). The folder's row
  stays until the delete is saved, whichever way it was asked (the row's swipe or menu, ⋯ *Delete
  Folder…*, Edit's *Remove*); *Cancel* leaves everything as it was. Deleting the folder whose
  screen is open goes back to the screen above it.
- **A book or series is a folder** (decision D19): the same screen, rows and rules as any
  folder. Importing makes it with one page per chapter, first in the book's order (its sort is
  *Manual*); after that the order is yours: Edit, drags and *Sort* change it, chapters move out,
  and pages and subfolders move in. Its cover and author are folder details (the detailed
  header). Its chapters use the ordinary page row, as pages inside any folder; front matter still
  shows dimmed with "Skipped" and no ▶ (it still opens for reading). A series' unfetched pages
  use the same link row as elsewhere. What sets it apart is only where it
  came from: *Replace* finds it by its file (above), a series' link chapters are fetched when
  playback reaches them, the Now Playing bar names it as the source of its chapters, and its
  finished chapters lose their audio (D7).

**Rows** are `ListRow`s, compact and two lines for every kind. A folder row's second line is
what is in it ("2 folders   3 pages", "Empty"), in Edit too; one whose pages play shows its
place and time left there instead. Every row's separator starts at its title. Every row that can be
downloaded has a Download control (⬇, a ring filling while it downloads, ✓ once downloaded) and
▶ side by side at its trailing edge, centred on the row's height. A page row (a chapter too) is
exactly two lines (decision D21): its title on one line, truncated, then one short line of what
it is and where it stands ("5 min", "6 min left", "✓ Finished" with a ✓ symbol, "Skipped", "Playing"), with a
small thumbnail as tall as the two lines. In a folder that line is the status alone (the header
already names the author or site); on the home and in search the site or path comes first. A
tap opens the row; its menu is a long-press (decision D11), and a
long press that moves lifts the row into a drag (below); swipe left removes (a page's *Remove*
takes its row out of every list once it is saved, and leaves it, with a toast, when it can't be). Rows that can play keep their ▶ (`PlayStateButton`): it plays the row (replacing what
plays) or pauses / resumes it when it is what you hear, and never navigates. The playing row is
tinted, with still or moving bars and "Playing" (or "Paused") in the accent. A page or chapter
whose audio is downloaded in the voice selected now shows ✓ in its Download control (VoiceOver:
"Downloaded"); a folder, book or series row does when every page its download covers is
(decision D16). ▶ / ⏸ and a folder's › share one trailing column, centred on the ⋯ slot as the
bar's ⏸ is (a skipped page keeps the column empty, so Download lines up); a folder's count sits
just before its ›. On a folder screen every row's menu starts with
*Select*.

**Folders play like books** (decision D15). Playing a page that is in a folder (its row's ▶, the
Reader's Listen, 🎧 on its page, the folder's own ▶) carries on through the folder, page to
page, then stops; a page in no folder plays to its end and stops. Every folder plays in its sort,
which is yours (a book's starts as the book's order). Link pages are passed over (a series'
are fetched), and so are pages marked *Skip in Playback*. The page that last played is the folder's place: its
row shows the place and the time left and its ▶ resumes there, as a book's does; before
anything in it has played, the first page starts where it was left. Now Playing's "Playing
from" names the folder.

**Dragging rows** (decision D15), on the home and folder screens, without Edit: a
long press lifts a row (its menu, which the press opened, goes as it moves). Let go on a folder
row (its middle, for a folder) to file it at the end of that folder; the folder lights up in the
accent while it takes the row, with a tick. Let go between rows to place it there, a line
marking the place: a page among pages, a folder among folders (over a folder row's top or bottom
quarter); placing a page makes its folder's sort *Manual* (the top level's too, until the home's
⋯ → *Sort* picks another), numbered first as it was shown. A row lands with a success tick; a refused one with an error buzz. A book or
series takes drops as any folder, and its chapters lift as any page (decision D19). A folder
dragged over itself or a folder inside it is refused (the drag shows ⊘); rows on the home's
Favorites tab or in search results (gathered from across the tree), a page played without saving
and rows in Edit don't lift. The list doesn't scroll by itself while a row is dragged.

| Row | Tap | Trailing | Menu (long-press) | Swipe left |
|---|---|---|---|---|
| Folder, book or series | opens it (push) | Download state; ▶ when its pages play, otherwise › | *Continue, Play from Start* (when its pages play)*, Download* (when it has pages)*, Add to / Remove from Favorites, Move to…, Rename, Edit Details, Delete… | Delete… |
| Saved page (including a chapter) | the Reader (Now Playing if it's what you hear) | Download state; ▶ (not on pages skipped in playback) | *Play from Here* (in a folder)*, Move to…, Mark as Finished / Unfinished, Mark All Above as Finished, Skip in Playback / Play in Playback* (in a folder)*, Share, Download, Delete Downloads* (when it has audio)*, Remove from Library, Add to / Remove from Favorites* | Remove |
| Page played without saving ("Not saved") | the Reader (Now Playing if it's what you hear) | ▶ | *Save, Share, Add to Favorites* | — |
| Link page | the page, in the browser | — | *Move to…, Share, Download, Remove from Library* | Remove |

*Download* isn't offered while that page or folder is downloading already (decision D16, below).

**Downloads** (decision D16): *Download* on a page, a folder, a book or a series (its row's
long-press, its Download control, a folder's ⋯ as *Download Folder* or *Download Book*, the Reader's ⋯) makes it
ready to play offline: a link page's text is fetched out of sight and the page saved where it is,
then its whole audio is rendered ahead in the on-device voice selected (Kokoro). A folder covers
its own pages in its order (not its subfolders'), a book or series its chapters that play and
aren't finished, one page at a time. A toast says *Downloading “…”* with *Show*, floating just above the
bottom chrome (above the Now Playing bar, never over it), as every toast does. Nothing is modal:
while downloads run, a 2 pt jade line along the top edge of the bottom chrome (the browser's, the
Library's, the Reader's) fills as they get on, and fades when nothing is queued, everything queued
is paused, or no on-device voice is selected (VoiceOver reads it as *Downloads, N percent*, a
button that opens the list). Rendering happens while the app is in front: the page playing and the
chapter after it always go first, a hot phone or Low Power Mode holds it, and in the background
downloads wait (only what plays renders there, in bursts; LISTEN_PLAYBACK.md).

```
Downloads                                       ( Done )
Queued  2                                  Pause All
▣  Pride and Prejudice                       (◔⏸)   the ring: how far; ⏸ pauses, ↓ resumes
   Kokoro Heart   4 of 12 chapters   38%
Downloaded  1
[i] Coupon Basics
   Kokoro Heart   12 MB
12 MB on this iPhone
Different Voice  1
[i] Seven-Day Yield
   Kokoro Bella   9 MB
   ( ↻ Re-download )  ( ✓ Keep )
```

**⋯ › Downloads** (`DownloadsSheet`, every ⋯ panel: the browser's, the Library's on every screen,
the Reader's, Now Playing's; medium, grows to large) lists, in sections shown only when they have
rows: **Queued** (the download rendering now and those waiting, *Pause All / Resume All*, each
row's ring pausing or resuming it), **Downloaded** (each with the room it takes, the total under the
section, on the cards' edge), and **Different Voice** (done, but rendered in another voice than the one selected
now). Every row names its voice ("Kokoro Heart"); its parts are set apart by space, never a dot.
After a voice change a finished download moves to *Different Voice*, with **Re-download** (renders
it again in the voice selected; the old voice keeps playing until each paragraph is replaced) and
**Keep** (stays as it is, counted as done, still named by its own voice), on one action row (symbols alone when short of room, D21). A row opens what was
downloaded (the Reader, or the Library at the folder); swipe left *Remove* takes the download off
the list and its audio off the phone (not the audio of what you hear). The list holds downloads
of what is in the Library: removing a page from the Library, or deleting a page or folder, takes
its download off the list too (a removed page's audio stays, ephemeral); its long-press menu has
*Pause / Resume*, *Re-download*, *Keep* and *Remove* as they apply. While Apple's voice is
selected nothing renders: queued downloads say *Waiting for an on-device voice*, with *Voice
Settings*. *Delete Downloads* on a page or a folder deletes its audio and its download. A page
that couldn't be fetched or rendered is counted ("2 couldn’t download"), and *Re-download* tries
again. The list is kept on the device (`Downloads.json`) and goes on after a relaunch. With
nothing in it, a card says *Nothing downloaded*: tap ⬇ on a page, a folder or a book in the
Library.

**The Move tree** (`MoveTreeSheet`): one sheet for *Move to…*, the browser's ⋯ → *Save to
Folder…* and 🔖's *Save to Folder…*; the import sheet's *Add to* pushes the same list inside it. The whole tree as one indented list (medium, grows to large): *＋
New Folder* (made at the top level, and the item goes in it), *Library (no folder)*, then
every folder, depth first. One tap files; ✓ marks the current place; a folder's
long-press offers *New Folder Inside* (made in it, and the item goes in that). *Library (no
folder)* files the page in no folder, out of the folder it was in; an ordinary 🔖 or *Save* keeps a page's folder. Every folder is a
destination, books and series too; a folder being moved, and everything inside it, can't be
picked. The tree closes
once what was picked is saved; a pick, or a *New Folder*, that can't be saved leaves it up under
the toast, to pick again or *Cancel* (in the import sheet, a *New Folder* that can't be saved leaves the
tree up the same way). The browser's *Save to Folder…* closes it on the pick, since the
page is extracted first (⋯ spins).

**A change that can't be saved** (a move, *New Folder*, *Rename*, *Edit Details*, *Sort*, a drop on a folder or
between rows, a
mark, *Remove*, a delete, ☆ or a favorite tile's *Rename* / *Remove*, saving or unsaving with 🔖
(the browser's, the Reader's or Now Playing's), *Save to Folder…*, ⋯ → *Save to Library* / *Remove from Library*) isn't stored: the
library reads as it did before it, and a toast says so ("Couldn’t move", "Couldn’t save") where
a success would have shown. *Remove* of several pages is one change: all go, or none. A folder's
screen doesn't follow a move that didn't happen, the Move tree stays up, ☆ shows no "Added to
Favorites", and 🔖 keeps what it showed. In Edit, the selection stays when its change can't
be saved; Edit's *Remove* is two changes, the pages first and then, after the question, the
  folders, so a folder delete that can't be saved leaves the folders selected but doesn't bring back
  pages already removed. The toast shows over the Move tree, the import sheet
and Now Playing too. Listening goes on being kept meanwhile: where you are in a page, when you last played it and
whether you finished it are stored once saving works again, even across failed changes.

**Library search** is the band's field, the same session as the browser's (`SearchSession` in
`SurfaceBand`, `ShellState.librarySearch`): focusing it hides the band's first row and
toolbar so the field sits above the keyboard with a round ✕ (on a folder screen it goes back to
the home first, the list it filters); swipe-down / scroll lowers the keyboard but **stays in search
mode**; ✕ exits and clears the filter. While there is text, the home's list holds the folders
(by name, or a book's author) and pages (titles, sites, excerpts) that match, across the whole
tree in the selected tab, each with its location.

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

**The two sheets share their chrome** (decision D24), so Listen turns the Reader into Now Playing
with nothing moving but what has to: the same top bar (`SheetTopBar`: the close pill at the top
left, ☝︎ at the top right, at the page margin), 🔖 in slot 1 and ⋯ in slot 5 of the bottom row,
and the same ⋯ menu (Now Playing adds *Go to*). UI tests check the frames match. They differ
where the job does: Now Playing is on the player's palette (it is what you hear, over
everything), its middle slots are the transport (⏮, the round ⏸ / ▶, ⏭) where the Reader has
Listen, it has the scrub capsule with the speed and the status notes, and its text follows the
audio under a title card (the Reader's sits under a heading and never moves by itself); the
Reader shows the Now Playing bar of another page above its row.

### The Reader sheet

```
┌──────────────────────────────────────┐
│                 ───                  │ ← grabber
│ ( ‹ Browser )                  (☝︎)  │ ← the pill names what is underneath
│ Notes on Tides                       │ ← title, then "site   9 min"
│ … serif text on paper …              │
│ ╭ Now Playing bar ──────────────╮    │ ← what you hear (always another page)
│ [🔖]  [ ▶  Listen  9 min ]  [ ⋯ ]    │ ← this page's own ▶, a pill over slots 2–4
└──────────────────────────────────────┘
```

The heading is always the serif title, then the site and length under it. When the article's own
first heading repeats the title, that heading takes the title's look and the source line moves
under it. The reading style always wins over a page's own styles (an extracted page's
stylesheets are left out), and an extracted title drops a trailing site name ("Speech synthesis
- Wikipedia" reads "Speech synthesis").

- **A sheet over the surface that opened it** (`ReaderSheetScreen`, `ShellState.reader`). From
  the browser (📄, ⋯ → Reader, a Favorites tile) the pill reads *‹ Browser*; from the Library
  *‹ Library*. The pill, the grabber and a pull down all close it to exactly where you were.
- **Listen** reads *▶ **Listen** 9 min*, *▶ **Resume** 6 min left* for a page part-way through
  (at 1×, written as rows write it, "1 h 5 min left" past the hour; the time in regular weight after the semibold title, left out when the pill is short of room
  at large text sizes), or *▶ Listen Again* for a finished one. It starts at the page's saved spot, makes the page what you
  hear (replacing what plays) and turns the Reader into Now Playing in place, where the Reader was
  (decision D2):
  - **At the Reader's top** (its first line of text not yet scrolled above the top of the reading
    area, so the title may be part way up), Now Playing opens at its top, the title card in full.
  - **Scrolled into the text**, the same line stays at the same place on screen, though Now
    Playing's title card is not the Reader's heading; the card is then partly or wholly above the reading area.
  - **When that place can't be reached** (past either end of Now Playing's page), the page goes
    as far as it can that way, so the line stays in view as near its place as possible. Keeping
    the line in view wins over showing the card in full.

  Now Playing sets that position once its page is laid out and holds it while the layout
  settles (the title card measured, the header, a text size change: each keeps the same line).
  It drops it if you drag, scrub, Jump to Audio, the audio moves on or the page reloads first. ☝︎ in the top bar, then a tap on a paragraph, listens from that
  paragraph (a hint banner with Cancel sits above the text meanwhile, at the page margin; the text
  moves down under it rather than being covered). While ☝︎ is on, each
  paragraph is a button to VoiceOver, *Paragraph N*, hint *Plays from this paragraph*.
- **A page part-way through opens at its saved spot**: the sentence where listening stopped
  (where *Resume* starts) is in the middle of the text and underlined, without a scroll of your
  own, and stays there while the layout settles (the header, a text size change) until you drag.
  A page not yet started, or finished, opens at its top.
- **After that the Reader never scrolls by itself** and has no speed or skip buttons; reading
  text never moves under you. A text size change (Dynamic Type) keeps the line at the top of the reading
  area where it is, to the character; a page at its top stays at its top. Now Playing does the
  same, or, while it follows the audio, centres the spoken sentence again.
- 🔖 saves / unsaves (tap; filled = saved), or files the page (long-press → *Save to Folder…*,
  the Move tree: saved there, or moved there when already saved); it keeps the screen and
  playback as they are.
- **⋯** (slot 5, the browser's ⋯ spot; Now Playing's is the same): rows *Save / Remove from Library, Move to…* (a saved
  page)*, Add to Favorites, Share, Download* (a saved page not downloading already)*, Voice Settings,
  Downloads, Debug* (developer options only); big buttons
  **Favorites / History / Website** — *Website* (the Reader off) shows the page in the browser,
  wherever the Reader was opened from; from the library, the library closes first. Playback
  never stops.
- The text sits between the header and the bottom row, so its first line starts below the close
  pill and its last line scrolls clear of the bottom row (UI tests check both).

### Now Playing

```
┌──────────────────────────────────────┐
│                 ───                  │ ← grabber
│ ( ⌄ example.com )              (☝︎)  │ ← the Reader's top bar; the pill names where it
│                                      │   plays from
│ ╭ [art] Title                      ╮ │ ← the title card, scrolls with the text
│ ╰       example.com   9 min left   ╯ │
│ … serif text, dimmed; the spoken     │
│   paragraph in full ink, the         │
│   sentence underlined …              │
│            ( Jump to Audio )         │ ← after you scroll away
│ Preparing next…                      │ ← status notes, above the scrubber
│ ( ━━━━━●━━━━░░░░──           1× )    │ ← the scrub capsule, the speed at its end
│ [🔖]  [⏮]  (⏸)  [⏭]  [ ⋯ ]          │ ← 🔖 and ⋯ as in the Reader; the round ⏸ / ▶
└──────────────────────────────────────┘
```

- **Opens from** the bar (tap, swipe up), from opening the Reader of the page that is playing,
  from Listen in the Reader (in place, D2) and from crash resume. It presents over everything
  (`ShellState.isNowPlayingPresented`) and holds no article of its own: it shows what you hear.
  **The close pill or a pull down (on the header, or on the text at its top) shrinks it into the
  bar**, back on
  what was underneath (the browser, the Library, or a Reader of another page), untouched.
- **It looks like a player, not the Reader**: deep jade in light and dark mode alike (the
  `Palette.player…` tokens), with light status bar content and a heavier dim on the strip above
  it. While a finger pulls it down the dim lifts, but the strip under the status bar stays as dark
  as at rest until the sheet has gone, so the clock stays readable. A **title card** at the top of the text (it scrolls with the text) shows the artwork, the
  title, and the site and time left as two parts (*✓ Finished* at the end). The text keeps the Reader's serif and
  margins in **lyrics style**: the spoken paragraph in full ink, the others dimmed, no tint box
  (a paragraph pressed while ☝︎ is on is in full ink too).
  The *Jump to Audio* pill is light with dark text; the scrub capsule, the bubble, the jump
  hint, the ⋯ panel and the speed popover sit on the player's colours. The Reader stays on paper. A plain-text article (no
  reading HTML) shows its paragraphs on the same reading page, in both, so everything below
  applies to it too.
- **The close pill names where it plays from** (*⌄ Pride and Prejudice*; VoiceOver: *Close Now
  Playing*, *Playing from …*): the folder the page is in, a book, a series or one you
  made; *Library* for a saved page in no folder; the site for a page you haven't saved. Tapping
  it only closes. **⋯ → *Go to <name>*** (the first row) closes Now Playing onto the Library at
  that folder, or the Library's home, on Everything; for a page that plays from its site, ⋯ → *Website* opens it in
  the browser.
- **☝︎** (top right, as in the Reader), then a tap on a paragraph, plays from that paragraph.
- **🔖** (slot 1, as in the Reader) saves / unsaves (tap) or files the page (long-press →
  *Save to Folder…*, the Move tree); saving never touches playback.
- **The text follows the audio.** It opens with the spoken sentence near the middle (the
  paragraph, until the sentence is worked out a moment later), from the bar, from opening the
  page that is playing and from crash resume; Listen in the Reader opens where the Reader was
  instead (D2). On each new paragraph it scrolls its spoken sentence near the middle; in a
  paragraph too long to stay on screen, it does so again whenever the spoken sentence leaves the
  visible text (the `Motion.standard` spring; a jump under Reduce Motion). The sentence, not the
  paragraph, goes to the middle: a long paragraph's middle can be a screen away from what is
  being read. The spoken paragraph lights up to full ink while the one before dims (a short
  fade; none under Reduce Motion), and the current sentence is underlined in the accent, as in the Reader (per chunk on
  engines that report only chunk starts; no underline before iOS 17.2). Drag the text and following stops (a pull of the sheet from the text's top
  doesn't move the text, so following goes on); a *Jump to Audio* pill floats over the text just
  above the controls (no arrow: the spoken sentence may be above or below).
  Tap it (or start another page) and following resumes. Scrubbing scrolls to the paragraph under
  the thumb.
- **At the end** it stays on the page: the text stays, all of it in full ink, the title card
  says "✓ Finished" where the time left was (where the Reader shows a page's length), and ▶
  plays the page again.
- **Controls** (today's listen rows): the scrub capsule (the speed at its trailing end) and
  `[🔖][⏮][▶︎][⏭][⋯]` in the browser's five-slot grid (🔖 under ‹, ⏮ under ›, ▶︎ under 🔖, ⏭
  under 🕘, ⋯ under ⋯). ▶︎ / ⏸ is a
  64 pt round button (accent fill, dark glyph; fixed size, like the toolbar glyphs). The row stays
  44 pt, so every slot sits where it does on the other surfaces; the disc overhangs it. ⏮ ⏭ and
  headphone / lock-screen skips are paragraph skips (D4). A sideways swipe on the row skips too.
- **Status notes** ("Preparing next…", Apple-fallback / language notes, the
  developer-only Debug chip) sit **above** the scrubber so appearing text never pushes it.
- **⋯**: the Reader's menu for the page you hear, after *Go to <name>* (when it plays from a
  folder or the Library): *Save / Remove from Library, Move to…, Add to Favorites, Share,
  Download, Voice Settings, Downloads, Debug*; big buttons **Favorites / History / Website**.
- A **download progress line** runs along the top edge of the bottom band while downloads run,
  as on the other surfaces, in the player's accent.
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
- **Speed** (*1×*, at the end of the scrub capsule; a tap opens the list): applied in place — the current sentence keeps going at the new speed.
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
failure; Reader, Now Playing and Library "Debug" → Listen debug panel), Voice
settings → Listen debug (and Open full panel), the listen bar's Debug pill / bake overlay, and
long-press ▶︎ → Listen debug panel. The entry points that open the full panel set
`speech.showListenDebug` (Browse's Debug › only fakes an extraction failure; the Debug pill
toggles the bake overlay); the shell's root
presents the panel (`listenDebugSheet`) while no shell sheet is up, and Voice settings present it
over themselves. They show only with **developer options** on (`DeveloperOptions`, UserDefaults `reader.developerOptions`): off by
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
| ⋯ → Website (Reader, Now Playing) | — | closes the sheet (and leaves the library) and shows / loads the page in the browser; audio continues |
| ⋯ → Voice Settings (`SpeechSettingsView`) | Done | `.sheet` |
| ⋯ → Share | — | `.sheet` (system share sheet) |
| ⋯ → History (`BrowseHistoryView`) | Done (grabber) | `.sheet`, medium/large |
| Band 📚 / Library (`LibrarySurface`): the home | 🌐 beside the Now Playing bar | in-place surface (shared bottom chrome); leave restores browse |
| Library → a folder (a book or series too) (`FolderScreen`) | ‹ system | push (`navigationDestination`) |
| Move to…, Save to Folder… (`MoveTreeSheet`) | Cancel (grabber) | `.sheet`, medium/large |
| Import Book… (Files picker, then `BookImportSheet`), an `.epub` link | Cancel (grabber, except while it works) | system picker, then `.sheet`, medium/large; *Add to* pushes inside it; D13 and refusals are alerts over it |
| Delete Folder…, Rename, New Folder | Cancel | confirmation dialog / alert |
| Edit Details (`FolderDetailsSheet`) | Cancel / Save | `.sheet`; the Photos and Files pickers over it |
| Reader sheet (`ReaderSheetScreen`): 📄, ⋯ → Reader, a Favorites tile, a Library row or card | *‹ Browser* / *‹ Library* pill, top left | `Sheet` over the surface; pull the header down |
| Now Playing (`NowPlayingScreen`): the bar, the Reader of the playing page, Listen, crash resume | *⌄ <playing from>* pill, top left | `Sheet` over everything; pull the header down |
| Listen debug panel | Done | `.sheet` |
| Speed picker | — | popover |

The browser's own ‹ / › are web-history buttons (the web view also has its edge swipes), not screens.
