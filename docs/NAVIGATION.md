# Navigation rule

**If a screen shows ‹, you can swipe back from the left edge. If it shows ✕ (or is a sheet with a
grabber), you can pull it down.** Either gesture must do exactly what tapping the button does.

Listen on compact width slides up over everything (the chrome too) and follows the sheet rule
without a button: a grabber, and a pull down that closes it (VoiceOver: the escape gesture;
"Bottom chrome", below).
Regular width keeps the Reader and Now Playing sheets ("iPad and regular width").

| Button | Presentation | Gesture | Provided by |
|--------|--------------|---------|-------------|
| ‹ | real push in a `NavigationStack` (`NavigationLink` / `navigationDestination`) | left-edge swipe-back | UIKit, with the system back button |
| ✕ | modal: `.sheet`, or the design system's `Sheet` (Follow's chapter preview; the regular-width Reader and Now Playing) | swipe down | `.sheet` does it natively; `Sheet` implements it (see below) |

## ‹ = push + swipe-back

- Never show a ‹ screen with `.sheet` / `.fullScreenCover`; push it.
- Keep the system back button: every pushed screen does. UIKit turns swipe-back off on a screen
  that hides it (`.navigationBarBackButtonHidden(true)`).
- **Don't hide the whole navigation bar on a pushed screen** (`.toolbar(.hidden, for: .navigationBar)`)
  when the screen below shows one. The bar is shared by the stack, so mid-swipe the parent's bar
  (large title, search field, toolbar buttons) pops in full-width on top of the article you're leaving.
  Keep the bar visible and stable; that gives the standard push/pop look. (The Library home, the
  stack's root, has no bar: its title is the first thing in its list. The screens pushed over it
  keep theirs.)
- Don't build swipe-back by hand. Push with `NavigationStack`; with the system back button it just
  works.
- Put "leaving" side effects in `onDisappear`, so the swipe and the tap stay identical. No screen
  saves the listening position: the playback session does, through `ListeningProgressRecorder`
  (`LISTEN_PLAYBACK.md`).

## ✕ = modal + swipe-down

- `.sheet`: swipe-down is built in (show the grabber), from the header or from a scrolling body at
  its top: the Move tree, the import sheet (except while it works), History,
  Settings, Prepared Audio, Edit Details. Their *Done*, *Cancel*, *Save* and *Import* are one
  pill, the neutral one the Reader's close pill is (`SheetBarButton`).
- The design system's `Sheet` (Follow's chapter preview, and the Reader and Now Playing on regular width,
  in place, not a `.sheet` or `fullScreenCover`): pulling the header (grabber or the top bar) down calls
  the same close action as its button. Closing never stops audio.
