# Library screens: deferred

- Now Playing's *Contents* and the Sleep Timer are step 3 part B; folders and books already
  play through `ChapterAdvance` (`LibraryStore.continueStart`), and "Playing from" names the
  folder.
- A dragged row doesn't scroll the list when held near its edge (the drop zone is over the
  List, which no longer sees the drag): a long folder needs two drags, or Edit's handles.
- A series' link chapter opens in the browser; fetching it and opening the Reader (and its ▶
  fetch-then-play) comes with step 6's page fetcher, as does *Find Newer Chapters*.
- *Save Page* on a link row isn't offered (open the link and use 🔖 / ⋯); it needs a fetch that
  doesn't use the visible browser (step 6).
- The Move tree from inside the Favorites sheet replaces the sheet (one shell sheet at a time).
