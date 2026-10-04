# Shell: deferred

- `Features/DesignSystem/Chrome/BottomChrome.swift`: at accessibility text sizes the glyphs inside the field
  capsule (mic, Jump, bookmark) and the reader's back control use an uncapped `.body` font and
  outgrow their 1.5×-capped frames. Cap the glyph size the same way, or let the frames grow further.
- `Features/Reader/ArticleReaderScreen.swift` (`navigationBarRow`): the pushed reader's title capsule in the navigation
  bar is content-sized; it could span the bar like the overlay's title row.
