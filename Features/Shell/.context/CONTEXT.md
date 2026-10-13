# Shell: working notes

What the user sees is in `../../../docs/NAVIGATION.md`. This file holds what to keep in mind while
changing the shell code.

- **`ShellState` is the navigation model** (what you see). Surface (browser or library) and the
  Library's path (`libraryPath`, bound to the Library's `NavigationStack`), the Reader sheet and
  its `ReaderOrigin` (derived from the surface), Now Playing, the one other sheet, the toast and
  the prompt. Add a screen by adding a case here, not a presentation flag in a view. The surface
  and path are written to `SurfaceMemory` on every change and restored at launch (D10); a UI-test
  launch doesn't restore unless `-restoreSurface`, so tests start on the browser whatever the
  last one left. One sheet at a time. It never stores what
  you hear: `isHearing` (injected) asks the playback session, so `openReader` of the playing page
  opens Now Playing.
- **Layers** (`BrowseStartView.layers`): surface → Reader sheet → Now Playing → ⋯ menu → system
  sheets → the shell's prompt. The toast (`ShellToastLayer`) floats over whichever bottom chrome
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
- **Now Playing is the player sheet** (`Sheet(look: .player)`): deep jade in both appearances,
  the dark colour scheme plus `onPlayerPalette` for what it holds. Its light status bar comes from
  a clear window that takes no touches, shown just above the app's while the sheet is up
  (`DesignSystem/Chrome/StatusBarStyle.swift`); SwiftUI's own route, a colour scheme for the
  window, would flip the surface underneath. Nothing of the app's covers Now Playing (the Reader
  sits under it); a system sheet over it (Voice settings, Share) leaves the strip above dark, so
  light stays right there. During a pull the dim lifts, and `Sheet` lays a scrim under the
  status bar (`PullDownLook.statusBarScrim`) that keeps the strip at the resting dim until the
  sheet is removed: no switch of style mid-gesture, so nothing flickers.
  `NowPlayingUITests.testTheStatusBarFollowsTheSurfaceOnTop` measures the clock's contrast
  (`UITests/StatusBarContrast.swift`, ≥ 4.5:1) in screenshots, including after leaving the app
  and coming back, and while a finger holds the sheet part way down.
- **Shared look lives in `../DesignSystem/`**: tokens, `Motion`, `BottomChrome`, the morph
  overlay (`MorphMenu.swift`) and the components. This folder keeps what knows about the app:
  `ShellState`, the ⋯ panel's rows (`MoreMenuPanel`), the Now Playing bar on a surface
  (`NowPlayingBarView`).
- **The ⋯ morph menu measures its focus point** through a preference and places the panel from it.
  Ignore focus changes under 0.5 pt (`MorphMenu.isNewFocus`): pixel rounding of the placement
  nudges the measurement each pass, and without the threshold the panel re-places itself forever
  (a layout loop at 100% CPU). The glass grows by frame and corner radius, never by scale.
- **Geometry is tested.** UI tests check toolbar slot positions and the focus offset within 1 pt;
  `UITests/MorphMenuUITestOffset.swift` must match `MorphMenu.focusOffsetFromAnchor`. The
  `moreMenuFocus` marker exists only in Debug builds with `-uiTesting`.
- **Sizing.** Field capsules use a fixed height (an unbounded `Capsule` turns into a circle) that
  grows with Dynamic Type up to `BottomChrome.maxTextGrowth` (1.5×); every control gets a 44 pt
  tap area through `tapTarget`.
- **Gestures.** Drags that dismiss or collapse lock their axis on the first movement and rubber-band
  the wrong direction (`SwipeGesturePolicy`, `App/SwipeBackSupport.swift`); releases seed the
  spring with the finger's speed, capped (`Motion.dismiss`, `Motion.maxReleaseVelocity`). A
  `Sheet`'s scrolling body pulls it from its top: `Sheet` puts a `SheetPullHandoff` in its
  content's environment, and a UIKit scroll view there feeds it through `ScrollPullHandoff` (a
  target on its pan, after the scroll view's own). New scrolling content in a `Sheet` needs that
  hook, or it only scrolls. Under
  Reduce Motion, slides and the morph become fades (`Motion.slideAndFade`, `Motion.sheet`).
