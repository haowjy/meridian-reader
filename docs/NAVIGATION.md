# Navigation rule

**If a screen shows ‹, you can swipe back from the left edge. If it shows ✕ (or is a sheet with a
grabber), you can pull it down.** Either gesture must do exactly what tapping the button does.

Listen on compact width slides up over everything (the chrome too) and follows the sheet rule
without a button: a grabber, and a pull down that closes it (VoiceOver: the escape gesture;
"Bottom chrome", below).
Regular width keeps the Reader and Listen sheets ("iPad and regular width").

| Button | Presentation | Gesture | Provided by |
|--------|--------------|---------|-------------|
| ‹ | real push in a `NavigationStack` (`NavigationLink` / `navigationDestination`) | left-edge swipe-back | UIKit, with the system back button |
| ✕ | modal: `.sheet`, or the design system's `Sheet` (Follow's chapter preview; the regular-width Reader and Listen) | swipe down | `.sheet` does it natively; `Sheet` implements it (see below) |

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
  its top: the Move tree, the import sheet (except while it works), Browsing History,
  Settings, Prepared Audio, Edit Details. Their *Done*, *Cancel*, *Save* and *Import* are one
  pill, the neutral one the Reader's close pill is (`SheetBarButton`).
- The design system's `Sheet` (Follow's chapter preview, and the Reader and Listen on regular width,
  in place, not a `.sheet` or `fullScreenCover`): pulling the header (grabber or the top bar) down calls
  the same close action as its button. Closing never stops audio.
