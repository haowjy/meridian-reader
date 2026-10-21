# Shell: working notes

What the user sees is in `../../../docs/NAVIGATION.md`. This file holds what to keep in mind while
changing the shell code.

- **`ShellState` is the navigation model** (what you see). Surface (browser or library) and the
  Library's path (`libraryPath`, bound to the Library's `NavigationStack`), the home's tab
  (`homeTab`: `showFavorites` selects Favorites, `showLibrary(at:)` Everything, `openLibrary`
  keeps it; stored under `library.homeTab`, the two-tab Bool key read once and removed), the Reader sheet and
  its `ReaderOrigin` (derived from the surface), Now Playing, the one other sheet and the toast.
  Add a screen by adding a case here, not a presentation flag in a view. The surface,
  path and tab are written to `SurfaceMemoryStore` on every change and restored at launch (D10); a UI-test
  launch doesn't restore unless `-restoreSurface`, so tests start on the browser whatever the
  last one left. One sheet at a time, except the listen debug panel, which shows over Voice
  settings when opened from them (`overSheet`, `ShellSheet.showsOverASheet`); the sheet's view
  presents it, so nothing else hosts a sheet of its own. It never stores what
  you hear: `isHearing` (injected) asks the playback session, so `openReader` of the playing article
  opens Now Playing.
- **Layers** (`BrowseStartView.layers`): surface → Reader sheet → Now Playing → ⋯ menu → system
  sheets. The toast (`ShellToastLayer`) floats over whichever bottom chrome
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
  `DesignSystem/Components/`), not the shell's: `ReaderSheet` and `NowPlayingSheet` each hold one
  and hand it to `Sheet(chrome:)`, which draws the header and the band over the text, measures
  them into the web view's insets (unchanged when they hide, so the text never moves) and puts the
  chrome in its content's environment. The reading web view feeds it finger drags and taps
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
  `ShellState`, the ⋯ panel (`MenuContext`, drawn by `MoreMenuPanel`: the item's rows from its
  one menu definition, `PageMenu` / `FolderMenu`, then the screen's rows ending in `tail`, then
  the big buttons; the panel draws `MenuRow`s and knows no surface), the Now Playing bar on a
  surface (`NowPlayingBarView`, whose long press is the article's menu then *Stop Listening*).
- **The ⋯ morph menu measures its focus point** through a preference and places the panel from it.
  Ignore focus changes under 0.5 pt (`MorphMenu.isNewFocus`): pixel rounding of the placement
  nudges the measurement each pass, and without the threshold the panel re-places itself forever
  (a layout loop at 100% CPU). The glass grows by frame and corner radius, never by scale.
- **The browser and the Library draw one band** (`SurfaceBand`, D22, rows as D23):
  `BandNowPlayingBar` alone, then the swap and the field, then a `BottomToolbarLayout` whose
  items name their slots (`.toolbarSlot`), one role per slot on both surfaces. Change a row in `SurfaceBand`, not in one surface, or the two drift;
  probe both surfaces' frames in screenshots. The
  band's bar never goes away (it keeps its space hidden when covered), so its height never
  changes; the Reader's `NowPlayingBarView` still hides.
- **Geometry holds within 1 pt**: toolbar slot positions, and the ⋯ focus offset
  (`MorphMenu.focusOffsetFromAnchor`). The `moreMenuFocus` marker, Debug builds with
  `-uiTesting` only, shows where the focus ends up.
- **Sizing.** Field capsules use a fixed height (an unbounded `Capsule` turns into a circle) that
  grows with Dynamic Type up to `BottomChrome.maxTextGrowth` (1.5×); every control gets a 44 pt
  tap area through `tapTarget`.
- **Gestures.** Drags that dismiss or collapse lock their axis on the first movement and rubber-band
  the wrong direction (`SwipeGesturePolicy`, in the design system); releases seed the
  spring with the finger's speed, capped (`Motion.dismiss`, `Motion.maxReleaseVelocity`). A
  `Sheet`'s scrolling body pulls it from its top: `Sheet` puts a `SheetPullHandoff` in its
  content's environment, and a UIKit scroll view there feeds it through `ScrollPullHandoff` (a
  target on its pan, after the scroll view's own). New scrolling content in a `Sheet` needs that
  hook, or it only scrolls. Under
  Reduce Motion, slides and the morph become fades (`Motion.slideAndFade`, `Motion.sheet`).
