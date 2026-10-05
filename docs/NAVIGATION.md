# Navigation rule

**If a screen shows ‹, you can swipe back from the left edge. If it shows ✕ (or is a sheet with a
grabber), you can pull it down.** Either gesture must do exactly what tapping the button does.

The two reading sheets have no ✕: the Reader closes with its labelled back pill ("‹ Browser",
"‹ Library"), Now Playing with ⌄. Both carry a grabber and pull down from their header, which does
exactly what that button does.

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
  Keep the bar visible and stable; that gives the standard push/pop look.
- Don't build swipe-back by hand. Push with `NavigationStack`; with the system back button it just
  works, with a custom one add `.edgeSwipeBack()`.
- A custom back control should just `dismiss()`; put "leaving" side effects in `onDisappear` so
  the swipe and the tap stay identical. No screen saves the listening position: the playback
  session does, through `ListeningProgressRecorder` (`LISTEN_PLAYBACK.md`).

## ✕ = modal + swipe-down

- `.sheet`: swipe-down is built in (show the grabber). A Done/Cancel/✕ button is optional.
- The Reader and Now Playing are the design system's `Sheet` (in place, not a `.sheet` or
  `fullScreenCover`): pulling the header (grabber, back pill or ⌄ row) down calls the same close
  action as its button. Closing never stops audio: the Now Playing bar shows what is playing. The
  drag starts only on the header, so it never competes with scrolling, text selection or ☝︎ taps.
  The header and the bottom row never hide, so the header is always there to pull.
- It moves like a system sheet: it rises from the bottom and leaves the same way. The surface
  stays as it is underneath (the page or start page, the Library list), so the pull reveals
  where you're going back to: the sheet follows the finger (up only with rubber-band resistance;
  a drag that starts sideways leaves it in place), shrinks slightly, and the dim behind it lifts.
  Released far enough or flung, it carries on off the bottom at the finger's speed; otherwise it
  springs back. Under Reduce Motion it fades in and out instead. What is under a sheet takes no
  touches until it has gone.

## The app is a browser (no tab bar)

There is no Saved | Browse tab bar anywhere. `RootView` shows `BrowseStartView`; all chrome is one
bottom bar, and the page uses everything between the status bar and it (safe area respected).

```
╭ [art] Now playing title              ⏸ ╮   ← the Now Playing bar (once something has played)
╰ site · N min left ━━━━━━━━──────────────╯
( 📄 address …                        🎧 )   ← 📄 / 🎧 on readable pages; 🎤 only while searching
[ ‹ ]   [ › ]   [ 🔍 ]   [ 📚 ]   [ ⋯ ]    ← 5 equal slots (slot 4 = Library↔Browser)
```

**One bottom-chrome design**, shared with the Reader and Now Playing so the bottom of the screen
barely changes between them
the bottom of the screen (`Features/DesignSystem/Chrome/BottomChrome.swift`): the band
(`bottomChromeBand`: 12 pt margins, 8 pt top padding, system bar material through the home
indicator), the field capsule (`bottomChromeField`: 44 pt, chrome-coloured capsule; 36 pt body-size controls
inside, like 🎤), and the toolbar row (`BottomToolbarLayout` + `toolbarIconFrame`: 44 pt, plain
19 pt glyphs). With larger text the capsule and its controls grow (up to 1.5×) instead of
clipping; toolbar glyphs keep their size and show in the large content viewer on long press.
Every control takes taps in at least 44 × 44 pt (`tapTarget`), whatever its drawn size: the
address-field 📄 and 🎧, the ✕ beside a search field, the Now Playing bar's play/pause, the
capsule's 36 pt controls. **Five equal slots, evenly spaced, one grid for every row:** Browse is
`[‹][›][Search][Library][⋯]`, the Library surface `[ ][ ][Search][Browser][⋯]`, the Reader
`[🔖][ ▶ Listen · 9 min ][⋯]` (the pill spans slots 2–4) and Now Playing `[1×][⏮][▶︎][⏭][⋯]`. Slot 4 is the Library↔Browser swap (📚 on Browse, 🌐 on Library — same
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
  replaces it; if extraction fails or finds too little text, 🎧 goes back to grey and a toast
  says "Nothing to listen to on this page"; Stop Listening, any other ▶ / ⏸ or another 🎧 while
  it extracts cancels it, silently); jade with moving bars when this page is playing
  (tap: pause); jade with still bars when it is loaded and paused (tap: resume). It never
  navigates.
