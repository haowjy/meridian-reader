# Shell: working notes

What the user sees is in `../../../docs/NAVIGATION.md`. This file holds what to keep in mind while
changing the shell code.

- **`ShellState` is the navigation model** (what you see). Surface (browser or library), the
  Reader sheet and its `ReaderOrigin` (derived from the surface), Now Playing, the one other sheet.
  Add a screen by adding a case here, not a presentation flag in a view. It never stores what
  you hear: `isHearing` (injected) asks the playback session, so `openReader` of the playing page
  opens Now Playing.
- **Layers** (`BrowseStartView.layers`): surface → Reader sheet → Now Playing → ⋯ menu → system
  sheets. A covered layer is out of hit testing and hidden from VoiceOver. The `Sheet` component
  animates its own rise and close and then calls its `onDismiss` (`closeReader`, `hideNowPlaying`);
  programmatic closes (Website, navigating) just remove it.
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
  spring with the finger's speed, capped (`Motion.dismiss`, `Motion.maxReleaseVelocity`). Under
  Reduce Motion, slides and the morph become fades (`Motion.slideAndFade`, `Motion.sheet`).
