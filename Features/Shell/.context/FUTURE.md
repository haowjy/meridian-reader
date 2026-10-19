# Shell: deferred

- `Features/DesignSystem/Chrome/BottomChrome.swift`: at accessibility text sizes the glyphs
  inside the field capsule (mic, Jump, bookmark) and the reader's back control use an uncapped
  `.body` font and outgrow their 1.5×-capped frames. Cap the glyph size the same way, or let the
  frames grow further.
- `Features/Browse/BrowseStartView.swift` (`covered`): a layer under a sheet gets
  `allowsHitTesting(false)` and `accessibilityHidden(true)`, yet its elements still show in the
  XCUITest tree (the Reader's `readerClose` beside Now Playing's `nowPlayingClose` with Now
  Playing over another page's Reader). Check with VoiceOver on a device whether they are reachable; if so, find
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
