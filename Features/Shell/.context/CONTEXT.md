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
  path and tab are written to `SurfaceMemoryStore` on every change and restored at launch; a UI-test
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
  removed: no switch of style mid-gesture, so nothing flickers. The ⋯ on either sheet is a system
  menu and keeps the system's look, not the theme's.
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
- **Shared look lives in `../DesignSystem/`**: tokens, `Motion`, `BottomChrome` and the components. This folder keeps what knows about the app:
  `ShellState`, the ⋯ menu (`MenuContext`, drawn by `MenuRows(blocks: context.blocks)` in a system `Menu`, at
  every width: the item's rows from its one menu definition, `ArticleMenu` / `FolderMenu`, then the
  screen's rows, then regular width's navigation rows; `MenuRows` draws `MenuRow`s and knows no surface), the Now Playing bar on a
  surface (`NowPlayingBarView`, whose long press is the article's menu then *Stop Listening*).
- **Compact width: one chrome host** (`Chrome/ChromeHost.swift`; `docs/NAVIGATION.md` "Bottom
  chrome"). Three destinations (Library, Browser, Settings), at most two rows expanded and a glass bubble
  folded, the Listen button ending row 1, the pill alone on row 2 (no ⋯ and no play/pause in the chrome;
  Listen is a cover above it; menus are on title lines and the Browser field's leading glyph), glass inside one `GlassEffectContainer` on
  iOS 26 with a blur and glass tint as the fallback. Its translucent fade takes the colour of what is under it: a
  web page's `underPageBackgroundColor` (`WebViewStore.pageBackground`, KVO), paper, or the reading
  theme. The in-place reader (`ReaderSurface`) covers a web view that takes no touches, so it
  carries its own left-edge swipe for ‹. The rest of design 5e is under "Planned"
  there. Regular width is untouched.
- **How the chrome host is wired.** Each destination hands the host a `ChromeScreen` (field,
  arrows, bubble title). One state (`ChromeState`), one pure layout (`ChromeLayout`, from
  `ChromeMetrics`: 104 pt of rows ending on the home indicator's strip) and one scroll controller
  (`ChromeScroll`). The glass is `ChromeSkin` (App sets `ChromeSkin.forcesMaterial` for
  `-chromeFallback`). Screens reserve `ChromeHome.clearance(step: 0)` above the safe area
  (`CompactChromeInsets`) and report their scroll with `CompactChromeScroll`, naming their
  `ChromeSource`. `ChromeScroll.policy` (`ChromePolicy`) is `.folds` on pages, lists and Settings;
  `.holds` on the start page, in Edit and under VoiceOver; `.reads` on an in-place reader, which is
  expanded or full screen (`ChromeScroll.fullScreen`, the one value the chrome and the page's
  `ReadingChrome.hidden` both read), never folded. A screen's ⋯ is on its title line
  (`TitleMenuButton`, `LibraryTitleMenu`, drawing `MenuContext.blocks`); the Browser's is
  `AddressField`'s `holdMenu`. Library Read and Browse reader mode open in place via
  `ReaderSurface`; their Aa, ▶ Listen, 🔖 and ⋯ are the top group (`ReadingTopGroup`), which Listen
  has too without ▶. ▶ Listen is never a play/pause in place: once the page is what you hear it shows
  the live state (`ReadingListen.Face`) and its tap only opens Listen. Listen and the top group's ⋯ and Aa share one
  round face, `ChromeCircleFace`.
- **Listen over the chrome.** `isNowPlayingPresented` draws `NowPlayingScreen` above the chrome in
  `BrowseStartView.layers`, as a `Sheet` covering the screen (`ReadingShowing.cover`), below the ⋯
  menu overlay and the sheet presenters so Voice, Save to Folder, ⋯ and the debug panel open over
  it. Its top row takes hold a further `Control.bar` down, unseen, over the top of the text
  (`Sheet`'s `grabReach`); a tap there is still the text's. Idle Listen binds the page played last,
  paused (`SpeechController.prepare`), never a second "current article"; with nothing to bind it
  opens on *Nothing Playing*, and a showing that loses what it showed closes.
- **Settings on compact width** is `Surface.settings` with `settingsPath` and `settingsSearch`;
  `isCompact` turning false on the Settings surface moves it to `ShellSheet.settings`.
- **Only the screen showing drives the compact chrome, handed over in one step.** Every report to
  `ChromeScroll` names its `ChromeSource`, and so does the in-place reader's full-screen write
  (`setFullScreen(_:from:)`; the Browser's reader stays mounted under other destinations); the check
  against the owner runs when the report is delivered, not when it was sent: the Browser's web view
  queues its offset reports in a `Task`, and keeps sending them under a reader, the Library, Listen or a
  sheet (hit testing off doesn't stop KVO). A refused report touches nothing, not even the baseline. The
  owner is `ShellState.chromeOwner` (the source and the screen within it: the Library's and Settings'
  paths, the Browser's page (`browserPage`, so a page that changes under another destination or a cover
  is a new screen only when the Browser shows again), the page read in place; nil under Listen, the Reader, any sheet or the Files picker), handed
  over by `syncChromeOwner` from the `didSet` of every property it reads, so each transition reaches
  `ChromeScroll.hand(to:)` synchronously; a new input to `chromeOwner` needs the same `didSet`. The
  handover drops the gesture's continuity on every change, keeping what is drawn: the first accepted
  report after it only sets the baseline, so a fling under a Listen or sheet that opened and closed
  never lands its travel at once. A cover and its removal back to the same owner keep the fold and full
  screen (a pending settle is cancelled under the cover and rescheduled when the owner is back); any other owner starts expanded and out of full screen. The rule (`ChromePolicy`) is computed
  in the same step from the source and `ChromeConditions` (VoiceOver, the reading layout, which
  destinations are in Edit, whether the Browser has a page), which `ChromeHost` keeps current; no screen
  resets the chrome on appearing.
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
- **Geometry holds within 1 pt**: toolbar slot positions.
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
  Reduce Motion, slides become fades (`Motion.slideAndFade`, `Motion.sheet`).
- **Regular width (iPad) is a second layout of the same shell, not a second shell.** The gate is
  `horizontalSizeClass == .regular`; nothing iPad-specific applies in compact. What it changes
  (user-visible behavior: `../../../docs/NAVIGATION.md`, "iPad and regular width"): a collapsible
  left sidebar (`RegularShellSidebar`, hosted by `BrowseStartView`), the Browse address field as the
  main pane's top band, the toolbar and Now Playing moved into `ClusteredPlayerDock` (it replaces
  `NowPlayingBarView` and steps aside under a sheet), a centred Reader column, and Voice and
  Settings as `.presentationSizing(.form)` sheets. Measures live in
  `../DesignSystem/Tokens/RegularLayout.swift` (`regularReadableMeasure`, `regularInsetFormSheet`
  apply them). Both layouts must keep working: probe a change on an iPhone and an iPad simulator.
- **The welcome article is wired through the shell, not special-cased in it.** `ShellState.openWelcome` is a
  closure `AppComposition.attachWelcome` sets once the library exists (like `isHearing`); ⋯ › Help (`MenuContext.help`, in every
  `tiles`, alone in the compact Library's) and Settings › About call it. `WelcomeArticle.open` opens Library Read (as a row's *Open* does), not Listen, while another page plays or is paused; it clears any sheet
  (`shell.sheet`, Settings on regular width) so Listen is not under it. Nothing else in the shell names the article.