- **⋯** opens a Safari-style menu panel that grows out of the button (covers the ⋯, no arrow):
  rows *New search, Save article / Remove from Saved (🔖),
  Bookmark / Remove Bookmark (☆), Share, Reload, Voice settings, Debug ›* (Debug only with
  developer options on — see "Developer options" below), then a row of big
  buttons **Bookmarks**, **Saved**, **History**, and **Reader** (rightmost, nearest the thumb,
  like Safari's All Tabs). The Reader toggle is disabled on the start page and on pages that
  aren't readable; on a readable page tapping it switches into reader mode. Actions that present
  something (Share, Voice settings, Bookmarks, Saved, History) run after the panel has closed.
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
- **Bookmarks vs Saved**: a *bookmark* is a page in the library's Favorites folder: usually a
  link (URL, title, favicon — e.g. a story's index page) with no text or audio. A *saved article*
  is a saved page (text + audio). Bookmarking never saves and saving never bookmarks, but there is
  one page per address: bookmarking a saved page moves it into Favorites (it leaves the library
  list and shows in the start page's grid, still saved), removing that bookmark puts it back in
  the list, and unsaving a bookmarked page leaves the bookmark. Star = bookmark, 🔖 = saved
  article.
- **The Now Playing bar** (`NowPlayingBarView` → `NowPlayingBar`) is the one thing that shows what
  you hear: a floating card 8 pt above the field capsule with the page's artwork (favicon or a
  letter tile), its title, "<site> · N min left", a thin progress line along its bottom edge, and
  play/pause centered over the ⋯ slot. It looks the same on the browser, the start page, the
  Library and the Reader sheet. It shows from the first play; it hides on Now Playing, while you
  type in a field, under other sheets, and after *Stop Listening*. At the end of a page it stays,
  reading "✓ Finished", and ▶ plays the page again. Tap or swipe up → Now Playing; long-press →
  *Stop Listening* (unloads the page; the bar goes).

**Start page** (no page loaded), Safari-style:
1. **Bookmarks**: a Favorites-style icon grid (favicon, or a coloured letter tile when there is
   no usable favicon, with the title below), 4 per row, up to 8; Show All → the bookmarks sheet.
   Tap → open the site; long-press → Rename… / Delete. First because it's stable: the top of
   the page doesn't move as listening progress changes.
2. **Continue listening**: pages part-way through (listened and not finished; older saves with a
   playhead past the start), saved or played without saving, most recently listened first, with a
   thin progress bar and "N min left". Up to 3; Show All opens the library. Tap → the Reader sheet
   (Now Playing if it is what you hear).
3. **Saved**: the newest saved pages in no folder not already above (up to 4), Show All → the
   library.
4. **Recent Searches** (local, newest first, Clear).

"Last listened" / "finished" are the page's `lastPlayedAt` / `finishedAt` (`LibraryQueries`
builds Continue from them).

**Bookmarks sheet** (`BookmarksListView`): every page in Favorites, tap to open, swipe to delete, Edit to
reorder/delete; grabber, medium/large.

**Library surface** (`LibrarySurface` / `SavedListView`): every saved page in no folder, newest
first. Uses the **same
bottom chrome shell** as Browse / Reader (search field capsule + five-slot toolbar). Slot 4
shows 🌐 Browser to swap back (restores the prior browse surface). The Now Playing bar sits above
its search field. Tapping an article opens it in the Reader sheet over the library ("‹ Library";
Now Playing if it is the article you hear). The row's play button plays without opening. The library's ⋯ is
its own menu — *Voice settings*, then big buttons **Bookmarks**, **History**, **Browser** — and
nothing in it acts on the page under the library. Bookmarks and History close the library
first; Browser is the same swap as 🌐.

**Library search** is the same session as Browse's (`SearchSession` + `SearchSessionChrome`):
focusing the field (or toolbar Search) hides the toolbar icons so the field sits above the
keyboard with a round ✕; swipe-down / scroll lowers the keyboard but **stays in search mode**
(typed text and ✕ kept); ✕ exits and clears the filter. Idle chrome keeps Search / 🌐 / ⋯.

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
never shows the page you hear: opening the Reader of that page (📄, a start-page or Library row)
opens Now Playing instead.

### The Reader sheet

```
┌──────────────────────────────────────┐
│                 ───                  │ ← grabber
│ ( ‹ Browser )                    ☝︎  │ ← back pill names what is underneath
│ Notes on Tides                       │ ← title, then "site · 9 min"
│ … serif text on paper …              │
│ ╭ Now Playing bar ──────────────╮    │ ← what you hear (always another page)
│ [🔖]  [ ▶  Listen · 9 min ]  [ ⋯ ]   │ ← this page's own ▶, a pill over slots 2–4
└──────────────────────────────────────┘
```

- **A sheet over the surface that opened it** (`ReaderSheetScreen`, `ShellState.reader`). From
  the browser (📄, ⋯ → Reader, a start-page row) the pill reads *‹ Browser*; from the Library
  *‹ Library*. The pill, the grabber and a pull down all close it to exactly where you were.
- **Listen** reads *▶ Listen · 9 min*, *▶ Resume · 6 min left* for a page part-way through, or
  *▶ Listen Again* for a finished one. It starts at the page's saved spot, makes the page what you
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
- 🔖 saves / unsaves (filled = saved); it keeps the screen and playback as they are.
- **⋯** (slot 5, the browser's ⋯ spot): rows *Voice settings, Save / Remove article, Bookmark
  site, Share, Debug* (developer options only); big buttons **Bookmarks / Saved / History /
  Website** — *Website* (the Reader off) shows the page in the browser, wherever the Reader was
  opened from; from the library, the library closes first. Playback never stops.
- The text sits between the header and the bottom row, so its first line starts below the back
  pill and its last line scrolls clear of the bottom row (UI tests check both).

### Now Playing

```
┌──────────────────────────────────────┐
│  ⌄          PLAYING FROM          ⊕  │ ← ⌄ or a pull down: shrink into the bar; ⊕ Save (✓ saved)
│              example.com             │ ← tap: the page in the browser
│ ╭ [art] Title                      ╮ │ ← the title card, scrolls with the text
│ ╰       example.com · 9 min left   ╯ │
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
  **⌄ or a pull down shrinks it into the bar**, back on what was underneath (the browser, the
  Library, or a Reader of another page), untouched.
- **It looks like a player, not the Reader**: deep jade in light and dark mode alike (the
  `Palette.player…` tokens), with light status bar content and a heavier dim on the strip above
  it. While a finger pulls it down the dim lifts, but the strip under the status bar stays as dark
  as at rest until the sheet has gone, so the clock stays readable. A **title card** at the top of the text (it scrolls with the text) shows the artwork, the
  title and *site · N min left* (*✓ Finished* at the end). The text keeps the Reader's serif and
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
  before iOS 17.2). Drag the text and following stops; a *Back to audio* pill floats
  over the text just above the controls (no arrow: the spoken paragraph may be above or below).
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
- **⋯**: rows *Voice settings, Share, Debug* (developer options only); big buttons **Bookmarks /
  Saved / History / Website**.
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
    "¶ N of M · sentence k of n" and the sentence's first words. It sits just above the capsule
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
- An unsaved page isn't restored after a relaunch (until the library model lands, step 2): Now
  Playing shows its text only while the app keeps it in memory.

## Developer options

Debug tools are hidden in normal use: the ⋯ Debug rows (Browse "Debug ›" with Fake extraction
failure; reader "Debug" → Listen debug panel), Voice settings → Listen debug (and Open full panel),
the listen bar's Debug pill / bake overlay, and long-press ▶︎ → Listen debug panel. They show only
with **developer options** on (`DeveloperOptions`, UserDefaults `reader.developerOptions`): off by
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
| ⋯ → Bookmarks / start page Show All (`BookmarksListView`) | — (grabber) | `.sheet`, medium/large |
| ⋯ → Saved / toolbar Library / start page Show All → library (`LibrarySurface`) | 🌐 Browser slot | in-place surface (shared bottom chrome); leave restores browse |
| Library → Choose voice (`SpeechSettingsView`) | ‹ system | push (`NavigationLink`) |
| Reader sheet (`ReaderSheetScreen`): 📄, ⋯ → Reader, a start-page row, a Library row | *‹ Browser* / *‹ Library* pill, top left | `Sheet` over the surface; pull the header down |
| Now Playing (`NowPlayingScreen`): the bar, the Reader of the playing page, Listen, crash resume | ⌄, top left | `Sheet` over everything; pull the header down |
| Listen debug panel | Done | `.sheet` |
| Speed picker | — | popover |

The browser's own ‹ / › are web-history buttons (the web view also has its edge swipes), not screens.
