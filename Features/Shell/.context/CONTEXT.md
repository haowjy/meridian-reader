# Shell: working notes

What the user sees is in `../../../docs/NAVIGATION.md`. This file holds what to keep in mind while
changing the shell code.

- **`ShellState` is the navigation model** (what you see). Surface (browser, library, or Settings on
  compact width, with its pushed pages `settingsPath` and Search Settings `settingsSearch`) and the
  Library's path (`libraryPath`, bound to the Library's `NavigationStack`), the home's tab
  (`homeTab`: `showLibrary(at:)` selects Everything, `openLibrary` keeps it; stored under
  `library.homeTab`, where an older build's `"favorites"` reads as Everything; `showLibrary(at:)`
  closes a page open in Library Read, since a place asked for by name must show), the Reader sheet and
  its `ReaderOrigin` (derived from the surface), Now Playing, the one other sheet and the toast.
  Add a screen by adding a case here, not a presentation flag in a view. The surface,
  path and tab are written to `SurfaceMemoryStore` on every change and restored at launch (D10); a UI-test
  launch doesn't restore unless `-restoreSurface`, so tests start on the browser whatever the
  last one left. One sheet at a time, except the listen debug panel, which shows over Voice
  settings when opened from them (`overSheet`, `ShellSheet.showsOverASheet`); the sheet's view
  presents it, so nothing else hosts a sheet of its own. It never stores what
  you hear: `isHearing` (injected) asks the playback session, so `openReader` of the playing article
  opens Now Playing.
