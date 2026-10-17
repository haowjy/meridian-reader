# Library screens: deferred

- Now Playing's *Contents* and the Sleep Timer are step 3 part B; folders and books already
  play through `ChapterAdvance` (`LibraryStore.continueStart`), and "Playing from" names the
  folder.
- A dragged row doesn't scroll the list when held near its edge (the drop zone is over the
  List, which no longer sees the drag): a long folder needs two drags, or Edit's handles.
- A link row (a favorite, a followed story's chapter waiting for its text) opens in the browser;
  opening it in the Reader would fetch it first (`FollowCenter.fill`), with a spinner on the row.
- *Save Page* on a favorite's link row isn't offered (open the link and use 🔖 / ⋯); it could
  fetch through `FollowCenter.fill` and the one queue.