- **The text pulls the sheet too, from its top**, so a sheet closes one-handed from the lower half
  of the screen (`SheetPullHandoff`). A drag on the text that begins with the text at its top and
  goes down moves the sheet instead of bouncing the text, which stays put; moving back up lowers
  the sheet first, then scrolls the text again. A drag that begins anywhere else in the text only
  scrolls, even once the text reaches its top: reading back up never closes the sheet. Sideways
  drags, text selection and ☝︎ taps are untouched, and the scrubber and the bottom row aren't
  text, so they never pull. In Listen a pull alone keeps following the audio (it moves
  nothing); once the drag moves the text, following stops as for any drag. In full screen the
  text hands no pull to the sheet: a pull down at its top only rubber-bands and brings the bars
  back, and a pull that begins with them showing closes the sheet as above. (Listen's full screen is
  left by the middle tap alone; an in-place reader's, which is the chrome's, by the tap or a scroll up of 24 pt.)
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
not a destination: it slides up over the chrome. The chrome has no ⋯: the Library's screens and
Settings have ⋯ on their title line, the reading pages (the Browser's reader mode, Library Read, Listen) in their
top group, and the Browser's menu is also a press and hold on its field's leading glyph. There is no system tab bar (invariant 13: `rg "TabView|UITabBar"` finds nothing).
Regular width keeps its own band and dock ("Two surfaces" and "iPad and regular width", below).

```
expanded    [‹ ›][ address / Search Library     ][🎧]     row 1: the screen's own, Listen at its end
            [ ▤ Library | 🌐 Browser | ⚙︎ Settings ]   row 2: where you are (glyph over name; glyphs alone when the names don't fit)
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

**Placement is measured from the safe area.** The bottom row ends on the home-indicator strip's top, as measured
(`ChromeHome`), not in it; on a phone whose strip is shallower than 18 pt (a Home button phone has none) it ends 18 pt
above the screen's edge, as the bubble does (`ChromeMetrics.rowLift`). The keyboard's row sits on the keyboard. The
bubble is the one piece placed from the screen's edge: 18 pt above it, inside the strip. What the chrome covers
above the safe area is `ChromeMetrics.clearance(step:home:)`: over a 34 pt strip 104 expanded (4 + 44 + 8 + 48), 48
one row (the keyboard's row too, over the keyboard), 24 the bubble (4 + 36 + 18 - 34); a view laid out to the
screen's edge (the web view) adds the strip: 138, 82, 58.

- **The bubble** (`ChromeLayout.bubble`, `ChromePieces.bubblePiece`, id `chromeBubble`): what the second fold step
  ends in, on every screen that folds (the Browser's page, the Library and its folders and books, Settings and
  its pages; never Library Read or the Browser's reader mode, which are expanded or full screen). Safari's minimized address bar: a **glass
  capsule** on the field's surface (`chromeSurface`, `BottomChrome.fieldFill`), 36 pt tall (`Control.small`),
  13 pt semibold ink (`TypeStyle.caption`'s size, fixed), 16 pt padding each side (`Spacing.m`), as wide as its text and
  padding, at most margin to margin, centred, its bottom 18 pt above the screen's edge (`bubbleClearance`, just over
  the home indicator). The hit area is its width and 44 pt tall (`bubbleHitOutset` 4 above and below). It names
  where you are: the page's domain on the Browser (no `www.`, no path), the screen's title in the Library,
  *Settings* in Settings
  (`ChromeScreen.bubbleTitle`). Audio keeps playing while folded; the bubble's tap and a scroll up bring both rows
  back. Sheets have no bubble. `-chromeFold P` (Debug) holds the fold at P wherever it may fold, to look at a step.

- **The pill** `[Library | Browser | Settings]`: 48 pt tall (`Control.tabBar`, the one piece not `Control.chrome`), three equal segments, a third of the pill each (117 pt on the
  SE's 375), each **its glyph over its name**, centred, as a tab bar
  (Library, Browser, Settings: the glyph 16 pt, `Glyph.small`, the name in `caption` semibold; ids `chromeLibrary`,
  `chromeBrowser`, `chromeSettings`), the lit one the screen you are on (an inset capsule, 4 pt on all four sides,
  40 tall, `pillLitHeight`, its glyph and name accent). The names show only when all three fit whole, across their segments and
  within the lit capsule's height; otherwise (large text from XXXL, a narrow phone, a smaller `Control.tabBar`)
  every segment is its glyph alone at the chrome glyph's 20 pt (`ViewThatFits`), never wrapped or clipped, and
  VoiceOver and the large content viewer keep the names.
- **Settings** (compact width) is a destination like the other two: its pill segment shows it in place under
  the same chrome (`ShellState.Surface.settings`, remembered for the next launch as `settings`), Library and
  Browser leave it, and it scrolls under the chrome and folds like the Library. Its title heads the list with ⋯ at
  the end of the line (Settings has no rows of its own, so the app-wide ones: Library, Browsing History, Listen). Row 1 is
  **Search Settings**, which filters the list as you type: a row shows when its title or its section's title
  contains the text, sections without a match go, and nothing matching says *No Results for "…"* (the
  Library search's view). Starting a search shows the list (a pushed page goes); the pages it pushes (Voice,
  Appearance, Prepared Audio, …) are `ShellState.settingsPath`, kept while another destination shows. Regular
  width keeps the Settings sheet (the sidebar's Settings); a Settings surface restored on regular width (or a
  window widened onto it) becomes the browser with the Settings sheet over it.
- **Listen** (`ChromeListenButton`, id `chromeListen`, VoiceOver *Listen*, value *Playing* while it plays): a
  44 pt glass circle ending row 1 on every screen, Library Read and the Browser's reader mode included. It shows
  the headphones, or the app's playing bars in the accent while something plays (still under Reduce Motion).
  A tap slides Listen up: on what is bound to playback; else the page played last (`LibraryQueries.lastPlayed`),
  bound paused at its saved place so ▶ resumes it there; else Listen's empty screen, *Nothing Playing*. It is not
  drawn while typing or in Library Edit (row 1 is then the field alone).
- **One shape system.** Every piece is a capsule or a circle (radius = height / 2). Two heights: **44 pt**
  (`Control.chrome`) for every piece in every row and state but the pill (fields, ‹ ›, Listen, Cancel, the
  keyboard's row, the reading pages' top group), on every screen, the same as a folder or book screen's system
  toolbar buttons; **48 pt** (`Control.tabBar`) for the pill (and Library Edit's actions in its place). They are
  the only values to change: every size, inset, hit area, footprint and clearance below derives from them
  (`ChromeMetrics`); the ▶ / ⏸
  floating over a page in full screen is not chrome and keeps `Control.bar` (48). Listen and
  the top group's ⋯ and Aa share one round glass face (`ChromeCircleFace`).
  **Concentric:** a 44 pt end holds a 24 pt glyph slot inset 10 (`endGlyphSlot`, `endInset`), so the slot's
  radius is the end cap's less the inset; a lit shape inside a piece is inset 4: the reader icon's
  circle 36 (`innerCircle`), the pill's lit segment 40 tall (`pillLitHeight`). **Every hit area is at least 44 pt** (`Control.tap`): at 44 the glass
  is the hit area; were `Control.chrome` or `Control.tabBar` below the tap floor, the hit shape would reach past the
  glass on every side (`hitOutset`, `pillHitOutset`; `ChromeHitShape`, `tapTarget(size)`), ‹ and › side by side reaching outward from their
  capsule's centre instead (`arrowHitSides`); with 8 pt gaps neighbouring hit areas never overlap. One 8 pt gap everywhere (`Spacing.xs`): between the rows and between
  neighbours on a row (‹ › and the field, the field and Listen, the field and Cancel). ‹ 44, ‹ › 88. Every control glyph is 20 pt medium (`Glyph.regular`, `BottomChrome.chromeGlyph`).
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
- **Row 1** is the screen's context: on the Browser `[‹ ›][address]` (as Safari: ‹ always, dimmed to 35%
  and disabled but in place with nowhere to go back; › beside it only while there is somewhere to go forward), on the
  Library its search field, in Library Read `[‹][(lit reader icon) site]` (the lit reader icon where the Browser's reader mode has it, the site taking the rest of the field, no ↻; a tap on the icon opens the article's live page in the Browser and a press and hold opens the top group's ⋯ menu; a page with no web address has none to open, so there a tap opens that menu and VoiceOver calls the icon *More*); Listen ends it. › after ‹ re-enters the reader view when ‹ left it (`ShellState.readerLeftByBack`, `readerOnLoad`). The Browser's reader mode is kept while another destination shows (`ShellState.pageReader`): back on the Browser it is as you left it, the reader view at its place or the web page.
  The address field is `[reader icon][URL][↻]` (↻ is ✕ while the page loads). ↻ never gives way: a 44 pt control
  (`Control.chrome`, `tapTarget`), its glyph in the chrome ink at the chrome glyph weight
  and size, centred on the capsule's end radius; the URL truncates and the reader icon gives way below
  about 150 pt (`ChromeMetrics.readerIconWidth`). There is no 🎧 in it on compact width: Listen
  is the round button after the field. While the page shows as its reader view the field is
  `[lit reader icon][URL][↻]`, the page alone: Aa is in the reading page's top group, not the field.
- **Row 2** is the pill alone, margin to margin; it never moves or resizes across destinations and states. There is no play / pause in the chrome: Listen, the row's tap in
  the Library and the reading pages' ▶ Listen start and control playback.
- **The reading pages' top group** (`ReadingTopGroup`, the same component on all three): on the Browser's
  reader mode and Library Read `( Aa ) ( ▶ Listen ) … ( 🔖 ) ( ⋯ )` floating at the top of the page; on Listen
  `( Aa ) … ( 🔖 ) ( ⋯ )` at the sheet's top corners, the grabber between them. VoiceOver reads them as they sit:
  Aa, ▶ Listen, 🔖, ⋯. ⋯ (`readerMore`; Listen's `listenMore`) is a glass circle at the trailing
  edge, where every other screen has its ⋯ (the Library's and Settings' title line, a folder's toolbar), the screen's menu as a system menu: in the Browser what a press and hold on the field's reader icon opens,
  in Library Read the Library's screen menu (what the Library's title line ⋯ has), in Listen *Play from a
  Paragraph* then the page's rows at `nowPlaying`. Aa (`readerAppearance`, VoiceOver *Text Appearance*) is a glass
  circle at the leading end that opens the text appearance panel, a popover pointing at it, Aa lit while it is open.
  **🔖** (`readerSave`; Listen's `nowPlayingBookmark`) is Save on the same glass circle as Aa and ⋯, just before ⋯
  (`SaveToggleButton`, chrome face): a tap saves the page or removes it, held it opens *Save to Folder…*, and while
  the page is saved its filled symbol is in the accent. It is the page's one save (`ArticleActions`, the save path
  its menu's *Save to Library* takes): the Browser's reader mode extracts and saves the page; Library Read's page is
  saved, so it shows filled, and a tap asks first (*Remove from Library?*, a confirmation dialog; every saved 🔖
  does) before removing it from the Library (its audio and spot stay; if you hear it, playback stops). It dims where it can't apply: a page with no text to save, Listen with no article
  text. **▶ Listen** (`inPlaceListen`), the page's primary action, is an accent-filled capsule just after Aa (tinted
  glass; the accent on the material skin), the chrome's glyph and its worded pieces' type (`row`, semibold, at most
  XXXL), `Spacing.m` each side: it plays the page from its saved spot and slides Listen up. It never goes while
  the page has text: once the page is what you hear (bound, playing or paused) the same capsule in the same place
  shows the live state, the playing bars and *Listen* while it plays, ▶ and *Listen* while paused, and its tap only
  slides Listen up, never restarting or moving playback (VoiceOver *Open Listen*). It is not drawn while the page
  has no text to read, so in place the row is `( Aa ) ( Listen ) … ( 🔖 ) ( ⋯ )`. Sizes: every piece 44 pt (`Control.chrome`, the bottom chrome's pieces: its circles are Listen's), as tall
  as a folder screen's system toolbar buttons, 8 pt between Aa
  and ▶ Listen and between 🔖 and ⋯, `Spacing.topBarMargin` (16) from the screen's edges, in place and in Listen alike, `Spacing.xs` below the row. It is the
  page's header, so at rest the title starts on its own line below it; the text scrolls under it. In place it
  sits on the safe area's top and 16 pt in from the screen's edges (`Spacing.topBarMargin`), where a navigation bar's buttons sit (a book's or folder's `‹ … Edit ⋯`), so both rows line up. In Listen it is the sheet's top row, as Voice Memos' is: the grabber
  (36 × 5) 8 pt below the sheet's top edge, centred; Aa and ⋯ with their tops 16 pt below that edge (centres
  16 pt + half of `Control.chrome`) and 12 pt in from its sides, inside its rounded corners; the title starts 8 pt below the circles, so the
  header is 16 pt + `Control.chrome` + 8 pt. It is the page's header, so it goes in full screen and comes back
  with it; in place that is the chrome's full screen, so the group, the bottom chrome and the status bar go and
  come back together, on the same curves (under Reduce Motion they fade out and in together). VoiceOver: ⋯, Aa,
  ▶ Listen, in that order.
- **Collapse follows the finger down, in steps; a scroll up brings it back at once.** One progress value
  (`ChromeScroll`), 0 two rows, 0.5 one row, 1 the bubble: `progress += dy / 120` for a scroll down (60 pt a
  step), ignored while the keyboard or the ⋯ panel is up, and 150 ms after the finger stops a part-way step
  settles forward to its end (`ChromeScroll.stepEnd`: 0, 0.5 or 1). **A scroll up of 24 pt with no scroll down
  between (`ChromeScroll.revealDistance`) brings both rows back, as Safari does, on every screen that folds.**
  The rows also come back by a tap on the bubble, by reaching the top of the content (offset <= 4, which resets
  progress to 0) (invariant 12), and by what is not a scroll: a new page or screen loading, opening the address
  or search field, VoiceOver being on. The Library, the Browser's page and Settings feed it; **Listen does not**
  (it has no chrome), the Browser's start page does not fold, and **an in-place reader never folds** (below).
  **Only the screen showing drives the chrome** (`ChromeSource`, `ShellState.chromeOwner`): the web page under
  the reader mode, the Library under Library Read and anything under Listen or a sheet (Voice, Share, Follow,
  History, the Files picker, …) move nothing, and after Listen or a sheet closes, the next scroll only sets where
  the following one is measured from. A browser page that loads under another destination, Listen or a sheet
  leaves the chrome showing alone; the Browser comes back expanded on its new page.
- **An in-place reader is expanded or full screen, nothing between** (`ChromePolicy.reads`). In Scroll mode
  **60 pt of scrolling down in one gesture** (`ChromeScroll.fullScreenDistance`, the moment a page's row 2 goes;
  about two and a half lines, so adjusting a line or two never hides anything) enters full screen: the top group,
  the bottom chrome and the status bar go together, exactly as the middle tap does. **A scroll up of 24 pt brings
  them all back, however full screen began** (a scroll or the tap), and so does the middle tap. After a reveal,
  hiding again takes a fresh 60 pt down. The top of the text doesn't reveal on its own (a scroll up to it does), and
  the rebound from a pull past the top never counts as a scroll down, while the pull itself counts as a scroll up.
  Only a finger counts: a move of the text by the app (following, a restore, a reflow, a jump, the end gliding to a
  new end) never toggles it. Pages mode and VoiceOver: the middle tap alone (VoiceOver keeps the bars).
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
  above the glass instead of under it. The inset follows the drawn step (`ChromeScroll.drawnStep`): 138 pt two rows,
  82 one row (and the keyboard's row while a search is open), 58 the bubble, each at least the home-indicator
  inset (the web view extends under it, so its own inset reads 0). The Library's lists and the readers keep one
  constant inset (138, less the home inset above the safe area). The switch happens **once per step**, not per
  frame: the page's fixed elements jump at each step's midpoint while the glass folds, and the page text reflows once, instead of the
  whole page re-laying out on every frame of the fold. The scroll offset does not move (the scroll view's
  `contentInset` stays constant; only the web layout inset changes). Content still scrolls under the glass.
  Limits: legacy `100vh` is always the full frame in WebKit and follows neither inset, so a `100vh` hero extends
  under the chrome (as in Safari with its bar up); iOS before 26 keeps the constant content inset only (no obscured
  inset); the in-place Reader is SwiftUI, not a web view, and has its own bottom inset; iPad regular layout is
  untouched. Fixture: `reader-test://pages/popup`, `testAFixedBottomPopupSitsAboveTheChrome`.
- **Listen slides up over everything** (`NowPlayingScreen`, `ReadingShowing.cover`, a `Sheet` that covers):
  from the bottom, over the chrome, to just under the status bar, the screen behind dimmed above its rounded top, as Apple Music's player. At its
  top a handle: the top group's row (above), 64 pt tall across the sheet in the page's colour, `( Aa )` and `( 🔖 ) ( ⋯ )` in
  its corners and the grabber centred between them, 8 pt below the sheet's top edge; the text starts below it and
  scrolls out of sight under it; there is no close button. The
  article's title is the first thing in its text, right below that row. A pull down anywhere on that row (a tap on
  ⋯ or Aa is the button; a drag that starts on one pulls), on the dimmed strip just above it, on the top 48 pt of the text below it
  (unseen: a tap or a drag up there is still the text's), or on the player card, whatever the text's scroll position (a
  drag that starts higher, in the status bar, is the system's) (a UIKit pan, `SheetPullPan`, so a drag that starts on a control pulls too; the scrubber keeps its drag), or on the text when it is at its top, follows the finger and closes it when let go far enough or
  flung while still heading down, and springs back otherwise; VoiceOver's escape gesture closes it too. Closing shows exactly what was under it: the surface,
  its scroll, a reader in place and its fold or full screen, a search (its keyboard lowered when Listen
  opened). Audio keeps playing. At the foot a glass player card at the chrome's margins (`Radius.surface` 24),
  as tall as its rows, floating over the text, which runs on under it to the screen's foot (`ReaderPlayerCard`); the
  end of the text scrolls to just above the card. No artwork and no divider: its
  groups are set apart by space alone.

  ```
  Title of the article, one line, the card's width…
  example.com                         6 min left
  ━━━━━━━━━━━━━━━━●──────────────────────────────
  Voice    ⏮        (  ▶  )        ⏭          1×
  ```

  Row 1: the title alone on one line, the card's full width (cut with …); Save is the top group's 🔖. The title
  opens the article's own place in the Library or its page, and never seeks; only the track does.
  Row 2, one text step smaller: the site at the left (it truncates) and the time left at the right; the
  page's status note (preparing, voice and language notes) or "Finished" alone in its place. Then the
  full-width scrubber, no times. Under it one row, no labels: Voice (VoiceOver: "Voice", never a voice's name) at the card's
  left margin, the speed (1×) at its right (it changes more often, so it sits under the thumb); between them ⏮, a 62 pt ▶ / ⏸ and ⏭
  (`NowPlayingTransport`'s `card` size), centred. Aa and ⋯ are the top group's. **Jump to Audio** is not in the card: scrolled away from the audio, a thin accent pill,
  "↑ Jump to Audio" or "↓ Jump to Audio" in the pills' type, 8 pt above and below (an `OverTextPill`; the same on regular width;
  its tap area 44 pt), floats in the middle 12 pt above the card (above
  the home indicator's strip in full screen) and brings the text back to the spoken sentence; while the text follows the audio, or once the article has finished, it isn't there.
  The top group's ⋯ (`listenMore`) is a system menu, a section per
  group: *Play from a Paragraph*; *Go to <folder or Library>*, *Save to Folder…*,
  *Mark as Finished*; *Share* (`MenuRegistry`'s `nowPlaying` place). There is no sleep timer. **Full screen** is a tap in the middle of the text, in and out: the
  card slides off, the status bar hides and Listen stops being a sheet: the gap at its top, its rounded
  corners and the dim above it go (`Motion.standard`), and the page covers the screen, its text from the
  status bar's foot to the screen's, where its end now scrolls; a ▶ / ⏸ (and *Jump to Audio*, when the text is away) floats for as long as full screen lasts; neither fades on its own. The text on
  screen doesn't move in or out. A pull does nothing to the sheet there (the text only rubber-bands);
  the middle tap leaves it, as in the in-place readers. It is Listen's own: the chrome
  underneath keeps its state. Voice, Save to Folder, ⋯ and the debug panel open over Listen and return to it.
- **Listen with nothing to play** (nothing bound and nothing played before): the same cover, its grabber and
  pull down, with *Nothing Playing*, "Choose an article or book to listen to." and the five tiles every empty
  screen has (`AddToLibraryTiles`, below), each closing Listen first. A pull from
  anywhere on it closes it. Listen that loses what it showed (the page removed from the Library) closes
  instead.
- **Starting something new** (compact width): a Library row's tap plays the article or chapter and slides
  Listen up (a followed story's chapter still waiting for its text plays once it is in, and Listen stays
  down); a reader's ▶ Listen does the same; a page shared from Safari opens in the Browser straight in
  reader view (once it has loaded and if it is readable; else the page itself), its ▶ Listen in the top group
  there; *Paste Text…* saves, then opens the new article in Library Read; *Import from…* and a shared book
  file close the import sheet on the new book's screen.
- **Reader mode on the Browser replaces the page in place** (like Safari Reader,
  `ReaderSurface`): the chrome never folds; it is expanded or full screen (a deliberate scroll down in Scroll
  mode or the middle tap; a scroll up of 24 pt or the tap brings it back, above), the address keeps the
  URL, the reader icon sits in a lit capsule and toggles back. The
  text is a reading page like the Reader's (`ReadingPage`, in place): Pages or Scroll as the
  Appearance setting says, the footer, full screen, *Play from Here* on a
  selection, and it opens at the page's saved listening spot, underlined. The reader's theme runs up
  under the status bar. Under the title the source line reads "site  length" (a long site gives way
  first, an ellipsis). Over the top of the page floats the top group, `( Aa ) ( ▶ Listen ) … ( 🔖 ) ( ⋯ )` (above):
  the title starts below it, and in Pages the card (the overview) is centred between it and the chrome. ▶ Listen
  plays the page from its saved spot and slides Listen up; once this page is what you hear it shows the playing
  bars or ▶ and only slides Listen up. It is not drawn while the page has no text to read. The
  reader stays a plain reader while its page plays: no spoken paragraph, underlined sentence, following
  or Jump to Audio (the playhead is Listen's), and no saved-spot underline (a page that isn't playing
  keeps its saved spot underlined); *Play from Here* moves the playhead and slides Listen up. The end of the text scrolls to just above the
  chrome's two rows. Full screen is the text alone, down to the screen's foot, where its end then scrolls: no floating
  ▶ / ⏸ (that is Listen's and the regular-width sheets'). While another layer covers the reader it stays mounted and quiet: no status bar change, and its scroll moves no chrome (it isn't the screen showing); closed back to, it is as it was, full screen included. The web page
  under the reader takes no touches and is hidden from VoiceOver; a swipe from the left edge does
  what ‹ does (back, which closes the reader).
- **Library Read replaces the Library in place** (same `ReaderSurface`, `ShellState.libraryReader`):
  a row's ⋯ → Read shows the article's text over the Library, which stays the lit segment and under it
  with its scroll; the chrome is expanded or full screen as in the Browser's reader mode (never folded), ‹ (`libraryReaderBack`)
  or a left-edge swipe closes it, and there is no player card. Row 1 is `[‹][(lit reader icon) site][Listen]`, laid out as the
  Browser's reader mode (the icon's tap opens the live page in the Browser). The top group is the Browser
  reader mode's, its ⋯ the Library's screen menu; its ▶ Listen starts the page. Nothing plays until then. Opening a saved page anywhere else on compact width
  (Prepared Audio's rows) opens it here too. At regular width Read keeps opening the sheet.
  A search in the Library ends when Read opens, so the chrome shows the reader's row and not the keyboard form.
- **⋯ is not in the chrome.** Each screen's menu keeps its rows and their order (`MenuContext`) and is a
  system menu (`MenuRows`, `TitleMenuButton`), the panel's big buttons as its last section:
  - the Library home: ⋯ at the end of the title's line (`libraryMore`); a folder's screen: ⋯ beside Edit in its
    navigation bar; Library Read: the top group's ⋯ (and a press and hold on the field's reader icon), the page's
    menu first (its *Save to Library* / *Remove from Library*, *Save to Folder…* / *Move to…* and *Follow…* group
    leading), then the Library's. The Library's menu adds *New Folder…*,
    *Import from…* and *Paste Text…* to its screen's rows, and *Browsing History* is among its last rows. *Paste
    Text…*'s *Save* opens the new article in Library Read.
  - Settings: ⋯ at the end of its title's line (`settingsMore`).
  - Listen: the top group's ⋯ (`listenMore`, above).
  - the Browser (page, start page, reader mode): a press and hold on the field's leading glyph (the reader
    icon, or 🔍 where there is none, `addressMenu`); a tap on the reader icon still toggles reader mode. In
    reader mode the top group's ⋯ opens the same menu.
    Its rows: *Open in Reader* (or *Show Web Page*), *Listen* (Listen over the page you hear; another readable
    page is extracted and plays, and Listen rises once it starts), then the page's menu (*Save to Library*,
    *Save to Folder…*, *Follow…* first) and the screen's rows regular width's ⋯ shows (*Reload*, …), then
    *Library* and *Browsing History*.
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
| 4 | 🕘 Browsing History | 🕘 Browsing History |
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
  Move tree (*Save to Folder…*). Dimmed on the start page. **🕘** (slot 4; on compact width a row of ⋯) opens Browsing History: the
  pages visited, newest first, as Library rows (the site under a titled visit, none under an
  untitled one, whose title line is already its site; then how long ago). A tap loads it; its ⋯
  and long press are the article's menu ("Menus", below; on the Library's article for the address when
  it has one), then *Remove from Browsing History*. Empty, it says *No Browsing History Yet*, "Pages you open show up here.", over the five tiles every empty screen has; each closes it first (*Browse the Web* to the Browser).
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
  replaces it while the article is extracted); on the article that is playing it opens Listen.
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
  the article's own menu (the same rows as everywhere the article's menu shows: "Menus", below; its
  *Save to Library*, *Save to Folder…* and *Follow…* first), then *Reload, Prepared Audio, Settings*,
  then a row of big buttons **Library**, **Browsing History**, and **Reader** (rightmost, nearest the
  thumb, like Safari's All Tabs). The page's *Save to Library* and *Save to Folder…* extract it first.
  *Follow…* reads the story the article belongs to ("Follow a story", below). On the start page there
  is no page, so no page rows; *Reload* and the Reader toggle show dimmed; the Reader toggle is dimmed on pages that
  aren't readable too, and on a readable page tapping it switches into reader mode. Actions that present something (Share, Settings, Browsing History, the Move tree)
  run after the panel has closed.
- **The ⋯ panel** (`MorphMenuOverlay`: one overlay for the browser toolbar ⋯, the library
  toolbar ⋯, the Reader's ⋯ and regular width's Listen ⋯; its rows come from the surface that opened it,
  `MenuContext`: the item's menu, the screen's rows, the big buttons) is not a popover: it is placed so the bottom-right button's icon (Reader,
  or Website in the Reader and Listen — marked with `morphMenuFocus`) sits slightly up and to
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
- **One saved state**: the browser's 🔖 and ⋯, the Reader and Listen all read "is this page
  saved?" from the article for its address, else its key (`ArticleActions`, `ArticleLookup`), the article
  Save saves into and *Remove from Library* removes, and they follow a change made anywhere at
  once.