- **Layers** (`BrowseStartView.layers`): surface (and its in-place reader) → Reader sheet (regular) →
  compact chrome → Now Playing (Listen) → ⋯ menu → system sheets. The toast (`ShellToastLayer`) floats over whichever bottom chrome
  is up (the browser's, the Library's, the Reader's `floating` slot, Now
  Playing's controls; the Move tree and the import sheet have no chrome, so it floats a toolbar
  row above the sheet's bottom, `sheetToastLayer()`: what shows of a medium-detent sheet ends
  above its content's bottom, which clips a toast anchored there). Each layer showing the toast times it out (`ShellState.expireToast`); a layer
  that goes away first, such as the Move tree closing as the toast comes up, leaves it showing.
  `attempt` runs a change that can fail and shows its failure as a toast. A covered layer is out of hit testing and hidden from VoiceOver. The `Sheet` component
  animates its own rise and close and then calls its `onDismiss` (`readerDidClose`,
  `nowPlayingDidClose`) with the presentation id it was shown with, so a close that lands late
  can't remove a sheet shown since; each layer is `.id`'d by its presentation, so a replacement
  starts fresh. Programmatic closes (Website, navigating) just remove it.
- **The Reader and Now Playing draw in the reading theme** (`Sheet(palette:)`, a `ReadingPalette`
  from `ReadingAppearance`), the same for both; `readingSurface` sets `readingPalette` and the
  theme's colour scheme on what they hold, and components that sit on both read it (`reading?.x ?? Palette.x`): everything that can float over the text does, the toast, the Now Playing bar and `PlayStateButton` included, so no app colour shows on a reading theme. A dark theme
  (Dark, Black) over a light app gets light status bar content from a clear window that takes no
  touches, shown just above the app's while the sheet is up
  (`DesignSystem/Chrome/SystemBars.swift`); SwiftUI's own route, a colour scheme for the
  window, would flip the surface underneath. The same window hides the status bar (and asks for a
  dimmed home indicator) in full screen, in every theme: while it is up it is the window the
  system asks, so a second mechanism on the app's window would be ignored. When neither is wanted
  any more it answers as the app's window for the length of the fade, then goes: removed at once,
  the status bar would pop back. Kept for the sheet's whole life it made the UI tests run about
  35 s longer, so it lingers only that long. Nothing of the app's covers the sheets; a system
  sheet over them (Settings, Share) leaves the strip above dark, so light stays right there.
  During a pull the dim lifts, and `Sheet` lays a scrim under the status bar
  (`PullDownLook.statusBarScrim`) that keeps the strip at the resting dim until the sheet is
  removed: no switch of style mid-gesture, so nothing flickers. The ⋯ panel opened from either
  sheet takes the theme too (`MenuContext.isOnReadingPage`).
- **Full screen is the reading sheet's own state** (`ReadingChrome`, in
  `DesignSystem/Components/`), not the shell's (an in-place reader's is the shell's: `ChromeScroll.fullScreen`
  through `ReadingInPlace.fullScreen`, set by the centre tap or the reading rule, so the page's top group and the
  chrome read one value; under Reduce Motion `ChromeHost` fades itself on that live value rather than through its
  delayed dip, so both fade together): `ReaderSheet` and `NowPlayingSheet` each hold one
  and hand it to `Sheet(chrome:)`, which draws the header and the band over the text, measures
  them into the web view's insets and puts the chrome in its content's environment. The bottom
  inset is what floats at the foot (in Scroll's full screen the home indicator's strip alone); a
  change there never moves the text on screen, except that a text at its end stays at its end. In
  full screen the sheet stops being one: its text is laid out from the status bar's foot either
  way (the gap above the header is the header's), and only its outline changes, to the whole
  screen with square corners, covering the dim; so the text never moves in or out. The reading web view feeds it finger drags and taps
  (`HTMLReadingView+Taps.swift`); programmatic scrolls never reach it. While hidden, the web view
  hands no pull to the sheet (`pullHandoff.handoff = nil`); a drag's `canPull` and hand-off are
  fixed when it begins, so the pull that brings the bars back never closes the sheet and a pull
  that began with the bars showing always finishes. Movement that pulls the sheet never shows or
  hides the bars. Pages mode reports its
  footer's height back to the chrome (`pageFooter`, with `homeIndicator` from `Sheet`) so what
  floats over the text sits above the footer.
- **The app's colour is global**: `Palette.accent` and its kin read `AppAppearance.shared`, so a
  view drawing them redraws when Settings › Appearance changes the colour (Observation tracks the
  read). Don't cache a `Palette` accent token in a `static let`.
  The status bar clock keeps ≥ 4.5:1 contrast on the surface on top: probe it in screenshots,
  including after leaving the app and coming back, and while a finger holds the sheet part way
  down.
- **Shared look lives in `../DesignSystem/`**: tokens, `Motion`, `BottomChrome`, the morph
  overlay (`MorphMenu.swift`) and the components. This folder keeps what knows about the app:
  `ShellState`, the ⋯ panel (`MenuContext`, drawn by `MoreMenuPanel` where a ⋯ grows a panel, and as a
  system menu by `MenuRows(blocks: context.blocks)` on compact title lines: the item's rows from its
  one menu definition, `ArticleMenu` / `FolderMenu`, then the screen's rows ending in `tail`, then
  the big buttons; the panel draws `MenuRow`s and knows no surface), the Now Playing bar on a
  surface (`NowPlayingBarView`, whose long press is the article's menu then *Stop Listening*).
- **The ⋯ morph menu measures its focus point** through a preference and places the panel from it.
  Ignore focus changes under 0.5 pt (`MorphMenu.isNewFocus`): pixel rounding of the placement
  nudges the measurement each pass, and without the threshold the panel re-places itself forever
  (a layout loop at 100% CPU). The glass grows by frame and corner radius, never by scale.
- **Compact width: one chrome host** (`Chrome/ChromeHost.swift`; `docs/NAVIGATION.md` "Bottom
  chrome"). Three destinations (Library, Browser, Settings), at most two rows expanded and a glass bubble
  folded, the Listen button ending row 1, the pill alone on row 2 (no ⋯ and no play/pause in the chrome;
  Listen is a cover above it; menus are on title lines and the Browser field's leading glyph), glass inside one `GlassEffectContainer` on
  iOS 26 with a blur and glass tint as the fallback. Its translucent fade takes the colour of what is under it: a
  web page's `underPageBackgroundColor` (`WebViewStore.pageBackground`, KVO), paper, or the reading
  theme. The in-place reader (`ReaderSurface`) covers a web view that takes no touches, so it
  carries its own left-edge swipe for ‹. The rest of design 5e is under "Planned"
  there. Regular width is untouched.
- **Only the surface showing drives the compact chrome.** Every report to `ChromeScroll` names its
  `ChromeSource`, and the check against `driver` runs when the report is delivered, not when it was
  sent: the Browser's web view queues its offset reports in a `Task`, and keeps sending them under a
  reader, the Library, Listen or a sheet (hit testing off doesn't stop KVO). A refused report touches
  nothing, not even the baseline. The driver is `ShellState.chromeDriver` (nil under Listen, the Reader,
  any sheet or the Files picker), handed over by `syncChromeDriver` from the `didSet` of every property it
  reads, so each transition reaches `ChromeScroll.drive` synchronously; a new input to `chromeDriver`
  needs the same `didSet`. `drive` drops the gesture's continuity on every change, keeping what is drawn:
  the first accepted report after it only sets the baseline, so a fling under a Listen or sheet that
  opened and closed never lands its travel at once, however quickly the changes follow each other.
- **A reading page's offset reports are a finger's or a move's, kept apart end to end.** The coordinator's
  `report(_:byFinger:)` is the only caller of `ReadingChrome.userScrolled` (finger) and `textMoved` (move,
  which only re-anchors). A finger report (`isDragging || isDecelerating`) is a move when code wrote the
  offset (every write in `Features/Reader/` goes through `movingByCode`, even mid-fling: a reflow, `showTop`,
  a page swipe's `y = 0`) or when the farthest offset it is clamped to changed since the last report:
  entering full screen drops the foot's inset by the chrome's height, and within that distance of the end
  the clamp would read as a scroll up of that height. A new offset write in a reader goes through
  `movingByCode`, or a fling under it toggles the bars.
- **Regular width: the browser and the Library share the field band** (`SurfaceBand`: the field and its ✕),
  over the clustered dock; the dock's toolbar is a `BottomToolbarLayout` whose items name their slots
  (`.toolbarSlot`), one role per slot on both surfaces. Compact width has no band: `ChromeHost` draws it.
  The Reader's `NowPlayingBarView` hides while covered.
- **Geometry holds within 1 pt**: toolbar slot positions, and the ⋯ focus offset
  (`MorphMenu.focusOffsetFromAnchor`). The `moreMenuFocus` marker, Debug builds with
  `-uiTesting` only, shows where the focus ends up.
- **Sizing.** Field capsules use a fixed height (an unbounded `Capsule` turns into a circle) that
  grows with Dynamic Type up to `Control.maxTextGrowth` (1.5×); every control gets a 44 pt
  tap area through `tapTarget`.
- **Gestures.** Drags that dismiss or collapse lock their axis on the first movement and rubber-band
  the wrong direction (`SwipeGesturePolicy`, in the design system); releases seed the
  spring with the finger's speed, capped (`Motion.dismiss`, `Motion.maxReleaseVelocity`). A
  `Sheet`'s scrolling body pulls it from its top: `Sheet` puts a `SheetPullHandoff` in its
  content's environment, and a UIKit scroll view there feeds it through `ScrollPullHandoff` (a
  target on its pan, after the scroll view's own). New scrolling content in a `Sheet` needs that
  hook, or it only scrolls. A UIKit pan's translation starts at zero where it recognizes, so a
  slow drag has no direction at `.began`: read the axis once it has moved
  (`SheetPullTracking.decidingMovement`), never from the first event. Under
  Reduce Motion, slides and the morph become fades (`Motion.slideAndFade`, `Motion.sheet`).
- **Regular width (iPad) is a second layout of the same shell, not a second shell.** The gate is
  `horizontalSizeClass == .regular`; nothing iPad-specific applies in compact. What it changes
  (user-visible behavior: `../../../docs/NAVIGATION.md`, "iPad and regular width"): a collapsible
  left sidebar (`RegularShellSidebar`, hosted by `BrowseStartView`), the Browse address field as the
  main pane's top band, the toolbar and Now Playing moved into `ClusteredPlayerDock` (it replaces
  `NowPlayingBarView` and steps aside under a sheet), a centred Reader column, and Voice and
  Settings as `.presentationSizing(.form)` sheets. Measures live in
  `../DesignSystem/Tokens/RegularLayout.swift` (`regularReadableMeasure`, `regularInsetFormSheet`
  apply them). Both layouts must keep working: probe a change on an iPhone and an iPad simulator.
