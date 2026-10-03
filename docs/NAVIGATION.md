# Navigation rule

**If a screen shows ‹, you can swipe back from the left edge. If it shows ✕, you can pull it down.**
Either gesture must do exactly what tapping the button does.

The reader is the one screen without a ‹ or ✕ at the top: its close control is the back button at
the bottom left (thumb reach). The same gestures still apply — the pushed reader swipes back, the
overlay reader pulls down — and do exactly what that button does.

| Button | Presentation | Gesture | Provided by |
|--------|--------------|---------|-------------|
| ‹ | real push in a `NavigationStack` (`NavigationLink` / `navigationDestination`) | left-edge swipe-back | `App/SwipeBackSupport.swift` (automatic) |
| ✕ | modal: `.sheet`, or an in-place overlay like Browse Reader Mode | swipe down | `.sheet` does it natively; overlays implement it (see below) |

## ‹ = push + swipe-back

- Never show a ‹ screen with `.sheet` / `.fullScreenCover`; push it.
- A custom back control is fine: hide only the system back button
  (`.navigationBarBackButtonHidden(true)`) and put your row in the bar
  (`ToolbarItem(placement: .principal)`). SwiftUI/UIKit normally disable swipe-back then; `SwipeBackSupport` (a `UINavigationController` extension) re-enables
  it app-wide: the edge gesture begins only at stack depth > 1 and not mid-transition, and scroll
  views yield to it only at the very left edge.
- **Don't hide the whole navigation bar on a pushed screen** (`.toolbar(.hidden, for: .navigationBar)`)
  when the screen below shows one. The bar is shared by the stack, so mid-swipe the parent's bar
  (large title, search field, toolbar buttons) pops in full-width on top of the page you're leaving.
  Keep the bar visible and stable; that gives the standard push/pop look.
- Do **not** add per-screen swipe-back hacks. Push with `NavigationStack` and it just works.
- A custom back control should just `dismiss()`; put "leaving" side effects in `onDisappear` so
  the swipe and the tap stay identical (the Saved reader persists progress there; playback keeps
  going).

## ✕ = modal + swipe-down

- `.sheet`: swipe-down is built in (show the grabber). A Done/Cancel/✕ button is optional.
- The browser's Reader Mode is an in-place overlay (not a sheet or `fullScreenCover`): pulling its
  top bar down calls the same close action as its back control. Closing never stops audio: if something is
  loaded, the mini player takes over. The drag starts only on the top bar, so it never competes
  with scrolling, text selection or Jump taps, and the app never autoscrolls. The reader's bars
  never hide, so the top row is always there to pull.
- It moves like a system sheet: it rises from the bottom and leaves the same way. The browser
  stays as it is underneath (page or start page, with its toolbar), so the pull reveals where
  you're going back to: the reader follows the finger (up only with rubber-band resistance; a
  drag that starts sideways leaves it in place), shrinks slightly, and the dim behind it lifts.
  Released far enough or flung, it carries on off the bottom at the finger's speed; otherwise it
  springs back. Under Reduce Motion it fades in and out instead.

## The app is a browser (no tab bar)

There is no Saved | Browse tab bar anywhere. `RootView` shows `BrowseStartView`; all chrome is one
bottom bar, and the page uses everything between the status bar and it (safe area respected).

```
[ ▶︎ Now playing title ━━━━━━━━━━━──────   ⏸ ]   ← mini player (only while something is loaded)
[ 🔒/📄 address …                      (🎤) ]   ← 📄 = reader icon; 🎤 only while searching
[ ‹ ]   [ › ]   [ 🔍 ]   [ 📚 ]   [ ⋯ ]    ← 5 equal slots (slot 4 = Library↔Browser)
```

