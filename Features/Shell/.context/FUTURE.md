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
- `Features/DesignSystem/Chrome/SystemBars.swift`: leaving full screen in a light reading theme
  removes the overlay window, so the status bar pops back instead of fading. Keeping the window for
  a reading sheet's life made it fade, but the UI tests ran about 35 s slower with it; find a way
  that doesn't. The home indicator's auto-hide in full screen can't be seen on the Simulator: check
  it on a device.
- `Features/Reader/HTMLReadingView+Pages.swift`: a spoken sentence that crosses a page break keeps
  its page until the next sentence starts; the footer reads "in chapter" on web articles too.
- The lock screen (`MPNowPlayingInfo`) may name an untitled page's site twice (its title is
  `lineOne`, its subtitle the byline), as the bar did before it dropped the site.
- `ScrollPullHandoff`: a pan that begins with no movement counts as horizontal and can't pull the
  sheet. Synthesized probe touches can begin that way; check a slow pull from the text's top on a
  device.