- **The text pulls the sheet too, from its top**, so a sheet closes one-handed from the lower half
  of the screen (`SheetPullHandoff`). A drag on the text that begins with the text at its top and
  goes down moves the sheet instead of bouncing the text, which stays put; moving back up lowers
  the sheet first, then scrolls the text again. A drag that begins anywhere else in the text only
  scrolls, even once the text reaches its top: reading back up never closes the sheet. Sideways
  drags, text selection and ☝︎ taps are untouched, and the scrubber and the bottom row aren't
  text, so they never pull. In Now Playing a pull alone keeps following the audio (it moves
  nothing); once the drag moves the text, following stops as for any drag. In full screen the
  text hands no pull to the sheet: a pull down at its top only rubber-bands and brings the bars
  back, and a pull that begins with them showing closes the sheet as above. (Compact full screen,
  which is the chrome's, is left by the middle tap alone.)
- It moves like a system sheet: it rises from the bottom and leaves the same way. The surface
  stays as it is underneath (the page or start page, the Library's screen), so the pull reveals
  where you're going back to: the sheet follows the finger (up only with rubber-band resistance;
  a drag that starts sideways leaves it in place), shrinks slightly, and the dim behind it lifts.
  Released far enough (72 pt) or flung (where a quarter second more at the release speed would
  take it past 180 pt; about 700 pt/s from rest), and still heading down as the finger lifts
  (where the release speed would carry it is past 72 pt), it carries on off the bottom at the
  finger's speed; otherwise it springs back (`Motion.settle`). Pulled down and then pushed back
  up before letting go, it stays (`SwipeGesturePolicy.shouldCommitDownwardDismiss`, the rule of
  every pull-to-dismiss: the sheets, Listen, the ⋯ panel). The header and the text use the same rule.
  Under Reduce Motion it fades in and out instead. What is under a sheet takes no touches until it
  has gone.

## Bottom chrome (compact width)

On iPhone (any compact width) one floating chrome host (`Features/Shell/Chrome/ChromeHost.swift`)
sits over three destinations, the Library, the Browser and Settings (and the in-place readers). Listen is
not a destination: it slides up over the chrome. The chrome has no ⋯: the Library's screens, Library Read and
Settings have ⋯ on their title line, and the Browser's menu is a press and hold on its field's leading glyph. There is no system tab bar (invariant 13: `rg "TabView|UITabBar"` finds nothing).
Regular width keeps its own band and dock ("Two surfaces" and "iPad and regular width", below).

```
expanded    [‹ ›][ address / Search Library     ][🎧]     row 1: the screen's own, Listen at its end
            [ ▤  |  🌐  |  ⚙︎                  ]     row 2: where you are (icons only), margin to margin
one row     [‹ ›][ address / Search Library     ][🎧]     first step of a scroll down: row 2 gone, row 1 in its place
folded                     ( example.com )                second step: the field shrunk to a small glass bubble naming the page; a tap brings both rows back
searching   [ 🔍 field                  ⊗ 🎤 ][Cancel]     the keyboard is up: margin to margin; no pill or Listen, no bubble
Listen      slides up over everything                     a pull down closes it, back to what was under it
```

Every piece is a pure function of one layout (`ChromeLayout`, the mockups' `rectsFor`) and a progress. The fold
has **steps**: 0 is two rows, 0.5 one row, 1 the bubble. **Every piece goes straight down, never sideways.** From
0 to 0.5 row 2 slides down off the screen's edge while row 1 drops one row (bar + gap) into its place; from 0.5 to 1
‹ › and Listen slide down off the edge while the field becomes the bubble: its text fades as the bubble's name fades
in where it was, at its size (to 0.6), then the field's glass, handed to the bubble's as one shape, shrinks to the
bubble while the name glides to its centre and down to 13 pt (`ChromeLayout.bubble`, `bubbleTextX`, `bubbleTextScale`). The sizes are Safari's (measured on an iPhone 17 Pro,
iOS 26). Both rows run **margin to margin with identical leading and trailing edges** on every phone: the field
and the pill start at the left margin, Listen and the pill end at the right one. A wider phone widens the field and
the pill.

**Placement is measured from the screen's edge.** The bottom row's bottom sits 34 pt above the screen's edge
(`ChromeMetrics.edgeClearance`), on the home-indicator strip rather than in it, on every phone (a Home button phone
too). Every footprint is from the edge: 142 expanded (4 + 48 + 8 + 48 + 34), 86 one row (and the keyboard's row), 58
the bubble (4 + 36 + 18). Consumers that inset from the safe area convert with
`ChromeHome.above(x)` = max(0, x - home indicator inset); the web view uses max(footprint, home inset).

- **The bubble** (`ChromeLayout.bubble`, `ChromePieces.bubblePiece`, id `chromeBubble`): what the second fold step
  ends in, on every screen that folds (the Browser's page, the Library and its folders and books, Library Read,
  the Browser's reader mode in Scroll mode, Settings and its pages). Safari's minimized address bar: a **glass
  capsule** on the field's surface (`chromeSurface`, `BottomChrome.fieldFill`), 36 pt tall (`Control.small`),
  13 pt semibold ink (`TypeStyle.caption`'s size, fixed), 16 pt padding each side (`Spacing.m`), as wide as its text and
  padding, at most margin to margin, centred, its bottom 18 pt above the screen's edge (`bubbleClearance`, just over
  the home indicator). The hit area is its width and 44 pt tall (`bubbleHitOutset` 4 above and below). It names
  where you are: the page's domain on the Browser (no `www.`, no path), the screen's title in the Library, the
  article's title in Library Read, the source in the Browser's reader mode, *Settings* in Settings
  (`ChromeScreen.bubbleTitle`). Audio keeps playing while folded; the bubble's tap and a scroll up bring both rows
  back. Sheets have no bubble. `-chromeFold P` (Debug) holds the fold at P wherever it may fold, to look at a step.

- **The pill** `[Library | Browser | Settings]`: three equal segments, a third of the pill each (117 pt on the
  SE's 375), **icons only** (each keeps its accessibility label: Library, Browser, Settings; ids `chromeLibrary`,
  `chromeBrowser`, `chromeSettings`), the lit one the screen you are on (an inset capsule, 4 pt on all four sides,
  40 tall, its glyph accent).
- **Settings** (compact width) is a destination like the other two: its pill segment shows it in place under
  the same chrome (`ShellState.Surface.settings`, remembered for the next launch as `settings`), Library and
  Browser leave it, and it scrolls under the chrome and folds like the Library. Its title heads the list with ⋯ at
  the end of the line (Settings has no rows of its own, so the app-wide ones: Saved, History, Listen). Row 1 is
  **Search Settings**, which filters the list as you type: a row shows when its title or its section's title
  contains the text, sections without a match go, and nothing matching says *No Results for "…"* (the
  Library search's view). Starting a search shows the list (a pushed page goes); the pages it pushes (Voice,
  Appearance, Prepared Audio, …) are `ShellState.settingsPath`, kept while another destination shows. Regular
  width keeps the Settings sheet (the sidebar's Settings); a Settings surface restored on regular width (or a
  window widened onto it) becomes the browser with the Settings sheet over it.
- **Listen** (`ChromeListenButton`, id `chromeListen`, VoiceOver *Listen*, value *Playing* while it plays): a
  48 pt glass circle ending row 1 on every screen, Library Read and the Browser's reader mode included. It shows
  the headphones, or the app's playing bars in the accent while something plays (still under Reduce Motion).
  A tap slides Listen up: on what is bound to playback; else the page played last (`LibraryQueries.lastPlayed`),
  bound paused at its saved place so ▶ resumes it there; else Listen's empty screen, *Nothing Playing*. It is not
  drawn while typing or in Library Edit (row 1 is then the field alone).
- **One shape system.** Every piece is a capsule or a circle (radius = height / 2). One height, **48 pt**
  (`Control.bar`, Safari's address bar and buttons), for every piece in every row and state (pill,
  fields, ‹ ›, Listen, Cancel, the floating ▶ / ⏸, Jump to Audio, Library Read's ⋯), on every screen. The round
  buttons share one face (`ChromeCircleFace`).
  **Concentric:** a 48 pt end holds a 24 pt glyph slot inset 12 (`endGlyphSlot`, `endInset`), so the slot's
  radius is the end cap's less the inset. **Every hit area is at least 44 pt** (`Control.tap`): the glass is
  48 tall, so the hit shape is the glass itself (`hitOutset` 0; `ChromeHitShape`, `tapTarget(size)`), and
  neighbouring hit areas never overlap. One 8 pt gap everywhere (`Spacing.xs`): between the rows and between
  neighbours on a row (‹ › and the field, the field and Listen, the field and Cancel). ‹ 48, ‹ › 96. Every control glyph is 20 pt medium (`Glyph.regular`, `BottomChrome.chromeGlyph`).
- **Look.** Translucent glass, nothing opaque behind it: Liquid Glass inside one
  `GlassEffectContainer` on iOS 26, every piece answering a press; earlier iOS (and a Debug launch
  with `-chromeFallback`) a blur with white at 58% over it (dark: 44, 44, 48 at 55%), an inner 0.5 pt
  edge and a soft shadow under each shape. Page content shows through and between the pieces. Behind
  them only a translucent fade (`ChromeFade`): clear 50 pt above the top piece, the colour of what is
  under (a web page's own background, paper on the start page, the search layer and the Library, the
  reading theme on readers) at 70% of the way down, at 90% opacity. A piece that is not shown
  leaves the tree (inside the glass container an opacity above a piece's glass is ignored) and the
  glass materializes in and out with a content cross-fade; the whole host's opacity (outside the
  container) does fade glass, which is how Reduce Motion cross-fades.
- **Row 1** is the screen's context: on the Browser `[‹ ›][address]` (the pair shows whenever either way is
  open, the half that cannot move dimmed to 35% and disabled but in place; nothing on a new page), on the
  Library its search field, in Library Read `[Aa  site]`; Listen ends it. › after ‹ re-enters the reader view when ‹ left it (`ShellState.readerLeftByBack`, `readerOnLoad`).
  The address field is `[reader icon][URL][↻]` (↻ is ✕ while the page loads). ↻ never gives way: a whole
  44 x 44 control (`Control.tap`), its glyph in the chrome ink at the chrome glyph weight
  and size, centred on the capsule's end radius; the URL truncates and the reader icon gives way below
  about 150 pt (`ChromeMetrics.readerIconWidth`). There is no 🎧 in it on compact width: Listen
  is the round button after the field. While the page shows as its reader view the field is
  `[reader icon][URL][Aa][↻]`: Aa (`readerAppearance`, VoiceOver *Text Appearance*) is the same 44 x 44
  control as ↻ and sits before it, so the URL truncates first. Aa is not drawn on the web page or while
  the search field is open (opening search closes its panel).
- **Row 2** is the pill alone, margin to margin; it never moves or resizes across destinations and states. There is no play / pause in the chrome: Listen, the row's tap in
  the Library and the readers' ▶ Listen start and control playback.
- **Collapse follows the finger down, in steps; a scroll up brings it back at once.** One progress value
  (`ChromeScroll`), 0 two rows, 0.5 one row, 1 the bubble: `progress += dy / 120` for a scroll down (60 pt a
  step), ignored while the keyboard or the ⋯ panel is up, and 150 ms after the finger stops a part-way step
  settles forward to its end (`ChromeScroll.stepEnd`: 0, 0.5 or 1). **A scroll up of 24 pt with no scroll down
  between (`ChromeScroll.revealDistance`) brings both rows back, as Safari does, on every screen that folds.**
  The rows also come back by a tap on the bubble, by reaching the top of the content (offset <= 4, which resets
  progress to 0) (invariant 12), and by what is not a scroll: a new page or screen loading, opening the address
  or search field, VoiceOver being on. The Library, the Browser and the in-place readers feed it; **Listen does not**
  (it has no chrome), the Browser's start page does not fold, and an in-place reader folds only in Scroll mode.
  **The bubble's tap does not pin.** `ChromeScroll.expandByHand` brings both rows back and grants a short grace:
  scroll reports within 0.35 s (`tapQuiet`, a fling already under way) move nothing, then the next 24 pt of
  scrolling down (`refoldGrace`) folds nothing, and past it the fold follows the finger again. The tap-swallow
  shield stays: while folded (fold < 0.75) a touch on the rows' area does not reach the page under it.
  Reduce Motion: no travel, the steps cross-fade.
- **Searching** (the keyboard up, or its session open): one row, **margin to margin on every phone**, Brave-style:
  the field (🔍 left, the text, a round ⊗ inside at the right while there is text, 🎤 at its end) and a **Cancel**
  text button (accent, 72 pt) at the right margin. It is not the fixed 351 pt block (the one exception to it): the
  field runs from the left margin (12) to Cancel, one 8 pt gap between, so it is 375 − 24 − 8 − 72 = 271 pt on the
  SE and 298 pt on a 402 pt phone (`testTypingIsTheFieldAndCancelMarginToMargin`). The pill, Listen, the bubble and any globe
  are not drawn while typing. Above the field the search layer is **opaque paper from under the safe area down to the
  keyboard**, and at its top, 12 pt under the safe area and 12 pt from each side, one **rounded card** of rows
  (`SearchSessionOverlay`): untouched (or empty), *Recent Searches* (header + Clear All, a 🔍 row each); typing, first
  `Search “typed”` (🔍, runs the search; for an address, `Go to “…”`), then up to 2 history matches, 1 saved page and the
  engine's live suggestions, 6 rows in all. Each suggestion row has 🔍 on the left and a ↖︎ on the right that puts its text in the
  field without searching; a row's tap runs it. Library's search uses the same Cancel in the row (its list is its own).
- **Web pages know the chrome (Browse, iOS 26+, compact width)**: the Browse `WKWebView` reports the chrome's
  footprint as its bottom `obscuredContentInsets` (plus min/max viewport insets), so a page's
  `position:fixed; bottom:0` banner (cookie bars, Reddit's "open in app"), sticky footers and `dvh`/`svh`/`lvh` sit
  above the glass instead of under it. The inset follows the drawn step (`ChromeScroll.drawnStep`): 142 pt two rows,
  86 one row (and the keyboard's row while a search is open), 58 the bubble, each at least the home-indicator
  inset (the web view extends under it, so its own inset reads 0). The Library's lists and the readers keep one
  constant inset (142, less the home inset above the safe area). The switch happens **once per step**, not per
  frame: the page's fixed elements jump at each step's midpoint while the glass folds, and the page text reflows once, instead of the
  whole page re-laying out on every frame of the fold. The scroll offset does not move (the scroll view's
  `contentInset` stays constant; only the web layout inset changes). Content still scrolls under the glass.
  Limits: legacy `100vh` is always the full frame in WebKit and follows neither inset, so a `100vh` hero extends
  under the chrome (as in Safari with its bar up); iOS before 26 keeps the constant content inset only (no obscured
  inset); the in-place Reader is SwiftUI, not a web view, and has its own bottom inset; iPad regular layout is
  untouched. Fixture: `reader-test://pages/popup`, `testAFixedBottomPopupSitsAboveTheChrome`.
- **Listen slides up over everything** (`NowPlayingScreen`, `ReadingShowing.cover`, a `Sheet` that covers):
  from the bottom, over the chrome, to just under the status bar, the screen behind dimmed above its rounded top, as Apple Music's player. At its
  top a grabber (its strip a full tap target tall); there is no close button. The article's title is the first thing in its
  text. A pull down on the grabber or the player card (a UIKit pan, `SheetPullPan`, so a drag that starts on a control pulls too; the scrubber keeps its drag), or on the text when it is at its top, follows the finger and closes it when let go far enough or
  flung while still heading down, and springs back otherwise; VoiceOver's escape gesture closes it too. Closing shows exactly what was under it: the surface,
  its scroll, a reader in place and its fold or full screen, a search (its keyboard lowered when Listen
  opened). Audio keeps playing. At the foot a glass player card at the chrome's margins (`Radius.surface` 24),
  as tall as its rows, floating over the text, which runs on under it to the screen's foot (`ReaderPlayerCard`); the
  end of the text scrolls to just above the card. No artwork and no divider: its
  groups are set apart by space alone.

  ```
  Title of the article, one line…              (🔖)
  example.com                         6 min left
  ━━━━━━━━━━━━━━━━●──────────────────────────────
  1×                                       Voice
           ⏮        (  ▶  )        ⏭
  Aa                                         ⋯
  ```

  Row 1: the title on one line (cut with …), then Save, a round 36 pt button. The title
  opens the article's own place in the Library or its page, and never seeks; only the track does.
  Row 2, one text step smaller: the site at the left (it truncates) and the time left at the right; the
  page's status note (preparing, voice and language notes) or "Finished" alone in its place. Then the
  full-width scrubber, no times. Under it two rows of small glyphs, no labels, at the card's margins:
  the speed (1×) over Aa at the left, Voice (VoiceOver: "Voice", never a voice's name) over ⋯ at the
  right; between them ⏮, a 62 pt ▶ / ⏸ and ⏭ (`NowPlayingTransport`'s `card` size), centred across
  both rows. **Jump to Audio** is not in the card: scrolled away from the audio, a round glass ↑ or ↓
  (48 pt, `JumpToAudioButton`, the same on regular width) floats in the middle 12 pt above the card (above
  the home indicator's strip in full screen) and brings the text back to the spoken sentence (VoiceOver:
  "Jump to Audio"); while the text follows the audio, or once the article has finished, it isn't there.
  ⋯ (`listenMore`) is a system menu, a section per
  group: *Play from a Paragraph*; *Go to <folder or Library>*, *Save to Folder…*,
  *Mark as Finished*; *Share* (`MenuRegistry`'s `nowPlaying` place). There is no sleep timer. **Full screen** is a tap in the middle of the text, in and out: the
  card slides off, the status bar hides and Listen stops being a sheet: the gap at its top, its rounded
  corners and the dim above it go (`Motion.standard`), and the page covers the screen, its text from the
  status bar's foot to the screen's, where its end now scrolls; a ▶ / ⏸ floats for 3 s. The text on
  screen doesn't move in or out. A pull does nothing to the sheet there (the text only rubber-bands);
  the middle tap leaves it, as in the in-place readers. It is Listen's own: the chrome
  underneath keeps its state. Voice, Save to Folder, ⋯ and the debug panel open over Listen and return to it.
- **Listen with nothing to play** (nothing bound and nothing played before): the same cover, its grabber and
  pull down, with *Nothing Playing*, "Choose an article or book to listen to." and two tiles, *Open
  Library* (`listenEmptyOpenLibrary`, accent-tinted), which closes it on the Library's home, and *Browse
  the Web*. A pull from
  anywhere on it closes it. Listen that loses what it showed (the page removed from the Library) closes
  instead.
- **Starting something new** (compact width): a Library row's tap plays the article or chapter and slides
  Listen up (a followed story's chapter still waiting for its text plays once it is in, and Listen stays
  down); a reader's ▶ Listen does the same; a page shared from Safari opens in the Browser straight in
  reader view (once it has loaded and if it is readable; else the page itself), its heading's ▶ Listen
  there; *Paste Text…* saves, then opens the new article in Library Read; *Import from…* and a shared book
  file close the import sheet on the new book's screen.
- **Reader mode on the Browser replaces the page in place** (like Safari Reader,
  `ReaderSurface`): the chrome folds on scroll in Scroll mode like a page (to a bubble naming the source) and stays expanded in Pages mode, the address keeps the
  URL (narrower by one round control), the reader icon sits in a lit capsule and toggles back. The
  text is a reading page like the Reader's (`ReadingPage`, in place): Pages or Scroll as the
  Appearance setting says, the footer, a tap in the middle for full screen, *Play from Here* on a
  selection, and it opens at the page's saved listening spot, underlined. The reader's theme runs up
  under the status bar. Under the title the source line reads "site  length" and ends in ▶ Listen, an
  accent-filled capsule (on-accent text, semibold; 36 pt tall at the default text size, growing with it
  up to 1.5×; a 44 pt tap) at the line's right end, centred on it: a long site gives way first (an
  ellipsis), and the pill never wraps or shrinks. It is a `<button>` in the page's heading, so it scrolls
  with the text and is never read aloud, and its label stays "▶ Listen" while the page plays. It plays the
  page from its saved spot and slides Listen up; for the page you hear it only slides Listen up. The
  reader stays a plain reader while its page plays: no spoken paragraph, underlined sentence, following
  or Jump to Audio (the playhead is Listen's), and no saved-spot underline; *Play from Here* moves the
  playhead and slides Listen up. The end of the text scrolls to just above the chrome as it is drawn
  (two rows, one, the bubble). Full screen is the text alone, down to the screen's foot, where its end then scrolls: no floating
  ▶ / ⏸ (that is Listen's and the regular-width sheets'). While another layer covers the reader it stays mounted and quiet: no status bar change, no fold anchor. Aa is in the address field beside ↻ (`readerAppearance`), and ⋯ → *Text Appearance* opens the same panel, a popover pointing at Aa either way. The web page
  under the reader takes no touches and is hidden from VoiceOver; a swipe from the left edge does
  what ‹ does (back, which closes the reader).
- **Library Read replaces the Library in place** (same `ReaderSurface`, `ShellState.libraryReader`):
  a row's ⋯ → Read shows the article's text over the Library, which stays the lit segment and under it
  with its scroll; the chrome folds to a bubble naming the article on a scroll down in Scroll mode and stays expanded in Pages mode (as in the Browser's reader mode), ‹ (`libraryReaderBack`)
  or a left-edge swipe closes it, and there is no player card. Row 1 is `[‹][Aa  site][Listen]`, as the
  Browser's reader mode: Aa opens the text appearance panel. The Library's ⋯ is a round glass face at the
  top right, on the title's line, gone in full screen. The heading's ▶ Listen starts it, as in the
  Browser's reader mode. Nothing plays until then. Opening a saved page anywhere else on compact width
  (Prepared Audio's rows) opens it here too. At regular width Read keeps opening the sheet.
  A search in the Library ends when Read opens, so the chrome shows the reader's row and not the keyboard form.
- **⋯ is not in the chrome.** Each screen's menu keeps its rows and their order (`MenuContext`) and is a
  system menu (`MenuRows`, `TitleMenuButton`), the panel's big buttons as its last section:
  - the Library home: ⋯ at the end of the title's line (`libraryMore`); a folder's screen: ⋯ beside Edit in its
    navigation bar; Library Read: a round ⋯ at the top right. The Library's menu adds *New Folder…*,
    *Import from…* and *Paste Text…* to its screen's rows, and *History* is among its last rows. *Paste
    Text…*'s *Save* opens the new article in Library Read.
  - Settings: ⋯ at the end of its title's line (`settingsMore`).
  - the Browser (page, start page, reader mode): a press and hold on the field's leading glyph (the reader
    icon, or 🔍 where there is none, `addressMenu`); a tap on the reader icon still toggles reader mode.
    Its rows: *Open in Reader* (or *Show Web Page*), *Listen* (Listen over the page you hear; another readable
    page is extracted and plays, and Listen rises once it starts), then the page's menu and the screen's rows
    regular width's ⋯ shows (*Save to Folder…*, *Follow…*, *Reload*, …), then *Saved* and *History*.
  Compact width has no *Settings* row anywhere: the pill has it.
- The field's and Listen's card's text grows with Dynamic Type up to *xxxLarge* inside
  the fixed pieces (larger clips or overlaps); every glyph offers the large content viewer. Every tap target is at least 44 pt.
- **Overlays, never rows:** prepare progress and toasts, on the top piece's edge.

## Planned: the rest of the bottom chrome redesign (approved design 5e, not shipped)

Still to come, from the approved design (mockups and build plan in the
project context, `work/bottom-chrome/`, outside this repo; the decision
`three-destination-bottom-chrome` in the project KB):

- **Widths:** below 360 pt or at large text, ‹ › give way to the field.

## Two surfaces: the Library and the browser (no tab bar)

The app has two surfaces: the **Library**, the folder tree, and the **browser**, a web page or the
start page. `BrowseStartView` hosts both (`ShellState.surface`), and each uses everything between
the status bar and the bottom chrome. On compact width the chrome host's pill switches between
them ("Bottom chrome", above); on regular width the sidebar does ("iPad and regular width",
below).

**The app reopens on the surface you left** (decision D10): the Library at the folder you were in
(`ShellState.libraryPath`, folders that no longer exist dropped), or the browser on its last page,
reloaded. A fresh install opens the Library. Kept on the device in UserDefaults
`shell.lastSurface` (`SurfaceMemory`). Reopened on the Library, the browser's last page loads the
first time you go there, and stays remembered until then, across relaunches. `-uiTesting` launches
start on the browser unless `-restoreSurface`.

**Regular width: one band on both surfaces** (`SurfaceBand`, decisions D22 and D23): the field
(the address field on the browser, *Search Library*, or the tab or folder it searches, on the
Library) at the top of the main pane, with a round ✕ beside it while searching, over the clustered
dock, whose toolbar has one role per slot on both surfaces:

| Slot | Browser | Library |
|---|---|---|
| 1 | ‹ web back | ‹ up a level (dimmed at the home) |
| 2 | › web forward | › (always dimmed: the Library has no forward) |
| 3 | 🔖 save the article / remove it (held: *Save to Folder…*) | ＋ *New Folder…*, *Import from…* |
| 4 | 🕘 History | 🕘 History |
| 5 | ⋯ | ⋯ |

A slot with nothing to do is dimmed in place, never removed, so nothing shifts.

**Shared bottom-chrome pieces** (`Features/DesignSystem/Chrome/`: `BottomChrome.swift`, `RegularBand.swift`), used by the
regular-width band and dock and by the reading sheets' bands: the band (`bottomChromeBand`: 12 pt
margins, 8 pt top padding, system bar material through the home indicator), the field capsule
(`bottomChromeField`: 44 pt, chrome-coloured capsule; 36 pt body-size controls inside, like 🎤),
and the toolbar row (`BottomToolbarLayout` + `toolbarIconFrame`: 44 pt, plain 20 pt glyphs). With
larger text the capsule and its controls grow (up to 1.5×) instead of clipping; toolbar glyphs
keep their size and show in the large content viewer on long press. Every control takes taps in at
least 44 × 44 pt (`tapTarget`), whatever its drawn size. **Five equal slots, evenly spaced, one
grid for every row:** each item names its slot (`.toolbarSlot(_:)`); a slot nothing names stays
empty, so items never slide along, every icon in slot N is at the same x and the ⋯ menu grows from
the same spot. ⋯ is never replaced.

- **A new search** is a tap on the address field: it selects the article's address, so typing
  replaces it (Recent Searches show full-bleed, Safari-style); ✕ cancels and restores the article's
  address. Swipe down lowers the keyboard but stays in search mode (typed text and Cancel kept). The
  page stays loaded underneath. ⋯ → *New Search* opens the start page with an empty field.
  Text without a scheme loads as an address only when its host ends in letters (`.com`, `.uk`,
  `.js`) or is an IP address; anything else ("3.14", "e.g.") is a Google search, and the
  suggestions follow the same rule (`BrowseURLParser`).
- **🔖** (regular width, slot 3; on compact width ⋯ has the page's *Save to Folder…*) is the Reader's 🔖 for the article on screen: tap saves it to the Library's top level
  (extracted first; 🔖 spins), or removes it when it is saved (filled, jade); held, it opens the
  Move tree (*Save to Folder…*). Dimmed on the start page. **🕘** (slot 4; on compact width a tile of ⋯) opens History: the
  pages visited, newest first, as Library rows (the site under a titled visit, none under an
  untitled one, whose title line is already its site; then how long ago). A tap loads it; its ⋯
  and long press are the article's menu ("Menus", below; on the Library's article for the address when
  it has one), then *Remove from History*. Empty, it says *No History Yet*, "Pages you open show up here.", over *Browse the Web* (closes it) and *Open Library*.
- ‹ / › are web history (disabled when WebKit can't go back / forward; KVO on the web view, so
  same-document history counts too). The web view's own edge swipes still work; over the in-place
  reader, a swipe from the left edge does what ‹ does.
- A page whose web content process ends (WebKit crashed, or iOS took its memory) shows blank
  until it loads again, so it reloads by itself: at once (in the background, once the app is in
  front), then after 2 s and 5 s when the new process ends too. A fourth end within a minute
  leaves it blank until ⋯ → *Reload* or another article (`ContentProcessRecovery`). Follow's
  chapter preview (also a `WebView`) reloads the same way; once it gives up, closing and
  reopening the preview loads the chapter again.
- No Reader button in the toolbar. The **reader icon** (📄, like Safari's article-format icon) sits
  at the leading edge of the address field only when the article is readable (the same Mozilla
  `isProbablyReaderable` check extraction uses, run after each load / same-document URL change);
  otherwise the lock / search glyph is there. Tapping it shows the page's reader view in place on
  compact width ("Bottom chrome", above) and opens the Reader sheet on regular width (a spinner
  replaces it while the article is extracted); on the article that is playing it opens Now Playing.
- **🎧** (headphones, trailing end of the address field; regular width only, compact has ↻ there)
  also shows only on readable pages. It is
  the article's own play button: grey when the article isn't what you hear (tap: listen now: a spinner
  while the article is extracted, what's playing keeps playing until this article is ready, then it
  replaces it, at the article's spot if it has one, or from the top if it was heard to the end; if
  extraction fails or finds too little text, 🎧 goes back to grey and a toast says "Nothing to
  listen to on this article"; Stop Listening, any other ▶ / ⏸ or another 🎧 while it extracts
  cancels it, silently); jade with moving bars when this article is playing
  (tap: pause); jade with still bars when it is loaded and paused (tap: resume). It never
  navigates.
- **⋯** opens a Safari-style menu panel that grows out of the button (covers the ⋯, no arrow):
  the article's own menu (the same rows as everywhere the article's menu shows: "Menus", below), then
  *New Search, Follow…, Reload, Prepared Audio, Settings*, then a row of big buttons **Saved**,
  **History**, and **Reader** (rightmost, nearest the thumb, like Safari's All Tabs). The page's
  *Save to Library* and *Save to Folder…* extract it first. *Follow…* reads the story the article
  belongs to ("Follow a story", below). On the start page there is no page, so no page rows;
  *Follow…*, *Reload* and the Reader toggle show dimmed; the Reader toggle is dimmed on pages that
  aren't readable too, and on a readable page tapping it switches into reader mode. Actions that present something (Share, Settings, History, the Move tree)
  run after the panel has closed.
- **The ⋯ panel** (`MorphMenuOverlay`: one overlay for the browser toolbar ⋯, the library
  toolbar ⋯, the Reader's ⋯ and regular width's Now Playing ⋯; its rows come from the surface that opened it,
  `MenuContext`: the item's menu, the screen's rows, the big buttons) is not a popover: it is placed so the bottom-right button's icon (Reader,
  or Website in the Reader and Now Playing — marked with `morphMenuFocus`) sits slightly up and to
  the left of the ⋯ glyph (Safari's feel: **12 pt left, 10 pt up**), not dead-on on top of it.
  Like every menu in the app (the long-press ones too), it keeps its shape (decision DR-09): a row
  that applies to what the menu is for but can't run now shows dimmed, and only a row that can
  never apply to that kind of item is left out (`MenuAvailability`). A toggle is one row showing
  the face for the item's state (*Save* / *Remove from Library*, *Mark as Finished* /
  *Unfinished*). A row that deletes something is red in it as in a long-press menu. Its rows are
  44 pt (`Control.tap`, a system menu's row), so at the default text size every panel fits on
  an iPhone 17 Pro, a folder's screen's too. A panel taller than the room above its ⋯ (larger
  text) stops below the status bar and its rows scroll; the big buttons stay at the bottom. It covers
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
- **One saved state**: the browser's 🔖 and ⋯, the Reader and Now Playing all read "is this page
  saved?" from the article for its address, else its key (`ArticleActions`, `ArticleLookup`), the article
  Save saves into and *Remove from Library* removes, and they follow a change made anywhere at
  once.
- **One library**: everything is an article in a folder (or in none). An article is a *link* (an address
  you kept, such as an address saved from a website: no text or audio), *saved* (text and audio kept), or played
  without saving (kept while in the last 50 of History, listed in the Library's History tab, and in the bar). *Remove from Library* is one action wherever it is asked (a row's swipe or menu,
  Edit, 🔖, the ⋯ of the browser, the Reader and Now Playing, the Now Playing bar's long-press):
  the article leaves its folder and every Library list it was in, History too; if it is what you hear, playback stops, as for
  *Stop Listening*, and Now Playing closes. It is kept while it is in the last 50 of History (C134) (an article never
  played goes at the next launch) but the bar doesn't offer it, and it comes back only when you
  save it or listen to it again (🎧, the Reader's Listen). There is one article per address: saving
  a link saves it in place. 🔖 = saved.
- **The Now Playing bar** (`NowPlayingBarView` → `NowPlayingBar`) shows what you hear in the
  Reader's band while another article plays: a flat card on the `PlayerCard` surface
  (reading-palette card fill, tile colours, radius, no shadow, progress track) with the article's
  artwork at the shared 40 pt tile size, its title (its site, or its book, when it has none), the
  site and the time left (two parts set apart by space, the time in lighter ink; at the playback
  speed, written as rows write it: "9 min left", "6 h 10 min left"), a groove progress line (4 pt,
  matching the scrub track) inside the card, and play/pause. At the end of an article it stays,
  reading ◉ Finished, and ▶ plays the article again. Tap or swipe up → Now Playing; long-press →
  the article's menu ("Menus", below; its *Remove from Library* stops the article you hear, as
  anywhere else), then *Stop Listening* (unloads the article). It hides on Now Playing, under other
  sheets and once nothing is loaded. Elsewhere on compact width the chrome's Listen does its job,
  and on regular width the clustered dock does.

**Start page** (no page loaded), Safari-style:
1. **Frequently Visited**: the sites you visit most, from the browser's History (no tracking of
   its own): History keeps one visit per page, the last 30, so a site counts its pages there, the
   most first, then the most recently visited. One tile per site (`www.` folded in): its icon (the
   newest visit's that fills a tile, else the letter tile) and its host below. 4 per row, up to 8
   (at the accessibility sizes one per row, the host beside its tile).
   While fewer than 4 sites are in History, starter tiles fill the first row: *Wikipedia*,
   *Standard Ebooks*, *Project Gutenberg* (letter tiles). A tile opens the site's home page in
   Browse; it has no long-press menu. Show All opens History (`FrequentlyVisited`).
2. **Recent Searches** (local, newest first, *Clear All*; each a 🔍 row, as in the search layer).

## The Library

The Library is a stack of screens in a `NavigationStack` (`LibrarySurface`, the path is
`ShellState.libraryPath`): the home, then folder → folder at any depth. ‹ and the edge swipe go
back up, as does the regular-width dock's ‹ (dimmed at the home). The home's title line is *Library* with ⋯ at
its end on compact width, then **Library / History** tabs, the system's segmented control at 44 pt (`SegmentedTabs`) (C104; History is the `recent` case,
stored as `history`, once labelled Recent); the bottom field searches the tab on screen and says so (*Search Library* on
Library, *Search History*). On a folder's screen it searches that folder,
everything under it, and says so (*Search Demo Finance*): the results stand under the folder's
name, each row showing where it is below the folder (its site when it is in the folder itself);
the search ends when you leave the folder. Each tab
is one mixed list: folders and pages share a single list, with no section headings. The History tab is everything you opened or started (C104); the browser's
*History* (🕘 on regular width, a row of the compact menus) is its pages visited. The two share a name (the
owner's choice, 2026-10-30). From the Library, 🕘 opens History over the Library, which stays under it (C130). A row under a minute says *<1 min* (C131). The Now Playing bar's line two names the article's folder when it is in one, as History does (C130). In an imported EPUB or followed story ＋ shows as in any folder (C149); a folder header's More ends with *Delete Folder…* alone at the bottom, after the create group. On
History and in search results a row in a folder shows that folder's
path in place of its site, and a folder opens in its place, under its parents, so ‹ goes to its
parent. Going to a place in the Library (Now Playing's ⋯ → *Go to …*, the title on Listen's card,
an imported book) opens it on Library, where every place shows; Library
comes back to the tab you left. Either way a page open in Library Read closes first, so the place
asked for shows. The tab is remembered with the surface. On compact width the chrome's row 1 is the search
field and the title line's ⋯ holds the creating rows, with *History* among its last rows ("Bottom chrome", above); on regular width the
band and dock are the browser's: the search field and `[‹][›][＋][🕘][⋯]`. ＋ is the ⋯ panel's two creating rows, *New Folder…*
(*New Folder…* in a folder) and *Import from…*, both made in the folder on screen (a book's too). Browser shows the browser as
it was; Library there comes back to the same folder. The
⋯ panel follows the screen on top (below): a folder's screen starts with the folder's own menu,
then every screen has *Sort ›, New Folder…**, Import from…,
Follow…, Prepared Audio, Settings*, and the big buttons **Saved**, **History**, **Browser**; nothing in it acts on the page under the Library. History closes the Library first; Browser is the same
as the chrome's Browser.

```
Library                                ⋯   ⋯ on compact width: New Folder…, Import from…, Paste Text…, Add Link…, Sort, …
Library  History
▣ Pride and Prejudice              ⋯   tap opens; its cover never changes (C102)
▣ Tide Tables                      ⋯
▣ Finance                          ⋯
[i] Seven-Day Yield                ⋯   tap plays; ◌ queued, a filling accent ↓, then a filled ↓ before its second line
```

Secondary lines (a row's second line, the bar's, a header's details) never join their parts with
a separator character: the parts sit apart by space (`DetailLine`, `Spacing.s`, growing with the
text), the first in secondary ink and the rest in the lighter tertiary ink; a playing row's status
is in the accent. A row's second line is always one line: the first part (the site) truncates
when it is short of room, and at accessibility text sizes the row shows its status alone there
(VoiceOver still reads every part). A section's count is its
own lighter label after the title (*Pages* then *48*). VoiceOver reads the parts joined with
commas.

- **The home** (`LibraryHomeView`, C104): Library shows what is saved: top-level folders and pages in
  no folder (*New Folder…* is in the title line's ⋯ on compact width, ＋ on regular width). Preparing an article saves it to the Library first (an article played without
  saving goes to the top level). History shows every article you started listening to
  ("opened" is started: `lastPlayedAt`), saved, prepared or played without saving (no folders,
  links or chapters), most recent first, in the same rows; a tap plays one. An unsaved one's ⋯ (and
  long-press) has *Save to Library*, which moves the article into the Library (it stays in History), *Save to Folder…*, and *Remove from History* (the same remove as *Remove from
  Library*: in no list after, pruned later), *Prepare Audio* (which saves it first, C104), and the marks dimmed until it is saved; swipe left is *Remove from History*. *Remove from History* never shows on an article in the
  Library (a saved article in History has *Remove from Library*), and is dimmed on one out of it that
  isn't in History. Every empty screen looks the same (`EmptyState`): a heading, one line under it, and
  its ways in as tiles (`ActionTile`), side by side (at the accessibility text sizes stacked, each a
  row with its symbol beside its label), the first accent-tinted, 96 pt below what is above it (24 pt
  at the accessibility sizes). An empty Library says
  *Start Your Library*, "Save articles from the web, a file, text or a link.", over four tiles, two by two:
  *Browse the Web* (the Browser), *Import a File* (as *Import from…*), *Paste Text* (as *Paste Text…*)
  and *Add a Link* (as *Add Link…*); History says *No History*, "Articles you play without saving show
  up here for 7 days.", over the same four. Search with no match is the system's search view.
  Search filters the tab on screen: on
  Everything the Library's folders and pages across the tree, on
  History its pages; folders by name, then pages by title (the newest first among equal
  titles); a result keeps its location and shows the path (one at the top level keeps its own second
  line). Rows are the compact two-line
  rows (below): an article row plays on a tap, a folder row opens, and each has only ⋯. The bar's ▶
  resumes what you last heard, and a folder row's ⋯ › *Continue* resumes its own pages without
  opening it (D14). A first-run empty Library shows *Find Something
  to Listen To*, naming 🌐 and ＋ by their symbols, with *Browse the Web* and *Import
  Book…* on one action row. The home has no navigation bar; rows scrolled up pass under a paper
  band behind the status bar, not under the clock. The home is the
  top level: its ⋯ is *Sort ›* (the order of the pages in no folder: *Manual*, *Newest*, the
  default, or *Title*), *New Folder…, Import from…, Paste Text…, Add Link…, Prepared Audio*.
- **A folder** (`FolderScreen`, books and series included): a centred header (YouTube Music's
  album header), then subfolders first (by their order), then pages by the folder's sort. The
  header is the title and counts; a folder with details has its cover above them (below). Once
  something in it has played, one more line says where it is, how far and what's left ("3 of 7
  38%   6 h 10 min left", at the playback speed); before that, its length ("52 min"). A folder
  with pages that play (decision D15) then has one row of three controls, the ▶ in the middle
  and a caption under each side one (the captions go, leaving the symbols, when one wouldn't fit
  whole, as at the largest text sizes: the row never wraps, D21):

  ```
              ◯↓            ( ▶ )            ⋯
           Prepare                        More
  ```

  The ▶ is a 62 pt disc (`Control.prominent`, as on Listen's player card) with a 26 pt glyph, and Prepare and More 36 pt (`Control.small`); the middles of the three controls'
  symbols line up (the captions hang below), and the header's lines sit close.
  The big ▶ is the folder's *Continue* (its place, or the first page; ⏸ while one of its pages is
  what you hear: tap pauses). *More* opens the folder's own menu, the same as its row's ⋯ and
  the top of its screen's ⋯ ("Menus", below). **Prepare Audio** is the folder's Prepare toggle (F7): an outline ↓ while it isn't
  prepared; the circle filling with jade from the bottom as it prepared audio (the ↓ white where the
  fill has reached it; never a ring: rings are listening), the same in grey while its prepare is
  paused; a grey filled ✓ once every article its prepare covers is. Its caption says *Prepare Audio*,
  *Preparing*, *Paused* or *Prepared*, and VoiceOver
  reads whether the toggle is on and the percent. Tapping ↓ turns the toggle on (or keeps it on):
  every article in it prepared audio and so does every article added to it later (Follow's new chapters, a
  article filed in). Tapping it while it prepared audio or is prepared, with the toggle on, asks *Turn
  Off Prepare* ("Prepared audio stays. New pages won’t prepare."), shown by the control (a
  popover pointing at it); asked from a menu (*More*, a folder row's ⋯ or long press, the screen's
  ⋯), the same question points at the button that opened the menu. Off, nothing new prepared audio
  and what is prepared stays. Prepared with the toggle off, a tap turns it on again and
  nothing is prepared again: it stays ✓ and a toast says new pages will prepare. *More*'s
  *Prepare / Turn Off Prepare* row is the same toggle, its face whether the toggle is on, so
  *Turn Off Prepare Audio* is there (asking the same) even while the control shows ↓ with the toggle
  on (an article's prepare removed, or one that failed). An article whose prepare you remove stays out
  of the folder's prepare until ↓ is tapped again (or its own *Prepare Audio*, which takes it back). The toggle turns on for a story
  you're caught up on too, which then shows ✓: the next chapters prepare as they come.
  A followed story's status line sits between the details and the row. It plays
  its own pages (not its subfolders') in the order shown, page to page, link pages skipped (a
  followed story's stop playback, below).
  **Edit** (top right) enters edit mode: all changes during the session (reorders, renames,
  moves, deletes, new folders) are staged until *Done* (top right) commits them in one save;
  *Cancel* (top left) reverts every change (C148). Cancel replaces the ‹ back button (hidden
  while editing) and swipe-back is disabled, so the only exits are Cancel or Done. A "New Folder…" row (plus-folder icon,
  accent tint) shows at the top of the list. Check circles appear on every row; a drag handle
  (≡) on the right of each row is the only way to reorder — touching elsewhere scrolls or
  selects. Articles are reorderable in any sort (reordering switches to Manual). The toolbar keeps its five slots and shows
  *Move to…* (📁, slot 1), *Mark as Finished* (●, the listening ring made full, the middle),
  ＋ (slot 4: the create group, C126; its *New Folder…* makes a folder here and files the
  selection into it, like Files' *New Folder with Items*) and *Remove*
  (🗑, ⋯'s slot) as symbols for the selection. *Remove* takes the selected pages out of the
  Library at once, then asks before deleting the selected folders, which stay selected until
  their delete is saved (*Cancel* keeps them selected). ⋯: the folder's own menu, then *Sort ›,
  New Folder…, Import from…, Paste Text…, Add Link…, Prepared Audio*. Every ⋯ ends with *Prepared Audio,
  Settings*; *Settings* is always the last row, just above the big buttons.
  The screen's name shows once, in its header; the navigation bar shows it only once the header
  has scrolled under the bar. An empty folder's header has no counts; under it the empty view
  every empty screen has (`EmptyState`): *This Folder Is Empty*, *Move articles here, or save them
  here from the Reader's 🔖* (the toolbar's symbol), over the same four tiles as the Library's (into
  the folder).
- **Edit Details** (a folder's or book's ⋯, or a folder, book or series row's long-press menu)
  opens a sheet (`FolderDetailsSheet`): the cover (a letter tile without one), **Name**,
  **Author**, a **Book** toggle under *Labels* (C149: on calls pages "chapters", off calls them
  "articles"; EPUB imports default to on), and *Choose from Photos*, *Choose from Files* (images)
  and *Remove Cover*. *Cancel* changes nothing; *Save* stores all at once. A picked picture is
  kept as a 600 px JPEG thumbnail, as a book's cover is. A folder with a cover or an author (a
  book has its file's) shows the detailed header: the cover above the title, the author before the
  counts ("A. Writer   2 folders   3 articles"), then the same progress line and controls. Its
  row shows the cover in place of the folder symbol, and the author under the title until an
  article in it has played. Details change only the look: its sort, Edit, drags and drops are
  unchanged. Clearing the author and removing the cover brings back the plain header.
- **Importing a book** (*Import from…*: ＋, the home's and a folder's ⋯, the empty Library's
  card) opens the Files picker for EPUBs and PDFs. The picked file is copied into the app and the import
  sheet (`BookImportSheet`, medium, grows to large) comes up at once: the cover, title, author,
  file and chapter count once read; a progress line ("Reading chapters… 4 / 9"); **Add to**, the
  folder whose screen it started from (else the Library), with *Change*, which pushes the Move
  tree inside the sheet and works until the book is being saved (the book is saved there; a
  chosen folder deleted meanwhile shows as *Deleted folder* and the import stops, saying so); the
  first chapters and what is skipped for listening. It can't be pulled down
  while it works; *Cancel* stops it and keeps nothing. Done, it closes on the book's screen,
  with *▶ Play*, which starts the first chapter that plays. A refusal says why in one line with OK: copy-protected (DRM),
  password-protected PDF, fixed layout, too large, or not a readable book; so does an import or *Replace* whose save
  fails, which keeps nothing. A book already in the Library asks *“Title”
  is already in the Library*: *Replace* (the same folder, its name, place and order kept,
  positions kept where chapters match; *Add to* then shows where it is and can't change) or
  *Cancel* (decision D13). *Replace* finds the book's chapters wherever they were moved and brings
  them up to date there; a new chapter goes into the book just after the chapter before it;
  chapters the file no longer has are deleted if they are still in the book; pages moved into
  the book from elsewhere are never touched (decision D19). An `.epub` link in the browser downloads the book (a toast while it does) into
  the same sheet, which waits for *Import* (top right), going to the Library unless changed. One
  import at a time: a book whose prepare finishes while the import sheet is up isn't imported,
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
  folder. Importing makes it with one article per chapter, first in the book's order (its sort is
  *Manual*); after that the order is yours: Edit, drags and *Sort* change it, chapters move out,
  and pages and subfolders move in. Its cover and author are folder details (the detailed
  header). Its chapters use the ordinary page row, as pages inside any folder; front matter still
  shows dimmed with "Skipped" (a tap still plays it, and its ⋯ › *Read* opens it). A followed
  story's chapters waiting for their text use the link row, with where the text stands; a tap
  fetches the text, then plays it ("Follow a story", below). What sets it apart is only where it came from: *Replace* finds a book by its file
  (above), Follow reads a story's contents again and fetches its chapters, the Now Playing bar
  names it as the source of its chapters, and its finished chapters lose their audio (D7).

**Follow a story**: the browser's ⋯ → *Follow…* on a story's page (a Royal Road chapter leads to
its story article), or the Library's ⋯ → *Follow…* (the home, or a folder, which the story's folder
goes in), where you type or paste the story's address. Follow covers the screen:

1. *Reading table of contents…* with a spinner and the address: one request, signed in as in the
   browser. A page with no list of chapters, or a site that refuses, says so, with *Try Again*
   and *Edit Address*; a story followed already offers *Open Its Folder*.
2. **Review**: a *Chapters 109* section header (how many are kept is on the button, *Follow 107
   Chapters*), *Select All*, then every chapter (its title,
   and its address shortened) with a box: tap the box to keep or leave it out (an author's note,
   a Q&A). Tapping the rest of the row opens its **preview**, the app's own sheet rising over the
   list with the chapter's real page in the browser's web view (signed in as in the browser). Its
   header says it is a passing look: the chapter's title and its box (tap to keep or leave it
   out), then the chapter's address in a small capsule, a label you can't edit or tap, with 📄 at
   its end, which swaps the article for its Reader text and back (filled while the Reader text
   shows; dimmed until the article can be read). The article's load runs along the header's foot. It
   is a preview and nothing more: links, forms and back / forward to another article go nowhere (a
   article's gate or challenge posting back to its own address still works), and there is no Save,
   no ⋯ and no bar at the bottom: the page runs to the screen's foot. The page scrolls; a pull
   down on the header, or on the article while it is at its top, closes the preview; one that
   starts further down only scrolls, as in the Reader.
3. **OK · Follow 107 Chapters** makes the folder at once (named for the story, its author as the
   byline) with the chapters kept, as links, and opens it. Their text is fetched one at a time
   while the app is open, each waiting for the one before and a pause; slow replies lengthen
   the pause, and a site that asks to slow down (429), fails (5xx) or doesn't answer is backed off
   from a minute up to 30 minutes (TECHNICAL_SPEC.md, "Fetching an article out of sight"). Nothing is
   fetched while the app is in the background.

The story's folder header has one line: *📡 Following* in the accent, then where it is, its parts
set apart by space (never a separator), in secondary ink: *41 of 107 fetched* (the Following
sheet's words), or *checked today 8:02 AM   2 new*. While chapters couldn't be had this
launch, their count comes right after *Following*: *📡 Following   1 chapter couldn’t load
41 of 107 fetched*; a line too long for the screen wraps rather than losing its end. While its site
is backed off, a notice in the caution colour names the chapter that waits by its title (*The
next chapter* when it has none): *Royal Road asked to slow down (429). “Chapter 42: Low Tide” in 1:52, then
slower.*, or *Example.com isn’t answering. “Chapter 42: Low Tide” is tried again in 1:52.* A
chapter waiting for its text says *Fetching text…*, *Retrying in 1:52*, *Waiting*, or why it
couldn't be had (it is tried again at the next launch); tapping it fetches it next and then plays it.
Playing through the story stops before a chapter still waiting for its text, and the chapter
after the one playing is always fetched first. *Skip in Playback* on a chapter that can't be had
lets playback go past it.

Tapping the line opens **Following**: where it is read from, *Last Checked*, *Next Check*,
*Chapter Text* ("109 of 109 fetched", "107 of 109 fetched, 2 chapters couldn’t load"), *Last
New Chapters* ("today 8:02 AM, 2 added"), **Check Now** (↻, a spinner while it reads; a failed check says why) and
**Unfollow** (or *Follow Again*). About once a day while the app is in front, the story's whole
table of contents is read again and chapters it didn't list before go at the end of the folder;
chapters left out in Review, and ones you deleted, stay out.
No feeds and no notifications. Unfollowing stops the checks; every chapter added stays, and their
text is still fetched.

**Rows** are `ListRow`s, compact and two lines for every kind (YouTube Music's rows). A folder
row's second line is what is in it ("2 folders   3 articles", "Empty"), in Edit too; one whose pages
play shows its place and time left there instead. Every row's separator starts at its title. A
article row (a chapter too) is exactly two lines (decision D21): its title (its site, or its book, when it has none) on one line, truncated,
then one short line of what it is and where it stands, with a small thumbnail as tall as the two
lines. At the accessibility text sizes the title runs the row's width on up to three lines instead,
over the thumbnail, the second line and the ⋯. Its site comes first on that line everywhere (none for an article without a title, whose
first line already is its site), except in a book or series, whose header names the source once;
on History and in search an article in a folder shows its folder's path there instead. The listening mark stands in a
fixed-width column at the row's trailing edge, just before the ⋯, so the rings line up down the list
(C88): nothing before a start (the column kept; line two says "18 min"), a small ring part-way
(line two "6 min left"; the only rings in the app are listening), the same ring full once finished
(line two "Finished"; no ✓), and still or moving accent bars while it plays or is paused (the row
tinted, "Playing" or "Paused" in the accent); every time at the playback speed.

The row's only control is **⋯** at its trailing edge, centred on the toolbar's ⋯ slot as the
bar's ⏸ is; a long press opens the same menu (the item's one menu, "Menus" below; decision
D11), and a long press that moves lifts the row into a drag (below). **Tapping an article
row plays it** (replacing what plays; in a folder it carries on through the folder) and, on compact
width, slides Listen up over the Library, except the
article you hear, which opens Now Playing (a stray tap never pauses), and a link that can't play,
which opens in the browser; a skipped page plays when tapped. *Read*, the menu's first row, opens
it (the Reader; Now Playing for the page you hear; the browser for a link). **Tapping a folder
row opens it**; its ⋯ has *Continue* and *Play from Start*. Swipe left is the menu's own last row,
by its name: an article's *Remove from Library* (or *Remove from History*), which takes its row out of
every list once it is saved, and leaves it, with a toast, when it can't be; a folder's *Delete
Folder…* (*Delete Folder…*), which asks.
In Edit the row has no ⋯ and a tap selects it.

A row's prepare shows on the row, never as a button: **preparing** (queued in any prepare,
its own or its folder's, paused too) dims the thumbnail or folder symbol under a small jade disc
with a white ↓; **prepared** puts a small filled ↓ in the accent (C97) at the start of the second line, before
the site. Prepared means the article's whole audio was made ahead of time by a prepare (its ⋯ ›
*Prepare Audio*, or its folder's Prepare) and is there in the voice selected now (or one *Keep*
stored); audio rendered only by listening never earns it. A folder, book or series row shows ✓
when every article its prepare covers is prepared (decision D16). VoiceOver reads
"Preparing" / "Prepared" with the status.

**Folders play like books** (decision D15). Playing an article that is in a folder (a tap on its row, the
Reader's Listen, 🎧 on its article, the folder header's ▶) carries on through the folder, article to
article, then stops; an article in no folder plays to its end and stops. Every folder plays in its sort,
which is yours (a book's starts as the book's order). Link pages are passed over (a followed
story's stop playback until their text is in), and so are pages marked *Skip in Playback*. The page that last played is the folder's place: its
row shows the place and the time left and *Continue* resumes there, as a book's does; before
anything in it has played, the first article starts where it was left. Now Playing's "Playing
from" names the folder.

**Dragging rows** (decision D15), on the home and folder screens, without Edit: a
long press lifts a row (its menu, which the press opened, goes as it moves). Let go on a folder
row (its middle, for a folder) to file it at the end of that folder; the folder lights up in the
accent while it takes the row, with a tick. Let go between rows to place it there, a line
marking the place: a page among pages, a folder among folders (over a folder row's top or bottom
quarter); placing an article makes its folder's sort *Manual* (the top level's too, until the home's
⋯ → *Sort* picks another), numbered first as it was shown. A row lands with a success tick; a refused one with an error buzz. A book or
series takes drops as any folder, and its chapters lift as any article (decision D19). A folder
dragged over itself or a folder inside it is refused (the drag shows ⊘); rows on the home's
History tab or in search results (gathered from across the tree), an article played without saving
and rows in Edit don't lift. The list doesn't scroll by itself while a row is dragged.

| Row | Tap | Swipe left |
|---|---|---|
| Folder, book or series | opens it (push) | *Delete Folder…* / *Delete Folder…* |
| Saved article (including a chapter) | plays it (Now Playing if it's what you hear) | *Remove from Library* |
| History article (played without saving) | plays it (Now Playing if it's what you hear) | *Remove from History* |
| Link page | opens it in the browser (a followed story's chapter: fetches it, then plays it) | *Remove from Library* |

### Menus

**Which options each menu has, in what order, and when each is greyed or hidden is `MenuRegistry` (C98, C99); docs/MENUS.md lists them with the generated table. Where this section names a different set of rows, MENUS.md wins.**

An item has one menu wherever it shows (decision C4): an article's (`ArticleMenu`), a folder's
(`FolderMenu`, books and series too) and a prepare's (`PrepareMenu`). The same rows, in the same
order, with the same names and symbols, in a row's ⋯ and its long press, a
History visit, the Now Playing bar's long press, a folder header's *More* and the top of every ⋯
panel that is about one item (the browser's page, the Reader's, Now Playing's, a folder's screen).
A place only hides a row that can never apply there or dims one that can't run now (DR-09); what
a place adds of its own comes after, set apart by a divider (the ⋯ panel's screen rows and big
buttons, the bar's *Stop Listening*, History's *Remove from History*). Rows that delete something
are red everywhere.

| An article's menu | Where it shows |
|---|---|
| *Read* / *Go to <place>* | *Read* (the Reader; Now Playing for the page you hear; the browser for a link or an address the Library hasn't) where the page isn't open; Now Playing has *Go to* its folder or the Library in its place; neither on the Reader or the browser |
| *Play from Here* | an article in a folder, in a Library list |
| *Prepare Audio* / *Remove Prepared Audio* (red) | a page out of the Library is saved first (C104); dimmed only on a browser page not yet loaded as a page |
| *Move to…* / *Save to Folder…* | *Save to Folder…* out of the Library (the Move tree, titled *Save to Folder*, saves it there), *Move to…* in it |
| *Mark as Finished* / *Mark as Unfinished* | dimmed until it is saved |
| *Mark All Above as Finished* | an article in a folder, in a Library list |
| *Skip in Playback* / *Play in Playback* | an article in a folder |
| *Share* | an article with a web address |
| *Select* | a folder screen's rows (Edit with that row selected) |
| *Save to Library* / *Remove from Library* (red) | *Save to Library* dimmed without text to save |
| *Remove from History* (red) | an article out of the Library; dimmed while it isn't in History |

| A folder's menu | Where it shows |
|---|---|
| *Continue*, *Play from Start* | dimmed while none of its pages play |
| *Prepare Audio* / *Turn Off Prepare Audio* | its Prepare toggle; *Prepare Audio* dimmed without pages, *Turn Off Prepare Audio* asks first |
| *Remove Prepared Audio* (red) | dimmed while nothing in it is prepared or preparing |
| *Move to…* | |
| *Rename…*, *Edit Details…* | |
| *Select* | a folder screen's rows |
| *Delete Folder…* / *Delete Folder…* (red) | asks first |

A toggle is one row showing the face for the item's state. *Remove Prepared Audio* takes the article out of
every prepare and deletes its audio (it stays out of its folder's prepare, P8); a folder's
*Remove Prepared Audio* does it for each of its pages. *Turn Off Prepare Audio* keeps what is prepared,
so it isn't red. A prepare's menu is in "Prepared Audio", below.

**Prepared Audio** (decision D16): *Prepare Audio* on an article, a folder, a book or a followed story (a
article's menu wherever it shows, a folder header's Prepare control, a folder's menu, beside its
*Remove Prepared Audio*, dimmed when there is nothing to do) makes it ready to play offline: a link article's text is fetched out of sight (in Follow's one
queue) and kept where it is, then its whole audio is rendered ahead in the on-device voice
selected (Kokoro). A folder covers its own pages in its order (not its subfolders'), a book or
story its chapters that play and aren't finished, one page at a time, and while its toggle is on,
pages added later too. A prepare starting (or a paused one going on) shows no toast: the row's
mark and the folder header's Prepare control already show it, and that control, while its
prepare runs, is captioned with the count ("2 of 3") and opens the Prepared Audio list (C96). Other
toasts (*already preparing*, *Nothing to prepare*) float just above the Now Playing
bar (never over it), as every toast does, and goes after a few seconds. A toast's message wraps
between words, never inside one: when a word wouldn't fit beside *View* (the largest text sizes),
*View* goes under the message, and then the symbol goes. Over the Reader and Now Playing a
toast, like the Now Playing bar and the play controls there, takes the reading theme's card,
inks and accent. Nothing is modal:
while prepared audio run, a 2 pt jade line along the top edge of the bottom chrome (the browser's, the
Library's, the Reader's) fills as they get on, and fades when nothing is queued, everything queued
is paused, or no on-device voice is selected (VoiceOver reads it as *Prepared Audio, N percent*, a
button that opens the list). Rendering happens while the app is in front: the article playing and the
chapter after it always go first, a hot phone or Low Power Mode holds it, and in the background
prepared audio wait (only what plays renders there, in bursts; LISTEN_PLAYBACK.md).

```
Prepared Audio                                       ( Done )
Now                                        Pause All
[i] Chapter 3: The Tide                        ⋯   ↓ filling (its own progress) before line two
   ↓ Demo Folder   17%
Waiting  2
[i] Chapter 4: The Bay                         ⋯   spinner, in the order pages render
   ◌ Demo Folder   Kokoro Heart
Prepared  1
[i] Coupon Basics
   Kokoro Heart   12 MB
12 MB on this iPhone
Different Voice  1
[i] Seven-Day Yield
   Kokoro Bella   9 MB
   ( ↻ Prepare Again )
```

**⋯ › Prepared Audio** (`PreparedAudioSheet`, every ⋯ panel: the browser's, the Library's on every screen,
the Reader's, Now Playing's; medium, grows to large; also Settings › Prepared Audio & Storage ›
Prepared Audio, pushed) lists one row per page (C110: a folder's pages each on their own row, never a folder total;
line two its folder's name, or its site for an article in no folder; the status mark before it:
spinner waiting, accent ↓ filling while it renders, filled once done), in sections shown only
when they have rows (**Now**, **Waiting** in render order, then the ones below; a folder's own
prepare is turned off on its screen, *Pause All* pauses everything). Older text below
describes record rows: **Queued** (the prepare rendering now and those waiting, *Pause All / Resume All*, each
row's filling arrow, just before its ⋯, pausing it; grey while paused, a tap resumes it; a paused
prepare is grey on its Library row and its folder's header too, captioned *Paused*),
**Prepared** (each with the grey ✓ and the room it takes, the total under the section, on the
cards' edge), and **Different Voice** (done, but its audio isn't in its article's voice, C138:
it never plays). Every row is a Library row (`ListRow`: one title line, one detail line) and names its voice
("Heart", C138; From Listening rows too); its parts are set apart by space, never a dot. A row opens what was prepared
(the Reader, or the Library at the folder). Its ⋯ and long press are the prepare's one menu,
the same in every section (`PrepareMenu`): *Pause / Resume* (dimmed once done), *Prepare Again*
(renders it again in its article's voice, C138; dimmed while queued) and *Remove Prepared Audio* on an article,
*Remove Prepared Audio* on a folder (red: the same action as in the article's or folder's own menu,
below). *Keep* is gone (C138): changing the voice in Settings no longer moves anything here; an
article's own voice changes from its menu's *Voice: Heart*. Swipe left is the same *Remove Prepared Audio* / *Remove Prepared Audio*.
The list holds prepared audio of what is in the
Library: removing an article from the Library, or deleting an article or folder, takes its prepare off
the list too (a removed article's audio stays, ephemeral). While Apple's voice is selected nothing
renders: queued prepared audio say *Needs a voice* (short, so line two keeps the folder, C130), with *Settings*. *Remove
Prepare* on an article and *Remove Prepared Audio* on a folder delete its audio and its prepare (a
article's listening audio alone, never prepared, is cleared only by its folder's *Remove
Prepared Audio* or Settings); the audio
of the article you hear and of the chapter staged after it stays for listening. It stays deleted: a
folder's prepare that listed the article drops it (the folder stays under *Prepared* if the rest
is done, and its header's Prepare control shows ↓ again, since not everything in it is
prepared), and nothing renders the article again until it is played or Prepare is tapped (the
page's, or the folder's, which lists the folder's pages afresh). A page
that couldn't be fetched or rendered is counted ("2 couldn’t prepare"), and *Prepare Again* tries
again. The list is kept on the device (`Downloads.json`) and goes on after a relaunch. With
nothing in it, it says *Nothing Prepared* (`EmptyState`): prepare an article from its ⋯, or a
folder or a book from its screen's ↓, over *Open Library* and *Browse the Web*.

**The Move tree** (`MoveTreeSheet`): one sheet for *Move to…* (titled *Move to*) and every *Save
to Folder…* (an article's menu out of the Library, 🔖 held; titled *Save to Folder*); the import sheet's *Add to* pushes the same list inside it. The whole tree as one indented list (medium, grows to large): *＋
New Folder…* (made at the top level, and the item goes in it), *Library (no folder)*, then
every folder, depth first. One tap files; ✓ marks the current place; a folder's
long-press offers *New Folder…* (made in it, and the item goes in that; dimmed on a folder
that can't be picked). *Library (no
folder)* files the article in no folder, out of the folder it was in; an ordinary 🔖 or *Save* keeps an article's folder. Every folder is a
destination, books and series too; a folder being moved, and everything inside it, can't be
picked. The tree closes
once what was picked is saved; a pick, or a *New Folder*, that can't be saved leaves it up under
the toast, to pick again or *Cancel* (in the import sheet, a *New Folder* that can't be saved leaves the
tree up the same way). The browser's *Save to Folder…* closes it on the pick, since the
article is extracted first (⋯ spins).

**A change that can't be saved** (a move, *New Folder*, *Rename*, *Edit Details*, *Sort*, a drop on a folder or
between rows, a
mark, *Remove*, a delete, saving or unsaving with 🔖
(the browser's, the Reader's or Now Playing's), *Save to Folder…*, ⋯ → *Save to Library* / *Remove from Library*) isn't stored: the
library reads as it did before it, and a toast says so ("Couldn’t move", "Couldn’t save") where
a success would have shown. *Remove* of several pages is one change: all go, or none. A folder's
screen doesn't follow a move that didn't happen, the Move tree stays up, and 🔖 keeps what it showed. In Edit, the selection stays when its change can't
be saved; Edit's *Remove* is two changes, the pages first and then, after the question, the
  folders, so a folder delete that can't be saved leaves the folders selected but doesn't bring back
  pages already removed. The toast shows over the Move tree, the import sheet
and Now Playing too. Listening goes on being kept meanwhile: where you are in an article, when you last played it and
whether you finished it are stored once saving works again, even across failed changes.

**Library search** is the bottom field, the same session as the browser's (`SearchSession`,
`ShellState.librarySearch`; drawn by `ChromeHost` on compact width, `SurfaceBand` on regular):
focusing it turns the chrome into its one searching row (on regular width it hides the dock's
toolbar) so the field sits above the keyboard with Cancel at its right (on a folder screen it goes back to
the home first, the list it filters); swipe-down / scroll lowers the keyboard but **stays in search
mode**; Cancel exits and clears the filter. While there is text, the home's list holds the folders
(by name, or a book's author) and pages (titles, sites, excerpts) that match, across the whole
tree in the selected tab, each with its location.

**Editing the address** (a Cancel state, so it closes like one):
- The toolbar steps aside and the field sits right above the keyboard, full width, with **Cancel** (text) to its right.
- An opaque layer covers the article with a rounded **card** at its top (Brave): `Search “typed”`, then history, a saved
  page and live suggestions, or Recent Searches (header + Clear All) while the field is empty; every row has a 🔍 and
  a ↖︎ that fills the term into the field without navigating.
- Cancel exits search mode: keyboard down, the article's address restored.
- Scrolling the Recent Searches / suggestions list drags the keyboard down with the finger
  (interactive, like Safari); with nothing listed, a swipe down on the layer lowers it. Either way
  it **stays in search mode** — typed text and Cancel remain; tap the field to type again.
- Focusing selects the whole address, so typing replaces it. While the field is empty or still
  shows the untouched address, **Recent Searches** (local, newest first, Clear All) are shown;
  otherwise the card's rows. **Live suggestions** come from Google's suggest endpoint (the app's one engine) as you type:
  one request after a 150 ms pause, the request in flight cancelled by the next keystroke and an answer that arrives late
  ignored, at most 6 rows in all, none for text that would load as an address, nothing on failure (the local rows stay),
  an ephemeral session with no cookies, cache or referrer, and nothing logged. **Settings › Browsing › Search Suggestions**
  (default on) turns them off; its footer says the typed text is sent to Google.
- 🎤 appears **only while searching** (the address field's `SearchSession`), not on the idle
  address bar. It dictates on-device (`SFSpeechRecognizer`, `requiresOnDeviceRecognition` when
  the locale supports it): partial text streams into the field; it stops on a second tap, on
  ~1.6 s of silence, or when you type. Listen pauses while the mic is open and resumes
  afterwards; its `.playback`/`.spokenAudio` session is restored. Nothing is submitted
  automatically.

## The Reader and Now Playing (what you see, what you hear)

What you **see** and what you **hear** are separate, in three layers: the surface (the browser or
the Library), the **Reader** for reading any article, and **Now Playing** (Listen) for what you hear.
Navigating never changes what you hear, and a play button never navigates (a Library row's tap, which
plays, slides Listen up on compact width). The Reader never shows
the article you hear: opening the Reader of that article (📄, a Library row) opens
Now Playing instead.

The two widths present them differently:

| | Compact width | Regular width |
|---|---|---|
| Reader | In place, under the bottom chrome (`ReaderSurface`): the Browser's reader mode and Library Read ("Bottom chrome", above). No sheet, grabber, pill, top bar or bottom band: Aa is in the chrome's field, ‹ starts row 1, and the heading reads the title, then "site  length  ▶ Listen" | A `Sheet` over the surface that opened it (`ReaderSheetScreen`): grabber, close pill, top bar, bottom band |
| Now Playing | Listen: a `Sheet` that covers the screen and the chrome, with a grabber, the article's title at the top of its text and the player card at its foot; a pull down closes it ("Bottom chrome", above) | A `Sheet` over everything that shrinks back into the Now Playing bar; its close pill names where it plays from |
| Into Now Playing | The chrome's round Listen, a reader's ▶ Listen, a Library row | The Now Playing bar (tap, swipe up), the Reader's ▶ |

The rest of this section describes the regular-width sheets unless it names compact width; the
compact readers and Listen are described under "Bottom chrome".

**On regular width the Reader and Now Playing share their chrome** (decision D24), so Listen turns the Reader into Now Playing
with nothing moving but what has to: the same top bar (the close pill at the top left, **Aa** then ☝︎ at the top right, at the article margin), one shared bottom band
(`ReadingBottomBand`: integrated controls flat on the page background, separated by a hairline
divider — title row, scrub track, transport row, no card, no shadow), the same
⋯ menu (Now Playing adds *Go to*), and the same colours and type (the reading theme, below). They
differ where the job does: Now Playing's transport has 🔖, ⏮, the round ⏸ / ▶, ⏭ and ⋯, the
Reader has ⋯, disabled ⏮/⏭ and a round ▶ that starts Listen; Now Playing has the scrub row with
the speed, and its text follows the audio (the Reader's sits under a heading and never moves by
itself).

### The Reader

The regular-width sheet (on compact width the Reader is in place: "Bottom chrome", above):

```
┌──────────────────────────────────────┐
│                 ───                  │ ← grabber
│ ( ‹ Browser )             (Aa) (☝︎)  │ ← the pill names what is underneath
│ example.org  9 min                   │ ← source and length
│ … text in the reading theme …        │
│ ─────────────────────────────────────│ ← hairline divider
│ [art] Notes on Tides          9 min [🔖]│ ← artwork, title, time, bookmark
│ [━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━] │ ← thin scrub track
│ [⋯]  [⏮]    (▶)    [⏭]       [1×] │ ← transport row
└──────────────────────────────────────┘
```

The sheet's heading shows the site and length above the text; its title is suppressed (the band
already shows it), so the title appears once. An article with no title of its own
shows only the site and length. The compact in-place readers and Listen show the title at the top of the text. When the article's own first heading repeats the title, that
heading takes the title's look and the source line moves under it. The length becomes the time left once the article
has been started, as in its row and on Listen (a finished article shows its length). In Scroll mode
the length line changes in place as the article is listened to, without reloading the text, so the
reading place stays; in Pages mode, whose pages are laid out from the heading's height, the text reloads. The reading
style always wins over an article's own styles (an extracted article's stylesheets are left out),
and an extracted title drops a trailing site name ("Speech synthesis - Wikipedia" reads "Speech
synthesis").

- **A sheet over the surface that opened it** (`ReaderSheetScreen`, `ShellState.reader`). From the
  browser (📄, ⋯ → Reader) the pill reads *‹ Browser*; from the Library *‹ Library*;
  the pill, the grabber and a pull down close it to exactly where you were.
- **The bottom band** sits flat on the page background: the artwork tile, the article
  title (one line, clipped), the time detail (*9 min*, *6 min left*, *Finished*) and 🔖 in a
  title row; a thin scrub track at position 0; and a transport row with 1× at the leading edge,
  disabled ⏮/⏭, the big round ▶ (Listen) and ⋯ at the trailing edge. No card, no shadow.
- **Listen** (the round ▶ in the transport) starts at the article's saved spot
  (at the playback speed, written as rows write it, "1 h 5 min left" past the hour; the time in regular weight after the semibold title, left out when the pill is short of room
  at large text sizes), or *▶ Listen Again* for a finished one. It starts at the article's saved spot, makes the article what you
  hear (replacing what plays) and turns the Reader into Now Playing in place, where the Reader was
  (decision D2):
  - **At the Reader's top** (its first line of text not yet scrolled above the top of the reading
    area, so the title may be part way up), Now Playing opens at its top.
  - **Scrolled into the text**, the same line stays at the same place on screen.
  - **When that place can't be reached** (past either end of Now Playing's article), the article goes
    as far as it can that way, so the line stays in view as near its place as possible.

  Now Playing sets that position once its article is laid out and holds it while the layout
  settles (the header, a text size change: each keeps the same line).
  It drops it if you drag, scrub, Jump to Audio, the audio moves on or the article reloads first. ☝︎ in the top bar, then a tap on a paragraph, listens from that
  paragraph (a hint banner with Cancel sits under the top bar meanwhile, at the article margin, as part
  of the header: the text's first line at the top starts below it). While ☝︎ is on, each
  paragraph is a button to VoiceOver, *Paragraph N*, hint *Plays from this paragraph*.
- **An article part-way through opens at its saved spot**: the sentence where listening stopped
  (where *Continue* starts) is in the middle of the text and underlined, without a scroll of your
  own, and stays there while the layout settles (the header, a text size change) until you drag.
  An article not yet started, or finished, opens at its top.
- **After that the Reader never scrolls by itself** and has no speed or skip buttons; reading
  text never moves under you. A text size change (Dynamic Type) keeps the line at the top of the reading
  area where it is, to the character; an article at its top stays at its top. Now Playing does the
  same, or, while it follows the audio, centres the spoken sentence again.
- 🔖 saves / unsaves (tap; filled = saved), or files the article (long-press → *Save to Folder…*,
  the Move tree: saved there, or moved there when already saved); it keeps the screen as it is,
  and playback too, except that unsaving the article you hear stops it.
- **⋯** (slot 5, the browser's ⋯ spot; Now Playing's is the same): rows *Save / Remove from Library, Move to…* (dimmed until
  the article is saved)*, Share, Prepare / Remove Prepared Audio* (dimmed until the article
  is saved; *Remove Prepared Audio* while it prepared audio or is prepared, as its Library row's menu
  shows)*, Prepared Audio, Settings*; big buttons
  **Saved / History / Website** — *Website* (the Reader off) shows the page in the browser,
  wherever the Reader was opened from; from the library, the library closes first. Playback
  never stops.
- The text fills the page down to the screen's foot and runs under the header and the bottom
  band, which are drawn over it (the header on the article's colour, the band on its tinted bar
  material); its first line starts below the header and its last line scrolls clear of the band.
  A tap in the middle goes full screen (below).
- **Links** in the text open in the browser when they lead to a web page (as ⋯ → Website does:
  the Reader leaves, Now Playing too); a link to a place on the same page goes there (in Pages, to
  the page holding it) and stops following the audio as a page turn does; any other link (mail,
  a book's links between its own chapters) does nothing. The text never leaves its article.

### Now Playing

The regular-width sheet (on compact width it is Listen, a cover with no pill: "Bottom chrome", above):

```
┌──────────────────────────────────────┐
│                 ───                  │ ← grabber
│ ( ⌄ example.com )         (Aa) (☝︎)  │ ← the Reader's top bar; the pill names where it
│                                      │   plays from
│ Title                                │ ← the article's title, at the top of its text
│ … text dimmed; the spoken paragraph  │
│   highlighted in full ink, the       │
│   sentence underlined …              │
│                 (↑)                  │ ← Jump to Audio: centred, 12 pt above the band, once you
│                                      │   scroll away (in full screen too)
│ ─────────────────────────────────────│ ← hairline divider
│ [art] Title              9 min left  │ ← artwork, title, time left
│ [━━━━━━━━━━━━━━━━━━━━━━━━━━━━] 1×   │ ← thin scrub + speed
│ Preparing next…                      │ ← status notes
│ [🔖]  [⏮]    (⏸)    [⏭]   [⋯]      │ ← transport row
└──────────────────────────────────────┘
```

- **Opens from** the bar (tap, swipe up), from opening the Reader of the article that is playing,
  from Listen in the Reader (in place, D2) and from crash resume (on compact width: the chrome's
  Listen, a reader's ▶ Listen, a Library row). It presents over everything
  (`ShellState.isNowPlayingPresented`) and holds no article of its own: it shows what you hear.
  **The close pill or a pull down shrinks it into the bar** (on compact width a pull down closes
  Listen), back on what was underneath (the browser, the Library, or a Reader of another page), untouched.
- **It reads like the Reader**: the same reading theme, typeface, size and spacing (see "Reading
  appearance" below). Over a light app, a dark theme (Dark, Black) gives it light status bar
  content and a heavier dim on the strip above it; while a finger pulls it down the dim lifts, but
  the strip under the status bar stays as dark as at rest until the sheet has gone, so the clock
  stays readable. The article's title is the first thing in its text; when the article's own first
  heading repeats it, that heading takes the title's look and shows once. The spoken paragraph is on the theme's highlight;
  every paragraph stays in full ink (C105). The *Jump to Audio* button takes the card's fill and the theme's ink; the scrub row, the bubble, the jump hint, the ⋯ panel and the speed popover
  take the theme's colours. A plain-text article (no reading HTML) shows its paragraphs on the
  same reading article, in both, so everything below applies to it too.
- **The bottom band** (flat on the page background, no card, no shadow) shows the artwork tile,
  the title (`ArticleRowTitle.lineOne`) and the time left (*9 min left*; *Finished* at the end)
  in a title row, then the scrub row with the speed control, status notes and the transport.
- **On regular width the close pill names where it plays from** (*⌄ Pride and Prejudice*; VoiceOver: *Close Now
  Playing*, *Playing from …*): the folder the article is in, a book, a series or one you
  made; *Library* for a saved article in no folder; the site for an article you haven't saved. Tapping
  it only closes. **⋯ → *Go to <name>*** (the first row) closes Now Playing onto the Library at
  that folder, or the Library's home, on Everything; for an article that plays from its site it reads
  *Go to Library*, dimmed until the page is saved, and ⋯ → *Website* opens the site in the browser.
  The Reader's ⋯ has no *Go to*.
- **Aa** and **☝︎** (top right, as in the Reader): Aa changes how the article reads; ☝︎, then a
  tap on a paragraph, plays from that paragraph.
- **🔖** (slot 1, as in the Reader) saves / unsaves (tap) or files the article (long-press →
  *Save to Folder…*, the Move tree); saving never touches playback, and unsaving (*Remove from
  Library*, here or in ⋯) stops the article, so Now Playing closes.
- **The text follows the audio.** It opens with the spoken sentence near the middle (the
  paragraph, until the sentence is worked out a moment later), from the bar, from opening the
  article that is playing and from crash resume; Listen in the Reader opens where the Reader was
  instead (D2). On each new paragraph it scrolls its spoken sentence near the middle; in a
  paragraph too long to stay on screen, it does so again whenever the spoken sentence leaves the
  visible text (the `Motion.standard` spring; a jump under Reduce Motion). The sentence, not the
  paragraph, goes to the middle: a long paragraph's middle can be a screen away from what is
  being read. The middle is the visible text's between the bars, and the whole screen's in full
  screen (the bars coming back over it never move the text). In Pages the page turns to the
  spoken sentence instead (below). The spoken paragraph lights up to full ink while the one before dims (a short
  fade; none under Reduce Motion), and the current sentence is underlined in the theme's accent, as in the Reader (per chunk on
  engines that report only chunk starts; no underline before iOS 17.2). Drag the text and following stops (a pull of the sheet from the text's top
  doesn't move the text, so following goes on). On compact Listen the player card's Jump turns into an
  arrow toward the spoken sentence ("Bottom chrome", above). Elsewhere a round *Jump to Audio* button floats over the text at the
  right edge, 12 pt above the player card of an in-place reader (level with the card's right edge; the bubble when it folds;
  on regular width above the band): a 48 pt glass circle on the round buttons' shared face (`ChromeCircleFace`), with an arrow
  that points to the spoken sentence, ↑ when it is above the visible text and ↓ when below (Pages: on an earlier or a later page).
  VoiceOver: "Jump to Audio", hint "Scrolls up / down to the sentence being read". Tap it (or start another page) and
  following resumes: the text scrolls so the spoken sentence is in the middle of the visible
  text (between the top of the screen and the bottom chrome), as when Now Playing opens, and
  stops at the document's ends where it can't centre. Scrubbing scrolls to the paragraph under
  the thumb.
- **At the end** it stays on the article: the text stays, all of it in full ink, the band
  says "Finished" where the time left was (the Reader shows the article's length), and ▶
  plays the article again.
- **Controls** (the band): optional status notes, then `[🔖][⏮][▶︎][⏭][⋯]` in the five-slot
  grid, then the scrub row and speed. (Compact width's Listen has the player card instead, its ⋯ a
  small system menu: "Bottom chrome", above.) ▶︎ / ⏸ is a 44 pt round button (accent fill, dark glyph; fixed size,
  like the toolbar glyphs), as tall as the row, so every slot sits where it does on the other
  surfaces. ⏮ ⏭ and headphone / lock-screen skips are paragraph skips
  (D4). A sideways swipe on the row skips too.
- **Status notes** ("Preparing next…", Apple-fallback / language notes, the
  developer-only Debug chip) sit **above** the transport row so appearing text never pushes it.
- **⋯**: the article's menu ("Menus", above) for the article you hear, with *Go to <name>* first (when
  it plays from a folder or the Library), then *Prepared Audio, Settings*; big buttons
  **Saved / History / Website**.
- A **prepare progress line** runs along the top edge of the bottom band while prepared audio run,
  as on the other surfaces, in the theme's accent.
- **Scrubber** (sentence-precise; the track runs inside the band): fill = progress
  (weighted by text length; with a local voice the thumb moves smoothly inside a paragraph,
  estimated from the player's time); the lighter fill ahead of it is audio already rendered (local
  voices; Apple speaks live so there is none).
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
- **Speed** (*1×*, at the end of the scrub capsule; a tap opens the list, 0.75× to 2×; Settings ›
  Listening has it as a row, *Speed 1× ›*, opening the same list): applied in place — the current sentence keeps going at the new speed.
  Local voices: a pitch-preserving time-stretch on the player (`AVAudioPlayer.enableRate` /
  `rate`; all audio, including Apple-fallback units, is rendered at 1×), so nothing is re-queued,
  re-rendered or restarted. The Apple voice (AVSpeechSynthesizer can't change a running
  utterance's rate) restarts from the word being spoken. The rate is persisted
  (`reader.rateMultiplier`) and the lock screen's playback rate follows it (and can set it).
- An article played without saving is kept while it is in the last 50 of Recent (C134), with its text and its
  spot: after a relaunch it is at the top of the Library's *Pages*, opens in the Reader where it was, and
  Now Playing shows its text.

### Full screen (the Reader and Now Playing)

The Reader and Now Playing read full screen the same way (`ReadingChrome`); Follow's chapter preview doesn't.

- **Full screen is a tap in the middle of the text, in and out, and nothing else.** In a compact
  in-place reader it removes the whole bottom chrome: its rows (or bubble), the fade and the status bar
  go (fade only under Reduce Motion), the home indicator dims, and the text shows alone, never
  moving, down to the screen's foot, with nothing floating over it. In compact Listen the player card slides off, the status bar hides
  and the sheet's top gap, rounded corners and dim go: the page covers the screen; the
  chrome under Listen keeps its state. In every reader, Scroll mode, the end of the text then scrolls down
  to the home indicator's strip (with the bars up, to just above what floats: the card, the band, the
  chrome as drawn); the text on screen stays where it is as they go or come, and a text at its end stays
  at its end. Pages mode keeps its pages as they are. **Scrolling does nothing to the chrome in full screen, and
  scrolling never enters or leaves it.** Leaving full screen returns to what the chrome was before
  (folded stays folded). On regular width the sheet's grabber, top bar and bottom band hide and show
  together the same way, and the sheet covers the screen as Listen's does.
  The app's own scrolls (following the audio, a scrub, opening at a spot) never change it. The bars
  stay while VoiceOver runs, while ☝︎ is on, and while Aa or ⋯ is open.
- **Not in full screen**, scrolling down folds the chrome to the capsule (above), in Scroll mode only; the text
  never moves for it.
- **Taps on the text** (not on a link; ☝︎ keeps its paragraph taps): the right 30% of the width
  goes forward a screen, the left 30% back one (the visible text less one line, landing with a
  whole line at the top: below the top bar, or below the fade in full screen; on the
  `Motion.standard` spring, a jump under Reduce Motion, never past either end), the middle enters or
  leaves full screen. The first 48 pt from the left edge do nothing, so an edge swipe never turns a
  page. Edge taps leave the bars as they are. In Now Playing a page turn stops following the audio
  as a drag does, and *Jump to Audio* appears.
- **A small ▶ / ⏸ floats at the bottom right** in full screen, in Listen and on regular width (never in
  a compact in-place reader) (a 44 pt accent disc with the
  shadow, above the home indicator, at the article margin): Now Playing's plays and pauses
  what you hear; the Reader's is its Listen (and turns it into Now Playing). It fades out 3 s after
  full screen begins; an edge tap (a page turn), or a tap on it, brings it back for another 3 s. A
  tap in the middle leaves full screen instead, and the bars come back. It isn't there while
  the bars show.
- **At the top**, a pull down in full screen rubber-bands and, on regular width, brings the bars
  back; scrolling never leaves it, and compact full screen is left by the middle tap alone
  (on regular width it never closes the sheet; a pull that begins with the bars showing closes it as
  usual, and while it pulls the sheet it never hides or shows the bars).
- The floating *Jump to Audio* (Now Playing, both widths) shows only while the text is away from
  the audio, centred just above the card or band, and in Scroll's full screen above the home
  indicator's strip, on the line of the floating ▶. Pages mode's full screen floats nothing over the
  text (the ▶ neither).

### Pages (the Reader and Now Playing)

With **Scroll / Pages** on *Pages* (Aa, Settings › Reading) both sheets show the text a page at a
time; Follow's chapter preview always scrolls.

```
┌──────────────────────────────────────┐   reading (bars hidden, C113)
│ Second page                          │ ← a page: the whole screen inside the safe area, whole
│ This offline test article has a long │   lines only, an even margin above and below
│ …                                    │
│ 2 min left                      33%  │ ← the footer: caption, quiet ink
└──────────────────────────────────────┘

┌──────────────────────────────────────┐   overview (a tap in the middle: bars shown)
│ ⌄ pages                        Aa ☝︎ │ ← the top bar
│                                      │
│ ┃ ┌──────────────────────────┐ ┃     │ ← the same page, scaled down (no reflow) into a card
│ ┃ │ Second page              │ ┃     │   centred between the bars, outlined in the accent;
│ ┃ │ This offline test …      │ ┃     │   the neighbouring pages peek at either side
│ ┃ └──────────────────────────┘ ┃     │
│                                 (↑)  │ ← Jump to Audio, when the voice is on another page (C111)
│ ─●──────────────────────────── 1×    │ ← the bottom band
└──────────────────────────────────────┘
```

- **An article** (C113, Kindle's) is laid out for the whole reading sheet, from 16 pt below its top (just under the status bar, C114) down to the footer, and holds
  whole lines only: no line is ever cut at its top or bottom. A line that doesn't fit starts the
  next page; a picture taller than a page shows a page-tall slice at a time until the rest of it
  fits, and the text after it carries on from there.
- **Reading and the overview**: reading, the bars are hidden. A tap in the middle shows them and
  the same article shrinks with a spring into a card between them (a scale of the article laid out for
  reading, so nothing reflows), outlined in the accent; the pages before and after are cards of
  their own beside it, the same size, parted by a gap and outlined in the theme's quiet rule grey
  (C116), fully drawn; a card ends at the text's bottom margin, with no strip kept for the
  footer, and *Jump to Audio* may float over its foot (C117); the accent outline follows the card centred as they swipe; the cards swipe sideways as pages do, and a tap anywhere on the card zooms back
  into reading. Under Reduce Motion the change is a short fade instead of the zoom.
- **The footer** (`2 min left` on the left, `33%` on the right), only while reading. The time is
  what is left from the first character of the article shown to the end of the article's text, at the
  playback speed, worded as the rows and the Now Playing bar word it; a chapter of a book or
  series says `2 min left in chapter`. The percentage is the page shown of the pages. It sits 12 pt
  above the home indicator's strip, at the page margins, in the Reader and in place alike (in place
  the strip comes from the window, `ChromeHome.inset`, since the page is laid out through it).
- **Turning** (C107): native horizontal paging, as Apple Books' *Slide*. The article is laid out in
  CSS columns a screen wide, in the web view's own scroll view with paging on, so a page tracks
  the finger 1:1 and settles with the system's physics; a tap at the right edge zone slides to the
  next page, at the left edge zone to the one before (the scroll view's own animation; at once
  under Reduce Motion); the middle enters or leaves full screen. The first 48 pt from the left edge
  stay the system's: a swipe or tap that begins there turns nothing. Pages never scroll
  vertically, so a pull down on the text doesn't close a regular-width sheet there (the grabber and
  the close pill do).
- **No following, nothing over the text** (C108): Pages is for reading. It never turns by itself
  with the audio: once the voice leaves the article shown, Now Playing offers *Jump to Audio* in
  its usual place above the band, as in Scroll (only while the bars show, C111), which shows the spoken sentence's page once. Neither
  the floating *Jump to Audio* nor the floating play / pause shows in Pages. Opening Now Playing
  in Pages still opens on the page you hear, or the Reader's handed-over line (D2).
- **Play from Here** (C109): selecting text (both modes) adds *Play from Here* to the system edit
  menu, before Copy; it plays from the start of the sentence holding the selection's start (the
  paragraph's start when none), saved article or not. A tap that clears a selection doesn't turn a
  article or toggle the bars.
- **The line being read stays** through a new layout (Aa's typeface, size or spacing, Dynamic
  Type, a picture arriving) and through switching Scroll ↔ Pages: the
  article holding it shows.

### Reading appearance (Aa, Settings › Reading)

One reading appearance for both sheets (`ReadingAppearance`, stored in UserDefaults
`reading.theme`, `reading.font`, `reading.textSize`, `reading.lineSpacing`, `reading.layout`), separate from the
app's theme. **Aa**, in both sheets' top bars just left of ☝︎, opens a compact panel pointing at
it; Settings › Reading has the same controls. Both edit the one store, so they never disagree,
and the article under the panel changes as you choose (colours repaint in place; a typeface, size or
spacing change reflows the text and keeps the line on screen where it was).

- **Theme**: *Match App* (the app's paper and ink in its appearance and colour; the default),
  *Light*, *Sepia*, *Dark*, *Black*. One token set each (`ReadingPalette`: background, card,
  ink, secondary and tertiary ink, dimmed ink, highlight, accent) for the Reader and Now Playing
  alike. The spoken paragraph sits on the highlight; every paragraph is in full ink (C105); the spoken
  sentence is underlined in the theme's accent (one underline colour per theme). Light, Dark and
  Black take the app's colour as their accent; Sepia has its own. Each is a swatch named under
  it; a name wraps between words, and at the accessibility sizes, where a name's longest word
  is wider than its swatch's share of the row, the swatches stand alone (VoiceOver still reads
  the names). Settings' *Color* swatches do the same.
- **Font**: *Serif* (New York; the default), *Sans Serif*, *Rounded*.
- **Text size**: smaller / larger in steps from 85% to 165% of the Dynamic Type size (100%
  default), so the system's text size still applies under it.
- **Line spacing**: *Compact*, *Normal* (the default), *Relaxed*.
- **Scroll / Pages**: one long column you scroll (the default), or a page of whole lines at a
  time (Pages, above).

Aa sits in the top bar, not the bottom row: Now Playing's five slots are full (🔖, ⏮, ⏸, ⏭, ⋯)
and the bottom chrome never moves, and the top bar is the one row the two sheets already share
control for control.

## Settings

**⋯ › Settings** (`SettingsView`; the last row of every ⋯ panel, and the sidebar's bottom row on
iPad; titled *Settings*, *Done* closes it) is a `NavigationStack` of cards on paper. Every list of cards in the app (the Library and its
folders, History, Settings and its pages, a Voice picker, Follow, Following, the Move tree, Folder
Details, Book Import, Prepared Audio) has the same rows: at least 48 pt at the default text size
(`Control.bar`, the system Settings' proportions, set once by `cardListStyle`: no row sets its own; a two-line row grows to its content), 16 pt
in from the card's sides with no List inset above or below, sections 16 pt apart, and a card's
note 8 pt under it (`cardListStyle`, `listCard`, `listFooter`). None of Settings' rows leads with
a symbol. Top to bottom:

- **Listening** (first; the audio settings):
  - *Voice ›* (`VoicePage`): the default voice for new articles and books, from the one voice
    switcher (`VoiceSelectionList`, the same list an article's or a book's *Voice* picker shows).
    *Phonon | Kokoro | Apple* chips choose which engine's voices are listed; picking a voice picks
    its engine. Phonon and Kokoro list their curated voices with samples, then *More voices*;
    Apple lists the installed voices for the language, Premium first. A voice's download shows
    progress below the list (tap to cancel; on cellular or Low Data Mode it asks first, "Download
    on Cellular?"), a downloaded Kokoro pack is removed with a swipe, and a crash or failure
    notice sits in the footer. The row's value never names the voice: *Default* while the
    built-in voice is the pick (Zoey, else Heart, else Apple's best), else its voice library
    (*Kokoro*, *Apple*).
  - *Language ›* (`LanguagePage`) and *Speed ›* (the speeds Now Playing lists, 0.75× to 2×, the
    chosen one ✓).
- **Appearance ›** and **Reading ›**, one card (nested pages, not inline rows):
  *Appearance* (`AppearanceSettingsPage`) holds *Theme* System / Light / Dark (the app's windows
  follow it) and *Color*: Jade (the default), Harbor, Plum, Ember, Graphite (the accent and what
  is drawn from it, on every screen; `AppAppearance`, UserDefaults `appearance.mode`,
  `appearance.accent`). *Reading* (`ReadingSettingsPage`) is the reading appearance above (the
  Aa panel), with a sample of what is chosen.
- **Browsing**: *Block Ads* (on by default): requests to common ad and tracker hosts don't load
  in any of the app's web views; a change applies to pages loaded after it.
- **Prepared Audio & Storage**: *Prepared Audio ›* (the Prepared Audio list), the size of the
  prepared audio, the size of the audio kept from listening, and the **version row** (a 2 s
  long-press toggles developer options, below).
- **About**: *Privacy Policy* and *Support* (open the project's web pages) and *Acknowledgements ›*
  (`AcknowledgementsView`: FluidAudio, Kokoro, Phonon / Gradium, ONNX Runtime, ZIPFoundation,
  Mozilla Readability).
- **Developer** (developer options only): *Listen Debug*, *Fake Extraction Failure* (every
  extraction fails until the app quits: the browser's Reader and Save, Follow's preview and
  chapters, prepared audio) and *Listen Debug Panel ›*.

## Developer options

Debug tools are hidden in normal use: Settings › Developer (Listen debug, Fake extraction
failure, Listen Debug Panel), the listen bar's Debug pill / bake overlay, and long-press ▶︎ →
Listen debug panel. No ⋯ panel has a Debug row. The entry points that open the full panel
present the shell's `ShellSheet.listenDebug` (the Debug pill toggles the bake overlay): the one
sheet, or over Settings when it is up (`ShellState.overSheet`), which stays when it closes.
They show only with **developer options** on (`DeveloperSettings`, UserDefaults `reader.developerOptions`): off by
default in Release builds, on by default in Debug builds; turning them off turns off Fake
Extraction Failure and closes the bake overlay. To toggle in any build, long-press the
**version row** at the bottom of Settings for 2 s (haptic + "Developer options on/off"
confirmation). A Release build clears a stored "on" once, so a Debug pill left from an older build
can't stick; long-press the version row to turn it back on. A launch forces it with
`-reader.developerOptions NO|YES`. Launch-argument hooks and test-only markers compile only in
Debug builds (`App/LaunchOptions.swift`).

## iPad and regular width

The iPad (and any window whose `horizontalSizeClass` is `.regular`) gets its own layout; the
iPhone and compact widths keep the chrome host ("Bottom chrome"), unchanged. The
sizes are tokens in `Features/DesignSystem/Tokens/RegularLayout.swift`.

- **Sidebar** (`RegularShellSidebar`, ~280 pt, left of the main pane, hosted by `BrowseStartView`):
  the app name (one line, a little smaller rather than broken where the text is very large) and
  *Hide sidebar*; *Library* and *Browser* (the two surfaces; what the pill's
  Library and Browser do on a phone); *Search*; a *Folders* list (the top-level folders; a tap opens
  that folder in the Library); and *Settings* at the bottom. *Hide sidebar* collapses it for focus
  reading and a floating *Show sidebar* button brings it back; the collapse is not remembered
  across launches.
- **Main-pane chrome.** The address field is the top band of the main pane (`SurfaceBand`). In the Library the band shows only while a search is
  active. The toolbar (‹ › ＋ or 🔖, 🕘, ⋯) moves into the dock.
- **Clustered player dock** (`ClusteredPlayerDock`, ~520 pt, bottom of the main pane) replaces the
  phone's play button and carries the surface's toolbar beside it. It shows the playing
  article, or a resume bar for the last-played one, or "Nothing playing / Pick something to play".
  At the accessibility text sizes the toolbar takes a row of its own above the player.
  It steps aside under a sheet or Now Playing.
- **Reader.** The text sits in a ~700 pt readable column, centred, and the Reader's player
  controls are held to the dock's width.
- **Voice and Settings** open as form sheets (`.presentationSizing(.form)`, ~600 pt, drag indicator
  visible) instead of full-width sheets. Other sheets keep their phone presentation.
- **Not built.** A Browse | Reader split view (web page and Reader side by side) is deferred, and
  so is landscape-specific polish; the project sets the portrait orientation key and the
  screenshots are portrait.

## Current screens

| Screen | Button | Presentation |
|--------|--------|--------------|
| Browser (start page / web page) | — | root |
| Browser → editing the address | Cancel (text), right of the field | in place; tap outside or drag down |
| Browser ⋯ / Reader ⋯ / Now Playing ⋯ / Library ⋯ | — | morph panel over the button (same design; rows per surface) |
| ⋯ → Website (Reader, Now Playing) | no shortcut | leaves the Reader (the sheet closes on regular width, and the library) and shows / loads the page in the browser; audio continues |
| ⋯ → Settings (`SettingsView`); on iPad also the sidebar's Settings | Done | `.sheet` (a form sheet on iPad); Voice, Language, Speed, Appearance, Reading, Prepared Audio and Acknowledgements push inside it |
| Reader / Now Playing → Aa (`TextAppearanceControl`); Browser reader mode → Aa in the address field, or ⋯ → Text Appearance | tap outside | popover from Aa |
| ⋯ → Share | — | `.sheet` (system share sheet) |
| ⋯ → History (`BrowseHistoryView`) | Done (grabber) | `.sheet`, medium/large |
| Library (`LibrarySurface`): the home | the chrome's Browser (the sidebar's on iPad) | in-place surface (shared bottom chrome); leave restores browse |
| Library → a folder (a book or series too) (`FolderScreen`) | ‹ system | push (`navigationDestination`) |
| Move to…, Save to Folder… (`MoveTreeSheet`) | Cancel (grabber) | `.sheet`, medium/large |
| Import from… (Files picker, then `BookImportSheet`), an `.epub` link | Cancel (grabber, except while it works) | system picker, then `.sheet`, medium/large; *Add to* pushes inside it; D13 and refusals are alerts over it |
| Delete Folder…, Rename, New Folder | Cancel | confirmation dialog / alert |
| Edit Details (`FolderDetailsSheet`) | Cancel / Save | `.sheet`; the Photos and Files pickers over it |
| Follow (`FollowSheet`): ⋯ → *Follow…* | Cancel; OK opens the story's folder | `.fullScreenCover` (a card's own pull would take the preview's); a chapter's preview is a `Sheet` over it holding the chapter's article, pulled down to close (from its top) |
| Following (`FollowingSheet`): a story's status line | Done | `.sheet`, medium and large |
| Reader (`ReaderSheetScreen`), regular width: 📄, ⋯ → Reader, a Library row or card | *‹ Browser* / *‹ Library* pill, top left | `Sheet` over the surface, pull the header down (compact width reads in place: `ReaderSurface`) |
| Listen / Now Playing (`NowPlayingScreen`): the chrome's Listen, a reader's ▶ Listen, a Library row, the bar, the Reader of the playing article, crash resume | compact: none (pull down; VoiceOver: escape); regular: *⌄ <playing from>* pill, top left | compact: a `Sheet` that covers the screen and the chrome, pull down to close; regular: `Sheet` over everything, pull the header down |
| Listen debug panel | Done | `.sheet` (over Settings when opened from it) |
| Speed picker | — | popover |

The browser's own ‹ / › are web-history buttons (the web view also has its edge swipes), not screens.

**Item wording (C120).** Every item is an *article* in the UI ("3 articles"); in an imported EPUB's folder it is a *chapter* ("12 chapters"). An item is never called a "page" (Pages is only the Reader mode). Recent lists only started articles and chapters, never folders (C119).

## Retention and Prepared Audio (C134, C135, C136)

- **Three states.** *Prepared*: saved and you chose *Prepare Audio*; its audio is never cleared automatically. *Saved*: in the Library; listening renders audio as it goes, and saving or starring no longer renders the whole article. *Being read*: opened or played without saving, listed in Recent.
- **Recent is the last 50 articles started.** At launch and when an article starts, unsaved articles beyond those 50 are deleted with their audio; saved articles beyond them lose only their audio from listening. Audio the session or the staged chapter needs is never touched. The finished-chapters trim skips prepared audio.
- **Prepared Audio list** (⋯ › Prepared Audio, Settings): the prepared sections (Now, Waiting, Prepared, Different Voice) and **From Listening** (audio rendered while listening, no ↓, with a footer about Recent 50); every row names its voice (C138). Every row has *Delete Audio* (swipe and ⋯), which never deletes the article. The list's ⋯ (`MenuRegistry`, `.deleteAllPrepared`, `.clearListeningAudio`) has **Delete All…** ("Delete N articles and their prepared audio? This can't be undone.": deletes every prepared article and its audio, folders stay) and **Clear Audio From Listening…** (that audio only), each shown only when its section has rows.
- **Naming.** The feature is *Prepare*, in the UI and in code (`PrepareCenter`, `PrepareRecord`, `PreparedAudioSheet`, `Features/PreparedAudio`). *Download* stays only for real file downloads (voice models, the CPU model, EPUB files). On-disk names are kept: `Downloads.json`, its keys, `downloads.wordsPerSecond`.