**One bottom-chrome design (Nav G)**, shared with the reader so Browse ↔ Reader barely changes
the bottom of the screen (`Features/Shell/BottomChrome.swift`): the band (`bottomChromeBand`:
12 pt margins, 8 pt top padding, system bar material through the home indicator), the field
capsule (`bottomChromeField`: 44 pt, secondary-background capsule; 36 pt body-size controls
inside, like 🎤), and the toolbar row (`BottomToolbarLayout` + `toolbarIconFrame`: 44 pt, plain
19 pt glyphs). With larger text the capsule and its controls grow (up to 1.5×) instead of
clipping; toolbar glyphs keep their size and show in the large content viewer on long press.
Every control takes taps in at least 44 × 44 pt (`tapTarget`), whatever its drawn size: the
address-field 📄, the ✕ beside a search field, the reader's back control, the mini player's
play/pause, the capsule's 36 pt controls. **Five equal slots, evenly spaced, one grid for both rows (Nav I):** Browse is
`[‹][›][Search][Library][⋯]`, the Library surface `[ ][ ][Search][Browser][⋯]`, the reader
`[1×][⏮][▶︎][⏭][⋯]`. Slot 4 is the Library↔Browser swap (📚 on Browse, 🌐 on Library — same
muscle memory as the morph-menu Reader↔Website near ⋯). Leading items fill slots 1, 2, 3…; the
last item (⋯) always sits in slot 5, so every icon in slot N is at the same x and the ⋯ menu
grows from the same spot. ⋯ is never replaced. The mini player's play/pause is centered over the
⋯ slot too.

- **Search** (🔍, middle): focuses the address field, empty, for a new search (Recent Searches
  show full-bleed, Safari-style); ✕ cancels and restores the page's address. Swipe down lowers
  the keyboard but stays in search mode (typed text and ✕ kept). The page stays loaded underneath.
- ‹ / › are web history (disabled when WebKit can't go back / forward; KVO on the web view, so
  same-document history counts too). The web view's own edge swipes still work.
- No Reader button in the toolbar. The **reader icon** (📄, like Safari's page-format icon) sits
  at the leading edge of the address field only when the page is readable (the same Mozilla
  `isProbablyReaderable` check extraction uses, run after each load / same-document URL change);
  otherwise the lock / search glyph is there. Tapping it opens the Reader Mode overlay (a
  spinner replaces it while the article is extracted).
- **⋯** opens a Safari-style menu panel that grows out of the button (covers the ⋯, no arrow):
  rows *New search, Save article / Remove from Saved (🔖),
  Bookmark / Remove Bookmark (☆), Share, Reload, Voice settings, Debug ›* (Debug only with
  developer options on — see "Developer options" below), then a row of big
  buttons **Bookmarks**, **Saved**, **History**, and **Reader** (rightmost, nearest the thumb,
  like Safari's All Tabs). The Reader toggle is disabled on the start page and on pages that
  aren't readable; on a readable page tapping it switches into reader mode. Actions that present
  something (Share, Voice settings, Bookmarks, Saved, History) run after the panel has closed.
- **The ⋯ panel** (`MorphMenuOverlay`: one overlay for the browser toolbar ⋯, the library
  toolbar ⋯ and the reader listen bar ⋯; its rows come from the surface that opened it,
  `MenuContext`) is not a popover: it is placed so the bottom-right button's icon (Reader,
  or Website in the reader — marked with `morphMenuFocus`) sits slightly up and to the left of
  the ⋯ glyph (Safari's feel: **12 pt left, 10 pt up**), not dead-on on top of it (UI tests check
  the offset within 1 pt on Browse, the reader overlay and the pushed reader). It covers
  the button and the toolbar around it, so the bottom row lands under the thumb, and grows out of
  that point (the glass grows from the button's circle to the panel's frame and corners, never
  stretched; the rows fade / un-blur in) while the ⋯ glyph
  fades, and the rest of the screen dims. Tapping the dimmed area,
  swiping the panel down, or Escape (VoiceOver scrub / hardware Esc) collapses it back into the
  button (a swipe-down collapses it at the release speed). While dragged, the panel follows the
  finger down and resists going up (rubber band); the drag's axis is fixed by its first movement,
  so a horizontal drag leaves the panel in place and a drag that drifts sideways doesn't make it
  jump. The reader overlay's pull-down follows the same rules. Light glass on iOS 26 (thick material
  before). Debug › is a native `Menu`.
