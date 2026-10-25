# Shell: deferred

- `Features/DesignSystem/Chrome/BottomChrome.swift`: at accessibility text sizes the glyphs
  inside the field capsule (mic, Jump, bookmark) and the reader's back control use an uncapped
  `.body` font and outgrow their 1.5×-capped frames. Cap the glyph size the same way, or let the
  frames grow further.
- `Features/Browse/BrowseStartView.swift` (`covered`): a layer under a sheet gets
  `allowsHitTesting(false)` and `accessibilityHidden(true)`, yet its elements still show in the
  XCUITest tree (the Reader's `readerClose` beside Now Playing's `nowPlayingClose` with Now
  Playing over another article's Reader). Check with VoiceOver on a device whether they are reachable; if so, find
  what keeps them exposed (an `accessibilityAddTraits(.isModal)` on `Sheet` didn't change the tree,
  and two stacked modal sheets would conflict).
- `Features/DesignSystem/Chrome/SystemBars.swift`: the home indicator's auto-hide in full screen
  can't be seen on the Simulator: check it on a device.
- `ScrollPullHandoff`: a pan that begins with no movement counts as horizontal and can't pull the
  sheet. Synthesized probe touches can begin that way; check a slow pull from the text's top on a
  device.
- `Features/Reader/HTMLReadingView+Pages.swift`: in Pages, a book chapter opened from its folder
  (a probe's tap on the Library row) also gets a tap in the middle of its text (`tapX` 196 of 402,
  logged in `textTapped`), so the Reader opens in full screen; in Scroll it doesn't. Check whether
  a finger's tap does it on a device, and where the click comes from.
- `Features/Browse/BrowseStartView.swift`, `Features/Shell/RegularShellSidebar.swift`: iPad Browse | Reader
  split (web page and Reader side by side in the main pane). Today the Reader is a sheet over the
  surface even at regular width. Design a split in the main pane gated on `.regular`, and decide
  what the sidebar's Browser row selects.
- `Features/Reader/ReaderSheetScreen.swift`: a trailing chapters column for a book's Reader at
  regular width (the iPad design proposed it; the Reader has no chapter list of its own, a book's
  chapters are its folder's rows in the Library). Add the column beside the ~700 pt measure
  (`RegularLayout.readableMeasure`) and keep it out of compact.
- `project.yml`, `Features/DesignSystem/Tokens/RegularLayout.swift`: iPad landscape polish. Only the
  portrait orientation key is set and the layout was only checked in portrait. Decide whether to
  allow landscape, then check the sidebar, dock (`playerClusterWidth`) and reading measure there.

- Bottom chrome redesign (approved 2026-10-25, in progress): the four-PR plan and the screen audit live in
  the project context (`work/bottom-chrome/build-plan.md`, `audit.md`). Open choices, each with a default
  taken from the mockups: Reader far left, idle Reader dimmed with an empty state, Reader returning to the
  screen you came from, the collapsed width fallback order, no Reader item in the iPad sidebar.
