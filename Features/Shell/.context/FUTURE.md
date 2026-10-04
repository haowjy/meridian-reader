# Shell: deferred

- `Features/DesignSystem/Chrome/BottomChrome.swift`: at accessibility text sizes the glyphs
  inside the field capsule (mic, Jump, bookmark) and the reader's back control use an uncapped
  `.body` font and outgrow their 1.5×-capped frames. Cap the glyph size the same way, or let the
  frames grow further.
- `Features/Saved/SavedListView.swift`: the Library's grouped `List` keeps the system grouped
  background, which doesn't match paper in either mode. The step 4 Library screens replace it.