- **Bookmarks vs Saved**: a *bookmark* is just a site link (URL, title, favicon — e.g. a story's
  index page), kept in its own small JSON store (`BookmarkStore`,
  Application Support/Bookmarks/bookmarks.json); no text or audio. A *saved article* is the
  reader article (text + audio) in SwiftData. The two are independent: bookmarking never saves,
  saving never bookmarks. Star = bookmark, 🔖 = saved article.
- **Mini player**: title, thin progress, play/pause (centered over the ⋯ slot). Shown whenever an article is loaded for
  playback and the reader isn't on screen (hidden while typing an address). Tap → the reader
  overlay; long-press → Stop listening.

**Start page** (no page loaded), Safari-style:
1. **Bookmarks**: a Favorites-style icon grid (favicon, or a coloured letter tile when there is
   no usable favicon, with the title below), 4 per row, up to 8; Show All → the bookmarks sheet.
   Tap → open the site; long-press → Rename… / Delete. First because it's stable: the top of
   the page doesn't move as listening progress changes.
2. **Continue listening**: saved articles part-way through (listened and not finished; older saves
   with a playhead past the start), most recently listened first, with a thin progress bar and
   "N min left". Up to 3; Show All opens the library. Tap → the reader overlay at that spot.
3. **Saved**: the newest kept articles not already above (up to 4), Show All → the library.
4. **Recent Searches** (local, newest first, Clear).

"Last listened" / "finished" live in `ListenHistory` (UserDefaults), not in the SwiftData row.

**Bookmarks sheet** (`BookmarksListView`): every bookmark, tap to open, swipe to delete, Edit to
reorder/delete; grabber, medium/large.

**Library surface** (`LibrarySurface` / `SavedListView`): every kept article. Uses the **same
bottom chrome shell** as Browse / Reader (search field capsule + five-slot toolbar). Slot 4
shows 🌐 Browser to swap back (restores the prior browse surface). Opening an article pushes the
reader inside the surface (its back control or a swipe from the left edge pops it); the shared library chrome hides
while the reader draws its own. The row's play button plays without opening. The library's ⋯ is
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

## The reader (one screen, wherever it's opened from)

```
┌ bar ─────────────────────────────────────────┐
│ (                  title                   ) │  ← title in the field capsule (overlay: own band; pushed: nav bar)
└──────────────────────────────────────────────┘
…  article: edge to edge, the current paragraph softly tinted  …
┌ bar ─────────────────────────────────────────┐
│ [🌐/🏠/📚] ( ━━━━━●━━━━░░░░──  ☝︎  🔖 ) │  ← back control left of the scrubber pill; pill = address capsule
│  [1×]   [⏮]    [▶︎]    [⏭]    [ ⋯ ]            │  ← listen row = the browser's 5-slot toolbar row
└──────────────────────────────────── home indicator ┘
```

**Bottom chrome = the browser's (Nav G).** The reader's bottom is built from the same pieces as
the browser's address field + toolbar (see "One bottom-chrome design" above): the scrub row
(scrubber, ☝︎ Jump, 🔖) sits in the same field capsule as the address field, Jump / 🔖 sized and
coloured like the mic (secondary; accent when on / saved); the listen row uses the same toolbar
layout and 19 pt plain glyphs as `[‹][›][Search][ ][⋯]` (▶︎ is a plain `play.fill`, no big
circle), with ⋯ in the same slot 5 as the browser's ⋯ (a UI test checks the frames match). Same band,
margins and position above the home indicator. The overlay's top row mirrors it at the top: the
title in a field capsule on the same bar material; the pushed reader's row sits in the navigation
bar, same capsule and bar material.
Against Browse's `[‹][›][Search][Library][⋯]` (same five-slot grid, Nav I): 1× under ‹, ⏮ under ›,
▶︎ under Search, ⏭ under Library, ⋯ under ⋯.

