# Library screens: deferred

- *Playing from* a folder, Now Playing's *Contents* and the Sleep Timer are step 3 part B; the
  book screen's button already plays through `ChapterAdvance` (`LibraryStore.continueStart`).
- A series' link chapter opens in the browser; fetching it and opening the Reader (and its ▶
  fetch-then-play) comes with step 6's page fetcher, as does *Find Newer Chapters*.
- *Save Page* on a link row isn't offered (open the link and use 🔖 / ⋯); it needs a fetch that
  doesn't use the visible browser (step 6).
- The Move tree from inside the Favorites sheet replaces the sheet (one shell sheet at a time).
- The Library's ⋯ has no *Debug* row (ux.md lists one): the listen debug panel presents only from
  Now Playing and the Reader. Needs the panel hosted where the Library can show it.
