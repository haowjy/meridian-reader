# Shell: deferred

- `Features/DesignSystem/Chrome/BottomChrome.swift`: at accessibility text sizes the glyphs
  inside the field capsule (mic, Jump, bookmark) and the reader's back control use an uncapped
  `.body` font and outgrow their 1.5×-capped frames. Cap the glyph size the same way, or let the
  frames grow further.
- `Features/Saved/SavedListView.swift`: the Library's grouped `List` keeps the system grouped
  background, which doesn't match paper in either mode. The step 4 Library screens replace it.
- `Features/Browse/BrowseStartView.swift` (`covered`): a layer under a sheet gets
  `allowsHitTesting(false)` and `accessibilityHidden(true)`, yet its elements still show in the
  XCUITest tree (two `readerClose` with Now Playing over another page's Reader; `NowPlayingUITests`
  taps ⌄ by label there). Check with VoiceOver on a device whether they are reachable; if so, find
  what keeps them exposed (an `accessibilityAddTraits(.isModal)` on `Sheet` didn't change the tree,
  and two stacked modal sheets would conflict).