**The back control** (left of the scrubber pill, within thumb reach) is the reader's one close
control; there is no ✕ or ‹ at the top. It goes back to where the reader was opened from
(`ReaderOrigin`) and its icon and label say which:
- 🌐 **Back to Website**: opened over a web page (address-bar reader icon, ⋯ → Reader, the mini
  player while a page is loaded). The page is revealed as it was.
- 🏠 **Back to Start Page**: opened over the start page (a start-page row, Continue listening, the
  mini player there, crash resume).
- 📚 **Back to Library**: pushed from the library list.

Pulling the overlay's top row down, and the pushed reader's left-edge swipe, do the same.

**The bars never hide (Nav H).** Like the browser's search bar / toolbar, the top row and the
bottom controls stay put: no hiding on scroll, no tap-to-toggle, no progress line, and the status
bar stays. (Nav F's auto-hide was removed.) The text runs edge to edge under the bars, but the
scroll content is inset by their height (native `contentInset` on the web view,
`contentMargins` on the plain-text fallback), so the first line starts below the top row and
the last line scrolls clear of the bottom controls (UI tests check both). The pushed reader's
navigation bar turns clear only while the ⋯ menu dims the page. The reader never autoscrolls on
its own (audio highlighting doesn't move the text; following your scrub is the one exception).
Pull-down-to-close (overlay, from the top row) and left-edge swipe-back (pushed reader) work as
above. Code:
`ReaderChrome.swift` (text insets), `BottomChrome.swift` (shared look), `ArticleListenSurface`
(edge-to-edge layout).

- Same look saved or not, playing or not: the tint marks where Play starts / is.
- **Status notes** (Nav J): "Preparing next…", Apple-fallback / language notes, and the
  developer-only Debug chip sit **above** the scrubber so appearing text never pushes it when you
  skip.
- **Scrubber** (sentence-precise): fill = progress (weighted by text length; with a local
  voice the thumb now moves smoothly inside a paragraph, estimated from the player's time); the
  lighter fill ahead of it is audio already rendered (local voices; Apple speaks live so there is
  none). This lighter fill replaced the old gray "not ready" paragraph cards; nothing per-paragraph
  in the text shows readiness any more (only the developer-only bake overlay does).
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
  - **The bubble** (a card as wide as the scrub band) shows the speed as a chip (½×, ¼×, Fine),
    "¶ N of M · sentence k of n" and the sentence's first words. It sits just above the capsule
    and, once the finger slides up, rides 44 pt above the finger so the thumb never covers it; at
    large text sizes it wraps rather than truncating.
  - **Release** seeks to the start of the sentence under the thumb, not the paragraph start:
    playing keeps playing from that sentence; paused stays paused there (Play resumes from it);
    not loaded just moves where Play starts (and the stored offset of a saved article resumes at
    the start of its sentence). The paragraph under the thumb is tinted and scrolled to while
    dragging (the only time the text scrolls on its own). A tap on the thumb itself isn't a seek.
  - Local voice: playback starts at the synth chunk holding the sentence, offset into its audio
    by characters (chunk boundaries found by counting letters; stitched paragraphs use the stored
    chunk durations), with a 0.25 s lead-in so the first word isn't clipped. Not rendered yet: the
    render queue does that chunk first (then the rest of the paragraph). Apple voice: speaks from
    the sentence's first character.
- **Speed** (1×, Nav I): applied in place — the current sentence keeps going at the new speed.
  Local voices: a pitch-preserving time-stretch on the player (`AVAudioPlayer.enableRate` /
  `rate`; all audio, including Apple-fallback units, is rendered at 1×), so nothing is re-queued,
  re-rendered or restarted. The Apple voice (AVSpeechSynthesizer can't change a running
  utterance's rate) restarts from the word being spoken. The rate is persisted
  (`reader.rateMultiplier`) and the lock screen's playback rate follows it (and can set it).
- ☝︎ **select paragraph**: then tap a paragraph to play from it (hint banner with Cancel).
- 🔖 save / unsave (filled = saved). Saving keeps the screen and playback as they are.
- **⋯** (bottom-right of the listen bar, the same spot as the browser's ⋯): the same morph panel
  in reader context. Top rows *Voice settings, Save / Remove article, Bookmark site,
  Share, Debug* (developer options only); bottom row **Bookmarks / Saved / History / Website** — in reader mode the Reader
  slot becomes 🌐 **Website** (same spot; its icon is 12 pt left / 10 pt up of ⋯, Nav J). Website = reader off:
  it always goes to the article's own page in the browser, wherever the reader was opened from.
  The reader overlay over that page just reveals it (no reload); from the library (the library
  closes first), the start page, Continue listening or the mini player the page loads in the
  browser.
  Playback never stops — the mini player takes over.
  In the pushed reader the dim covers the navigation bar too; a tap there closes the menu.
  Voice settings (speed / voice / engine — what the gear used to hold) opens as a sheet. There
  is no gear on the listen bar.

## Developer options (Nav I / J)

Debug tools are hidden in normal use: the ⋯ Debug rows (Browse "Debug ›" with Fake extraction
failure; reader "Debug" → Listen debug panel), Voice settings → Listen debug (and Open full panel),
the listen bar's Debug pill / bake overlay, and long-press ▶︎ → Listen debug panel. They show only
with **developer options** on (`DeveloperOptions`, UserDefaults `reader.developerOptions`): off by
default in Release builds, on by default in Debug builds. To toggle in any build, long-press the
The first Release launch of Nav J clears a previously stored unlock so a Debug pill
cannot stick on after upgrading; long-press the version row again to turn it back on.

**version row** at the bottom of Voice settings for 2 s (haptic + "Developer options on/off"
confirmation). UI tests force it with `-reader.developerOptions NO|YES`.

## Current screens

| Screen | Button | Presentation |
|--------|--------|--------------|
| Browser (start page / web page) | — | root |
| Browser → editing the address | ✕ round, right of the field | in place; tap outside or drag down |
| Browser ⋯ / Reader ⋯ | — | morph panel over the button (same design; reader context swaps Reader for Website) |
| Browser toolbar Search | ✕ round, right of the field | in place (editing the address, empty) |
| Reader ⋯ → Website | — | closes the reader (and leaves the library) and shows / loads the article's page in the browser; audio continues |
| ⋯ → Voice settings (`SpeechSettingsView`) | Done | `.sheet` |
| ⋯ → Share | — | `.sheet` (system share sheet) |
| ⋯ → History (`BrowseHistoryView`) | — (grabber) | `.sheet`, medium/large |
| ⋯ → Bookmarks / start page Show All (`BookmarksListView`) | — (grabber) | `.sheet`, medium/large |
| ⋯ → Saved / toolbar Library / start page Show All → library (`LibrarySurface`) | 🌐 Browser slot | in-place surface (shared bottom chrome); leave restores browse |
| Library → reader (`OfflineArticleView` → `ArticleReaderScreen`, title row in the nav bar, text full-bleed under it) | 📚 back control, bottom left | push inside the surface (`navigationDestination(for: UUID.self)`); edge swipe-back |
| Library → Choose voice (`SpeechSettingsView`) | ‹ system | push (`NavigationLink`) |
| Browser → address-field reader icon / ⋯ Open in Reader / start page row / mini player (`ArticleReaderScreen`) | 🌐 / 🏠 back control, bottom left | full-screen in-place overlay (covers the whole browser, edge to edge); pull top row down |
| Listen bar ⋯ → Voice settings (`SpeechSettingsView`) | Done | `.sheet` |
| Listen debug panel | Done | `.sheet` |
| Speed picker | — | popover |

The browser's own ‹ / › are web-history buttons (the web view also has its edge swipes), not screens.