- **One library**: everything is an article in a folder (or in none). An article is a *link* (an address
  you kept, such as an address saved from a website: no text or audio), *saved* (text and audio kept), or played
  without saving (kept while in the last 50 of History, listed in the Library's History tab, and in the bar). *Remove from Library* is one action wherever it is asked (a row's swipe or menu,
  Edit, 🔖, the ⋯ of the browser, the Reader and Listen, the Now Playing bar's long-press):
  the article leaves its folder and every Library list it was in, History too; if it is what you hear, playback stops, as for
  *Stop Listening*, and Listen closes. It is kept while it is in the last 50 of History (C134) (an article never
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
  reading ◉ Finished, and ▶ plays the article again. Tap or swipe up → Listen; long-press →
  the article's menu ("Menus", below; its *Remove from Library* stops the article you hear, as
  anywhere else), then *Stop Listening* (unloads the article). It hides on Listen, under other
  sheets and once nothing is loaded. Elsewhere on compact width the chrome's Listen does its job,
  and on regular width the clustered dock does.

**Start page** (no page loaded), Safari-style:
1. **Frequently Visited**: the sites you visit most, from Browsing History (no tracking of
   its own): it keeps one visit per page, the last 30, so a site counts its pages there, the
   most first, then the most recently visited. One tile per site (`www.` folded in): its icon (the
   newest visit's that fills a tile, else the letter tile) and its host below. 4 per row, up to 8
   (at the accessibility sizes one per row, the host beside its tile).
   While fewer than 4 sites are in Browsing History, starter tiles fill the first row: *Wikipedia*,
   *Standard Ebooks*, *Project Gutenberg* (letter tiles). A tile opens the site's home page in
   Browse; it has no long-press menu. Show All opens Browsing History (`FrequentlyVisited`).
2. **Recent Searches** (local, newest first, *Clear All*; each a 🔍 row, as in the search layer).

## The Library

The Library is a stack of screens in a `NavigationStack` (`LibrarySurface`, the path is
`ShellState.libraryPath`): the home, then folder → folder at any depth. ‹ and the edge swipe go
back up, as does the regular-width dock's ‹ (dimmed at the home). The home's title line is *Library* with ⋯ at
its end on compact width (a glass circle, the reading pages' ⋯; Settings' title line has the same), then **Library / History** tabs, the system's segmented control at 44 pt (`SegmentedTabs`) (C104; History is the `recent` case,
stored as `history`, once labelled Recent); the bottom field searches the tab on screen and says so (*Search Library* on
Library, *Search History*). On a folder's screen it searches that folder,
everything under it, and says so (*Search Demo Finance*): the results stand under the folder's
name, each row showing where it is below the folder (its site when it is in the folder itself);
the search ends when you leave the folder. Each tab
is one mixed list: folders and pages share a single list, with no section headings. The History tab is everything you opened or started (C104); the browser's
*Browsing History* (🕘 on regular width, a row of the compact menus) is its pages visited. From the
Library, 🕘 opens Browsing History over the Library, which stays under it (C130). A row under a minute says *<1 min* (C131). The Now Playing bar's line two names the article's folder when it is in one, as History does (C130). In an imported EPUB or followed story ＋ shows as in any folder (C149); a folder header's More ends with *Delete Folder…* (*Delete Book…* on a book) alone at the bottom, after the create group. On
History and in search results a row in a folder shows that folder's
path in place of its site, and a folder opens in its place, under its parents, so ‹ goes to its
parent. Going to a place in the Library (Listen's ⋯ → *Go to …*, the title on Listen's card,
an imported book) opens it on Library, where every place shows; Library
comes back to the tab you left. Either way a page open in Library Read closes first, so the place
asked for shows. The tab is remembered with the surface. On compact width the chrome's row 1 is the search
field and the title line's ⋯ holds the creating rows, with *Browsing History* among its last rows ("Bottom chrome", above); on regular width the
band and dock are the browser's: the search field and `[‹][›][＋][🕘][⋯]`. ＋ is the ⋯ panel's two creating rows, *New Folder…*
(*New Folder…* in a folder) and *Import from…*, both made in the folder on screen (a book's too). Browser shows the browser as
it was; Library there comes back to the same folder. The
⋯ panel follows the screen on top (below): a folder's screen starts with the folder's own menu,
then every screen has *Sort ›, New Folder…**, Import from…,
Follow…, Prepared Audio, Settings*, and the big buttons **Library**, **Browsing History**, **Browser**; nothing in it acts on the page under the Library. Browsing History closes the Library first; Browser is the same
as the chrome's Browser.

```
Library                                ⋯   ⋯ on compact width: New Folder…, Import from…, Paste Text…, Add Link…, Sort, …
Library  History
▣ Pride and Prejudice              ⋯   tap opens; its cover never changes (C102)
▣ Tide Tables                      ⋯
▣ Finance                          ⋯
[i] Seven-Day Yield                ⋯   tap plays; ◜ the spinning arc queued, the ring filling, then ●↓ before its second line
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
  ("opened" is started: `lastPlayedAt`), saved, prepared or played without saving (articles only,
  a book's chapters and link pages too; no folders), most recent first, in the same rows; a tap plays one. An unsaved one's ⋯ (and
  long-press) has *Save to Library*, which moves the article into the Library (it stays in History), *Save to Folder…*, and *Remove from History* (the same remove as *Remove from
  Library*: in no list after, pruned later), *Prepare Audio* (which saves it first, C104), and the marks dimmed until it is saved; swipe left is *Remove from History*. *Remove from History* never shows on an article in the
  Library (a saved article in History has *Remove from Library*), and is dimmed on one out of it that
  isn't in History. Every empty screen looks the same (`EmptyState`): a heading, one line under it, and
  its ways in as tiles (`ActionTile`, laid out by `ActionTileGrid`), two to a row at one size, the
  same height, a symbol over a label and only as tall as they need (85 pt at the default size), then one
  across the full width, a row with its symbol beside its label, a one-line row's height (48 pt; at the
  accessibility text sizes every tile is such a row, stacked, the full-width one still last), the first
  accent-tinted. It is centred in what is visible between the rows above it (a title and tabs, a folder's
  header) and the top of the chrome; at the default text size it fits there with the chrome expanded, and
  scrolls only at the larger sizes or in a half-height sheet on a small phone (*Nothing Prepared*,
  *No Browsing History Yet*), until the sheet is pulled up. An empty Library says
  *Start Your Library*, "Save from the web, a file, text or a link, or follow a site.", over five tiles, the
  same on every empty screen (`AddToLibraryTiles`; a folder's go into the folder, every other's into the top
  level): *Browse the Web* (the Browser) and *Follow a Site* (the Follow sheet asking for a story's address,
  into the top level even from a folder), *Import a File* (as *Import from…*) and *Paste Text* (as *Paste Text…*),
  then *Add a Link* (as *Add Link…*) across the full width, each closing what is over the screen first (a sheet, Listen) and landing
  where its result shows (the Browser, the Follow sheet, or the Library with the picker, editor or address field up); History says *No History*, "Articles you listen to show up here.",
  over the same five. It keeps the last 50 started (`LibraryStore.recentLimit`); one played without saving
  also leaves after 7 days unplayed (`pruneUnsaved`). Search with no match is the system's search view.
  Search filters the tab on screen: on
  Everything the Library's folders and pages across the tree, on
  History its pages; folders by name, then pages by title (the newest first among equal
  titles); a result keeps its location and shows the path (one at the top level keeps its own second
  line). Rows are the compact two-line
  rows (below): an article row plays on a tap, a folder row opens, and each has only ⋯. On regular width the
  bar's ▶ resumes what you last heard (compact width has Listen instead), and a folder row's ⋯ ›
  *Continue* resumes its own pages without opening it (D14). The home has no navigation bar; rows scrolled up pass under a paper
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
  the top of its screen's ⋯ ("Menus", below). **Prepare Audio** is the folder's Prepare toggle (F7), drawn as every download in the app is
  (`DownloadMark`, the App Store's look): ◯↓ while it isn't prepared; the spinning accent arc while
  it waits its turn; a thin accent ring filling clockwise as it prepares (no ■: a tap then opens
  the Prepared Audio list), the same ring grey and still while its prepare is paused; ●↓ once
  every article its prepare covers is. Its caption says *Prepare Audio*,
  *Preparing*, *Paused* or *Prepared*, and VoiceOver
  reads whether the toggle is on and the percent. Tapping ↓ turns the toggle on (or keeps it on):
  every article in it prepared audio and so does every article added to it later (Follow's new chapters, a
  article filed in). Tapping it while it prepared audio or is prepared, with the toggle on, asks *Turn
  Off Prepare* ("Prepared audio stays. New pages won’t prepare."), shown by the control (a
  popover pointing at it); asked from a menu (*More*, a folder row's ⋯ or long press, the screen's
  ⋯), the same question points at the button that opened the menu. Off, nothing new prepared audio
  and what is prepared stays. Prepared with the toggle off, a tap turns it on again and
  nothing is prepared again: it stays ✓ and a toast says new pages will prepare. *More*'s
  *Prepare / Stop Preparing* row is the same toggle, its face whether the toggle is on, so
  *Stop Preparing Audio* is there (asking the same) even while the control shows ↓ with the toggle
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
  here from the Reader's 🔖* (the toolbar's symbol), over the same five tiles as the Library's (they
  add into the folder, except *Follow a Site*, whose story's folder goes at the Library's top level).
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

**Follow a story**: *Follow…* in a page's menu (the browser's, a reading page's ⋯, a row's) on a
story's page (a Royal Road chapter leads to its story article), or the Library's ⋯ → *Follow…* (the home, or a folder, which the story's folder
goes in), where you type or paste the story's address. Follow covers the screen:

1. *Finding the chapters…* with the spinning download arc and the address: one request, signed in as in the
   browser. A page with no list of chapters, or a site that refuses, says so, with *Try Again*
   and *Edit Address*; a story followed already offers *Open Folder*.
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
set apart by space (never a separator), in secondary ink: *41 of 107 downloaded* (the Following
sheet's words) with the download ring filling after it (`DownloadMark`; the spinning arc while it
checks for new chapters), or *checked today 8:02 AM   2 new*. While chapters couldn't be had this
launch, their count comes right after *Following*: *📡 Following   1 chapter couldn’t load
41 of 107 downloaded*; a line too long for the screen wraps rather than losing its end. While its site
is backed off, a notice in the caution colour names the chapter that waits by its title (*the
next chapter* when it has none): *Royal Road asked to slow down. Trying “Chapter 42: Low Tide” again in 1:52,
more slowly.*, or *Example.com isn’t answering. Trying “Chapter 42: Low Tide” again in 1:52.* A
chapter waiting for its text shows the spinning download arc before its second line, which says
*Downloading…*, *Trying again in 1:52* or *Waiting* (no arc, only why, once it couldn't be had) (it is tried again at the next launch); tapping it fetches it next and then plays it.
Playing through the story stops before a chapter still waiting for its text, and the chapter
after the one playing is always fetched first. *Skip When Playing* on a chapter that can't be had
lets playback go past it.

Tapping the line opens **Following**: where it is read from, *Last Checked*, *Next Check*,
*Chapters* ("109 of 109 downloaded", "107 of 109 downloaded, 2 chapters couldn’t load", the download
ring after it while chapters are fetched), *Last
New Chapters* ("today 8:02 AM, 2 added"), **Check Now** (↻, the spinning download arc while it reads; a failed check says why) and
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
(line two "6 min left"; the only rings in this column are listening: a download's ring sits before line two), the same ring full once finished
(line two "Finished"; no ✓), and still or moving accent bars while it plays or is paused (the row
tinted, "Playing" or "Paused" in the accent); every time at the playback speed.

The row's only control is **⋯** at its trailing edge, its glyph ending where the card's text and
every row's trailing mark do (`RowMetrics`); a long press opens the same menu (the item's one menu, "Menus" below; decision
D11), and a long press that moves lifts the row into a drag (below). **Tapping an article
row plays it** (replacing what plays; in a folder it carries on through the folder) and, on compact
width, slides Listen up over the Library, except the
article you hear, which opens Listen (a stray tap never pauses); a link page (*Add Link…*'s,
a story's chapter waiting for its text) is fetched first, its row showing the download arc and saying *Downloading…* (or why it
couldn't be had), then plays, Listen staying down; a skipped page plays when tapped. *Read*, the first row after the
menu's save group, opens it (the Reader; Listen for the page you hear; the browser for a link). **Tapping a folder
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
story's stop playback until their text is in), and so are pages marked *Skip When Playing*. The page that last played is the folder's place: its
row shows the place and the time left and *Continue* resumes there, as a book's does; before
anything in it has played, the first article starts where it was left. Listen's "Playing
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
| Saved article (including a chapter) | plays it (Listen if it's what you hear) | *Remove from Library* |
| History article (played without saving) | plays it (Listen if it's what you hear) | *Remove from History* |
| Link page | fetches its text, then plays it (Listen if it's what you hear; ⋯ *Read* opens it in the browser) | *Remove from Library* |

### Menus

**Which options each menu has, in what order, and when each is greyed or hidden is `MenuRegistry` (C98, C99); docs/MENUS.md lists them with the generated table. Where this section names a different set of rows, MENUS.md wins.**

An item has one menu wherever it shows (decision C4): an article's (`ArticleMenu`), a folder's
(`FolderMenu`, books and series too) and a prepare's (`PrepareMenu`). The same rows, in the same
order, with the same names and symbols, in a row's ⋯ and its long press, a
Browsing History visit, the Now Playing bar's long press, a folder header's *More* and the top of every ⋯
panel that is about one item (the browser's page, the Reader's, Listen's, a folder's screen).
A place only hides a row that can never apply there or dims one that can't run now (DR-09); what
a place adds of its own comes after, set apart by a divider (the ⋯ panel's screen rows and big
buttons, the bar's *Stop Listening*, Browsing History's *Remove from Browsing History*). Rows that delete something
are red everywhere.

| An article's menu | Where it shows |
|---|---|
| *Save to Library* / *Remove from Library* (red) | first, everywhere, with the next two as one group; *Save to Library* dimmed without text to save. The reading pages keep their 🔖 too |
| *Save to Folder…* / *Move to…* | *Save to Folder…* out of the Library (the Move tree, titled *Save to Folder*, saves it there), *Move to…* in it |
| *Follow…* | an article with a web address (one that can belong to a story); dimmed while the page is being extracted. It opens Follow on its address ("Follow a story", below) |
| *Read* / *Go to <place>* | *Read* (the Reader; Listen for the page you hear; the browser for a link or an address the Library hasn't) where the page isn't open; Listen has *Go to* its folder or the Library in its place; neither on the Reader or the browser |
| *Play from Here* | an article in a folder, in a Library list |
| *Prepare Audio* / *Remove Prepared Audio* (red) | a page out of the Library is saved first (C104); dimmed only on a browser page not yet loaded as a page |
| *Mark as Finished* / *Mark as Unfinished* | dimmed until it is saved |
| *Mark All Above as Finished* | an article in a folder, in a Library list |
| *Skip When Playing* / *Don’t Skip* | an article in a folder |
| *Share* | an article with a web address |
| *Select* | a folder screen's rows (Edit with that row selected) |
| *Remove from History* (red) | an article out of the Library; dimmed while it isn't in History |

| A folder's menu | Where it shows |
|---|---|
| *Continue*, *Play from Start* | dimmed while none of its pages play |
| *Prepare Audio* / *Stop Preparing Audio* | its Prepare toggle; *Prepare Audio* dimmed without pages, *Stop Preparing Audio* asks first |
| *Remove Prepared Audio* (red) | dimmed while nothing in it is prepared or preparing |
| *Move to…* | |
| *Rename…*, *Edit Details…* | |
| *Select* | a folder screen's rows |
| *Delete Folder…* / *Delete Folder…* (red) | asks first |

A toggle is one row showing the face for the item's state. *Remove Prepared Audio* takes the article out of
every prepare and deletes its audio (it stays out of its folder's prepare, P8); a folder's
*Remove Prepared Audio* does it for each of its pages. *Stop Preparing Audio* keeps what is prepared,
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
toasts (*already preparing*, *Nothing to prepare*) float just above the Listen
bar (never over it), as every toast does, and goes after a few seconds. A toast's message wraps
between words, never inside one: when a word wouldn't fit beside *View* (the largest text sizes),
*View* goes under the message, and then the symbol goes. Over the Reader and Listen a
toast, like the Now Playing bar and the play controls there, takes the reading theme's card,
inks and accent. Nothing is modal:
while prepared audio run, a 2 pt jade line along the top edge of the bottom chrome (the browser's, the
Library's, the Reader's) fills as they get on, and fades when nothing is queued, everything queued
is paused, or no on-device voice is selected (VoiceOver reads it as *Prepared Audio, N percent*, a
button that opens the list). The article playing and the chapter after it always go first, a hot
phone or Low Power Mode holds it, and in the background it goes on while audio plays; a link
article's text is fetched only while the app is in front (LISTEN_PLAYBACK.md).

```
Prepared Audio                                       ( Done )
Now                                        Pause All
[i] Chapter 3: The Tide                        ⋯   the ring filling (its own progress) before line two
   ◔ Demo Folder   17%
Waiting  2
[i] Chapter 4: The Bay                         ⋯   the spinning arc, in the order pages render
   ◜ Demo Folder   Default
Prepared  1
[i] Coupon Basics
   Default   12 MB
12 MB on this device
Different Voice  1
[i] Seven-Day Yield
   Kokoro   9 MB
   ( ↻ Prepare Again )
```

**⋯ › Prepared Audio** (`PreparedAudioSheet`, every ⋯ panel: the browser's, the Library's on every screen,
the Reader's, Listen's; medium, grows to large; also Settings › Prepared Audio & Storage ›
Prepared Audio, pushed) lists one row per page (C110: a folder's pages each on their own row, never a folder total;
line two its folder's name, or its site for an article in no folder; the status mark before it:
`DownloadMark`, as everywhere: the spinning arc waiting, the ring filling while it renders, ●↓ once done), in sections shown only
when they have rows (**Now**, **Waiting** in render order, then the ones below; a folder's own
prepare is turned off on its screen, *Pause All* pauses everything). Older text below
describes record rows: **Queued** (the prepare rendering now and those waiting, *Pause All / Resume All*, each
row's filling ring, just before its ⋯, pausing it; grey while paused, a tap resumes it; a paused
prepare is grey on its Library row and its folder's header too, captioned *Paused*),
**Prepared** (each with the grey ✓ and the room it takes, the total under the section, on the
cards' edge), and **Different Voice** (done, but its audio isn't in its article's voice, C138:
it never plays). Every row is a Library row (`ListRow`: one title line, one detail line) and says its voice
as Settings › Voice does, never by the voice's name (*Default*, else its voice library, *Kokoro*:
`LocalTTSCoordinator.voiceSummary`; From Listening rows too); its parts are set apart by space, never a dot. A row opens what was prepared
(the Reader, or the Library at the folder). Its ⋯ and long press are the prepare's one menu,
the same in every section (`PrepareMenu`): *Pause / Resume* (dimmed once done), *Prepare Again*
(renders it again in its article's voice, C138; dimmed while queued) and *Remove Prepared Audio* on an article,
*Remove Prepared Audio* on a folder (red: the same action as in the article's or folder's own menu,
below). *Keep* is gone (C138): changing the voice in Settings no longer moves anything here; an
article's own voice changes from its menu's *Voice: Default* (or *Voice: Kokoro*, …). Swipe left is the same *Remove Prepared Audio* / *Remove Prepared Audio*.
The list holds prepared audio of what is in the
Library: removing an article from the Library, or deleting an article or folder, takes its prepare off
the list too (a removed article's audio stays, ephemeral). On a device that can run neither
voice nothing renders: queued prepared audio say *Can’t prepare on this device*, and the list says
why. An article its voice can't read (its language) is marked failed with the same words as
Listen's ("Can’t read French yet."). *Remove
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
folder or a book from its screen's ↓, over the five tiles every empty screen has, each closing the sheet first.

**The Move tree** (`MoveTreeSheet`): one sheet for *Move to…* (titled *Move to*) and every *Save
to Folder…* (an article's menu out of the Library, 🔖 held; titled *Save to Folder*); the import sheet's *Add to* pushes the same list inside it. The whole tree as one indented list (medium, grows to large): *＋
New Folder…* (made at the top level, and the item goes in it), *Library*, then
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
(the browser's, the Reader's or Listen's), *Save to Folder…*, ⋯ → *Save to Library* / *Remove from Library*) isn't stored: the
library reads as it did before it, and a toast says so ("Couldn’t move", "Couldn’t save") where
a success would have shown. *Remove* of several pages is one change: all go, or none. A folder's
screen doesn't follow a move that didn't happen, the Move tree stays up, and 🔖 keeps what it showed. In Edit, the selection stays when its change can't
be saved; Edit's *Remove* is two changes, the pages first and then, after the question, the
  folders, so a folder delete that can't be saved leaves the folders selected but doesn't bring back
  pages already removed. The toast shows over the Move tree, the import sheet
and Listen too. Listening goes on being kept meanwhile: where you are in an article, when you last played it and
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

## The Reader and Listen (what you see, what you hear)

What you **see** and what you **hear** are separate, in three layers: the surface (the browser or
the Library), the **Reader** for reading any article, and **Listen** for what you hear.
Navigating never changes what you hear, and a play button never navigates (a Library row's tap, which
plays, slides Listen up on compact width). The Reader never shows
the article you hear: opening the Reader of that article (📄, a Library row) opens
Listen instead.

The two widths present them differently:

| | Compact width | Regular width |
|---|---|---|
| Reader | In place, under the bottom chrome (`ReaderSurface`): the Browser's reader mode and Library Read ("Bottom chrome", above). No sheet, grabber, close pill, top bar or bottom band: the top group (⋯, Aa, ▶ Listen) floats at the top, ‹ starts row 1, the heading reads the title, then "site  length" | A `Sheet` over the surface that opened it (`ReaderSheetScreen`): grabber, close pill, top bar, bottom band |
| Listen | Listen: a `Sheet` that covers the screen and the chrome, with Aa and ⋯ (the top group) in its top corners, the grabber between them, the article's title at the top of its text and the player card at its foot; a pull down closes it ("Bottom chrome", above) | A `Sheet` over everything that shrinks back into the Now Playing bar; its close pill names where it plays from |
| Into Listen | The chrome's round Listen, a reader's ▶ Listen, a Library row | The Now Playing bar (tap, swipe up), the Reader's ▶ |

The rest of this section describes the regular-width sheets unless it names compact width; the
compact readers and Listen are described under "Bottom chrome".

**On regular width the Reader and Listen share their chrome** (decision D24), so Listen turns the Reader into Listen
with nothing moving but what has to: the same top bar (the close pill at the top left, **Aa** then ☝︎ at the top right, at the article margin), one shared bottom band
(`ReadingBottomBand`: integrated controls flat on the page background, separated by a hairline
divider — title row, scrub track, transport row, no card, no shadow), the same
⋯ menu (Listen adds *Go to*), and the same colours and type (the reading theme, below). They
differ where the job does: Listen's transport has 🔖, ⏮, the round ⏸ / ▶, ⏭ and ⋯, the
Reader has ⋯, disabled ⏮/⏭ and a round ▶ that starts Listen; Listen has the scrub row with
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
  hear (replacing what plays) and turns the Reader into Listen in place, where the Reader was
  (decision D2):
  - **At the Reader's top** (its first line of text not yet scrolled above the top of the reading
    area, so the title may be part way up), Listen opens at its top.
  - **Scrolled into the text**, the same line stays at the same place on screen.
  - **When that place can't be reached** (past either end of Listen's article), the article goes
    as far as it can that way, so the line stays in view as near its place as possible.

  Listen sets that position once its article is laid out and holds it while the layout
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
  area where it is, to the character; an article at its top stays at its top. Listen does the
  same, or, while it follows the audio, centres the spoken sentence again.
- 🔖 saves / unsaves (tap; filled = saved), or files the article (long-press → *Save to Folder…*,
  the Move tree: saved there, or moved there when already saved); it keeps the screen as it is,
  and playback too, except that unsaving the article you hear stops it.
- **⋯** (slot 5, the browser's ⋯ spot; Listen's is the same): rows *Save / Remove from Library, Move to…* (dimmed until
  the article is saved)*, Share, Prepare / Remove Prepared Audio* (dimmed until the article
  is saved; *Remove Prepared Audio* while it prepared audio or is prepared, as its Library row's menu
  shows)*, Prepared Audio, Settings*; big buttons
  **Settings / Library / Listen** (compact width: **Library / Browsing History / Listen**). The
  page's website is reachable through *Share*. Playback never stops.
- The text fills the page down to the screen's foot and runs under the header and the bottom
  band, which are drawn over it (the header on the article's colour, the band on its tinted bar
  material); its first line starts below the header and its last line scrolls clear of the band.
  A tap in the middle goes full screen (below).
- **Links** in the text open in the browser when they lead to a web page (as ⋯ → Website does:
  the Reader leaves, Listen too); a link to a place on the same page goes there (in Pages, to
  the page holding it) and stops following the audio as a page turn does; any other link (mail,
  a book's links between its own chapters) does nothing. The text never leaves its article.

### Listen

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
  every paragraph stays in full ink (C105). The *Jump to Audio* pill takes the theme's accent and its ink on the accent; the scrub row, the bubble, the jump hint, the ⋯ panel and the speed popover
  take the theme's colours. A plain-text article (no reading HTML) shows its paragraphs on the
  same reading article, in both, so everything below applies to it too.
- **The bottom band** (flat on the page background, no card, no shadow) shows the artwork tile,
  the title (`ArticleRowTitle.lineOne`) and the time left (*9 min left*; *Finished* at the end)
  in a title row, then the scrub row with the speed control, status notes and the transport.
- **On regular width the close pill names where it plays from** (*⌄ Pride and Prejudice*; VoiceOver: *Close Now
  Playing*, *Playing from …*): the folder the article is in, a book, a series or one you
  made; *Library* for a saved article in no folder; the site for an article you haven't saved. Tapping
  it only closes. **⋯ → *Go to <name>*** (the first row) closes Listen onto the Library at
  that folder, or the Library's home, on Everything; for an article that plays from its site it reads
  *Go to Library*, dimmed until the page is saved, and ⋯ → *Website* opens the site in the browser.
  The Reader's ⋯ has no *Go to*.
- **Aa** and **☝︎** (top right, as in the Reader): Aa changes how the article reads; ☝︎, then a
  tap on a paragraph, plays from that paragraph.
- **🔖** (slot 1, as in the Reader) saves / unsaves (tap) or files the article (long-press →
  *Save to Folder…*, the Move tree); saving never touches playback, and unsaving (*Remove from
  Library*, here or in ⋯) stops the article, so Listen closes.
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
  doesn't move the text, so following goes on). Then *Jump to Audio* shows, on both widths: a thin accent pill
  (`OverTextPill`, 8 pt above and below its label) floating centred on the line just
  above what floats at the text's foot (compact Listen's player card, regular width's band; the home indicator's strip
  in full screen), with an arrow that points to the spoken sentence, ↑ when it is above the visible text and ↓ when
  below (Pages: on an earlier or a later page). While it shows, Scroll mode's text leaves its line clear: the end of
  the text scrolls to just above the pill, and the text on screen doesn't move as it comes and goes.
  VoiceOver: "Jump to Audio", hint "Scrolls up / down to the sentence being read". Tap it (or start another page) and
  following resumes: the text scrolls so the spoken sentence is in the middle of the visible
  text (between the top of the screen and the bottom chrome), as when Listen opens, and
  stops at the document's ends where it can't centre. Scrubbing scrolls to the paragraph under
  the thumb.
- **At the end** it stays on the article: the text stays, all of it in full ink, the band
  says "Finished" where the time left was (the Reader shows the article's length), and ▶
  plays the article again.
- **Controls** (the band): optional status notes, then `[🔖][⏮][▶︎][⏭][⋯]` in the five-slot
  grid, then the scrub row and speed. (Compact width's Listen has the player card instead, its ⋯ the
  top group's system menu: "Bottom chrome", above.) ▶︎ / ⏸ is a 44 pt round button (accent fill, dark glyph; fixed size,
  like the toolbar glyphs), as tall as the row, so every slot sits where it does on the other
  surfaces. ⏮ ⏭ and headphone / lock-screen skips are paragraph skips
  (D4). A sideways swipe on the row skips too.
- **Status notes** ("Preparing next…", "Preparing the voice", the developer-only Debug chip) sit **above** the transport row so appearing text never pushes it.
- **⋯**: the article's menu ("Menus", above) for the article you hear, with *Go to <name>* first (when
  it plays from a folder or the Library), then *Prepared Audio, Settings*; big buttons
  **Settings / Library / Listen**.
- A **prepare progress line** runs along the top edge of the bottom band while prepared audio run,
  as on the other surfaces, in the theme's accent.
- **Scrubber** (sentence-precise; the track runs inside the band): fill = progress
  (weighted by text length; the thumb moves smoothly inside a paragraph, estimated from the
  player's time); the lighter fill ahead of it is audio already rendered.
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
  - Playback starts at the synth chunk holding the sentence, offset into its audio
    by characters (chunk boundaries found by counting letters; stitched paragraphs use the stored
    chunk durations), with a 0.25 s lead-in so the first word isn't clipped. Not rendered yet: the
    render queue does that chunk first (then the rest of the paragraph).
- **Speed** (*1×*, at the end of the scrub capsule; a tap opens the list, 0.75× to 2×; Settings ›
  Listening has it as a row, *Speed 1× ›*, opening the same list): applied in place — the current sentence keeps going at the new speed.
  A pitch-preserving time-stretch on the player (`AVAudioPlayer.enableRate` / `rate`; all audio
  is rendered at 1×), so nothing is re-queued, re-rendered or restarted. The rate is persisted
  (`reader.rateMultiplier`) and the lock screen's playback rate follows it (and can set it).
- An article played without saving is kept while it is in the last 50 of Recent (C134), with its text and its
  spot: after a relaunch it is at the top of the Library's *Pages*, opens in the Reader where it was, and
  Listen shows its text.

### Full screen (the Reader and Listen)

The Reader and Listen read full screen the same way (`ReadingChrome`); Follow's chapter preview doesn't.

- **Full screen is a tap in the middle of the text, in and out; in a compact in-place reader in Scroll
  mode, also a scroll** (60 pt down in one gesture enters it, 24 pt up leaves it, however it began: "An
  in-place reader is expanded or full screen", above). In a compact in-place reader it removes the whole
  bottom chrome (its two rows), the top group, the fade and the status bar together (fading together under
  Reduce Motion), the home indicator dims, and the text shows alone, never
  moving, down to the screen's foot, with nothing floating over it. In compact Listen the player card slides off, the status bar hides
  and the sheet's top gap, rounded corners and dim go: the page covers the screen; the
  chrome under Listen keeps its state. In every reader, Scroll mode, the end of the text then scrolls down
  to the home indicator's strip (with the bars up, to just above what floats: the card, the band, the
  chrome as drawn); the text on screen stays where it is as they go or come, and a text at its end stays
  at its end. Pages mode keeps its pages as they are. **Listen's and the regular-width sheets' full screen are
  the tap's alone: scrolling never enters or leaves them.** Leaving full screen brings the chrome back
  expanded (an in-place reader's chrome never folds). On regular width the sheet's grabber, top bar and bottom band hide and show
  together the same way, and the sheet covers the screen as Listen's does.
  The app's own scrolls (following the audio, a scrub, opening at a spot, a reflow) never change it. The bars
  stay while VoiceOver runs, while ☝︎ is on, and while Aa or ⋯ is open.
- **Taps on the text** (not on a link; ☝︎ keeps its paragraph taps): the right 30% of the width
  goes forward a screen, the left 30% back one (the visible text less one line, landing with a
  whole line at the top: below the top bar, or below the fade in full screen; on the
  `Motion.standard` spring, a jump under Reduce Motion, never past either end), the middle enters or
  leaves full screen. The first 48 pt from the left edge do nothing, so an edge swipe never turns a
  page. Edge taps leave the bars as they are. In Listen a page turn stops following the audio
  as a drag does, and *Jump to Audio* appears.
- **A small ▶ / ⏸ floats at the bottom right** in full screen, in Listen and on regular width (never in
  a compact in-place reader) (a 44 pt accent disc with the
  shadow, above the home indicator, at the article margin): Listen's plays and pauses
  what you hear; the Reader's is its Listen (and turns it into Listen). In Listen, *Jump to
  Audio* (while the text is away from the audio) comes and goes with it, as one group. It fades out 3 s
  after full screen begins; a scroll, an edge tap (a page turn), or a tap on it, brings it back for
  another 3 s. A
  tap in the middle leaves full screen instead, and the bars come back. It isn't there while
  the bars show.
- **At the top**, a pull down in full screen rubber-bands and, on regular width, brings the bars
  back; in a compact in-place reader it is a scroll up and brings them back after 24 pt; Listen's is left by
  the middle tap alone (on regular width it never closes the sheet; a pull that begins with the bars showing closes it as
  usual, and while it pulls the sheet it never hides or shows the bars).
- The floating *Jump to Audio* (Listen, both widths) shows only while the text is away from
  the audio, centred just above the card or band, and in Scroll's full screen above the home
  indicator's strip, on the line of the floating ▶. Pages mode's full screen floats nothing over the
  text (the ▶ neither).

### Pages (the Reader and Listen)

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
  with the audio: once the voice leaves the article shown, Listen offers *Jump to Audio* in
  its usual place above the band, as in Scroll (only while the bars show, C111), which shows the spoken sentence's page once. Neither
  the floating *Jump to Audio* nor the floating play / pause shows in Pages. Opening Listen
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
app's theme. **Aa**, in both sheets' top bars just left of ☝︎ (on compact width in the reading pages' top
group), opens a compact panel pointing at it; Settings › Reading has the same controls. Both edit the one store, so they never disagree,
and the article under the panel changes as you choose (colours repaint in place; a typeface, size or
spacing change reflows the text and keeps the line on screen where it was).

- **Theme**: *Match App* (the app's paper and ink in its appearance and colour; the default),
  *Light*, *Sepia*, *Dark*, *Black*. One token set each (`ReadingPalette`: background, card,
  ink, secondary and tertiary ink, dimmed ink, highlight, accent) for the Reader and Listen
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

Aa sits in the top bar, not the bottom row: Listen's five slots are full (🔖, ⏮, ⏸, ⏭, ⋯)
and the bottom chrome never moves, and the top bar is the one row the two sheets already share
control for control.

## Settings

**Settings** (`SettingsView`) is a `NavigationStack` of cards on paper: on compact width the chrome
pill's third destination, in place under the chrome; on regular width a sheet opened from the last row
of every ⋯ panel and the sidebar's bottom row (titled *Settings*, *Done* closes it). Every list of cards in the app (the Library and its
folders, History, Settings and its pages, a Voice picker, Follow, Following, the Move tree, Folder
Details, Book Import, Prepared Audio) has the same rows: at least 48 pt at the default text size
(`Control.bar`, the system Settings' proportions, set once by `cardListStyle`: no row sets its own; a two-line row grows to its content), 16 pt
in from the card's sides with no List inset above or below, sections 16 pt apart, and a card's
note 8 pt under it (`cardListStyle`, `listCard`, `listFooter`). None of Settings' rows leads with
a symbol. Top to bottom:

- **Listening** (first; the audio settings):
  - *Voice ›* (`VoicePage`): the default voice for new articles and books, from the one voice
    switcher (`VoiceSelectionList`, the same list an article's or a book's *Voice* picker shows).
    One card, no tabs: each voice library, in the registry's order, is a row that opens its section
    in place (`DisclosureRow`, as iOS's Settings groups do; a row in the card, not a section
    title): a tap anywhere on it opens or closes it, its chevron turning from › to ⌄ (a cross-fade
    under Reduce Motion), and VoiceOver calls it a button, expanded or collapsed. Open at first:
    the library holding the voice in use and any with a download running; several can be open, and
    what is open lasts as long as the screen. A closed one still says what is inside: the voice in
    use set apart by space (*Kokoro   Heart*), and a small accent ring while one of its voices
    downloads. Open, it lists its curated voices; Phonon's others follow behind their own *More
    Voices* row (lined up with the names, closed until opened or the voice in use is there).
    Picking a voice picks its engine. Each voice row is drawn as iOS's own Voice screen draws one
    (`VoiceRow`): the sample's ▶ at the leading edge (every voice has a sample; one without would
    show its ▶ dimmed, never a gap), the name over its size, in every state, so rows never change
    height (the size of its own files on the device once it is there: a Phonon voice's file in the
    app, *0.3 MB*, a Kokoro pack, *0.5 MB*; while it isn't, what choosing it downloads: with
    Kokoro's shared model missing, model and pack, *164 MB*; VoiceOver reads it with the name), and
    one trailing mark: ✓ for the voice in use once it is on the device, ⤓ when it isn't downloaded
    (the voice in use too: it shows ⤓, VoiceOver still calls it selected, and the ✓ comes back once
    it downloads), the download's progress while it downloads, whoever started it (a pick, or
    playback loading the voice): `DownloadMark`, the app's one download look: a spinning accent arc
    while it starts, then a ring filling round a ■ that stops it, and listening waiting for it too (its VoiceOver hint says so); nothing for a
    downloaded voice not in use.
    A tap on the row or ⤓ picks it: one not on the device downloads first and the ✓ stays on the
    voice before until it is there (the newest pick wins, the voice already in use included, and a
    stopped download never selects); a failed download says *Couldn’t
    download* in red on its row, with ⤓ back (a tap tries again); a stopped one goes back to not
    downloaded. On cellular or in Low Data Mode Kokoro's model asks first ("Download on
    Cellular?" or "Download in Low Data Mode?", *Download* or *Not Now*, which stops it).
    A download playback started fails on its row the same way. A stop while it waits for the
    network's answer or for that question ends the wait and takes the question away.
    *Edit* (top right) leads each downloaded Kokoro voice's row with ⊖ (every row moves over for
    its column); a tap on ⊖ turns it upright and shows a red *Remove* in place of the row's mark
    (one row at a time), the same action as the swipe's *Remove*. The row stays: only the
    download goes, after its question. Heart ships in the app, so it is removable only as Kokoro's last
    voice, which removes Kokoro's model too ("Remove Kokoro? Frees 164 MB. Kokoro voices will
    need to download again."); removing the default, or the voice of what you're listening to,
    asks first and says what changes: listening stops, which voice new articles take, and that
    articles already in it download it again before they play (`SpeechController.voiceRemoval`
    decides it, and `removeVoice` carries it out, asking again if what it does changed meanwhile). A failed removal is a
    toast. Edit and the swipe work in every open section, and a section closes in Edit too. A
    failed engine load's message is the first row of its section; a library the device can't run
    keeps its row, and opening it says what it needs. The note under the card is the screen's. The *Voice ›* row's
    value never names the voice: *Default* while the built-in voice is the pick (Zoey, else
    Heart), else its voice library (*Kokoro*).
  - *Speed ›* (the speeds Listen lists, 0.75× to 2×, the
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
  It steps aside under a sheet or Listen.
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
| Browser ⋯ / Reader ⋯ / Listen ⋯ / Library ⋯ | — | morph panel over the button (same design; rows per surface) |
| ⋯ → Website (Reader, Listen) | no shortcut | leaves the Reader (the sheet closes on regular width, and the library) and shows / loads the page in the browser; audio continues |
| ⋯ → Settings (`SettingsView`); on iPad also the sidebar's Settings | Done | `.sheet` (a form sheet on iPad); Voice, Language, Speed, Appearance, Reading, Prepared Audio and Acknowledgements push inside it |
| Reader / Listen → Aa (`TextAppearanceControl`; compact width: the top group's Aa, `ReadingTopGroup`) | tap outside | popover from Aa |
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
| Listen (`NowPlayingScreen`): the chrome's Listen, a reader's ▶ Listen, a Library row, the bar, the Reader of the playing article, crash resume | compact: none (pull down; VoiceOver: escape); regular: *⌄ <playing from>* pill, top left | compact: a `Sheet` that covers the screen and the chrome, pull down to close; regular: `Sheet` over everything, pull the header down |
| Listen debug panel | Done | `.sheet` (over Settings when opened from it) |
| Speed picker | — | popover |

The browser's own ‹ / › are web-history buttons (the web view also has its edge swipes), not screens.

**Item wording (C120).** Every item is an *article* in the UI ("3 articles"); in an imported EPUB's folder it is a *chapter* ("12 chapters"). An item is never called a "page" (Pages is only the Reader mode). Recent lists only started articles and chapters, never folders (C119).

## Retention and Prepared Audio (C134, C135, C136)

- **Three states.** *Prepared*: saved and you chose *Prepare Audio*; its audio is never cleared automatically. *Saved*: in the Library; listening renders audio as it goes, and saving or starring no longer renders the whole article. *Being read*: opened or played without saving, listed in Recent.
- **Recent is the last 50 articles started.** At launch and when an article starts, unsaved articles beyond those 50 are deleted with their audio; saved articles beyond them lose only their audio from listening. Audio the session or the staged chapter needs is never touched. The finished-chapters trim skips prepared audio.
- **Prepared Audio list** (⋯ › Prepared Audio, Settings): the prepared sections (Now, Waiting, Prepared, Different Voice) and **From Listening** (audio rendered while listening, no ↓, with a footer about Recent 50); every row says its voice as Settings › Voice does (*Default*, else its voice library; never the voice's name). Every row has *Delete Audio* (swipe and ⋯), which never deletes the article. The list's ⋯ (`MenuRegistry`, `.deleteAllPrepared`, `.clearListeningAudio`) has **Delete All…** ("Delete N articles and their prepared audio? This can't be undone.": deletes every prepared article and its audio, folders stay) and **Clear Audio from Listening…** (that audio only), each shown only when its section has rows.
- **Naming.** The feature is *Prepare*, in the UI and in code (`PrepareCenter`, `PrepareRecord`, `PreparedAudioSheet`, `Features/PreparedAudio`). *Download* stays only for real file downloads (voice models, the CPU model, EPUB files). On-disk names are kept: `Downloads.json`, its keys, `downloads.wordsPerSecond`.
