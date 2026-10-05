# Library screens: deferred

- Deleting (rows, *Delete Folder and Contents*, *Delete Book*) still removes audio before the save
  (`LibraryStore.deleteWithoutSaving`); a failed save brings the pages back without their audio.
  Route it through `LibraryAudioWork` after the save, as Replace does on `step/5-import`.
- *Playing from* a folder, Now Playing's *Contents* and the Sleep Timer are step 3 part B; the
  book screen's button already plays through `ChapterAdvance` (`LibraryStore.continueStart`).
- A series' link chapter opens in the browser; fetching it and opening the Reader (and its ▶
  fetch-then-play) comes with step 6's page fetcher, as does *Find Newer Chapters*.
- *Save Page* on a link row isn't offered (open the link and use 🔖 / ⋯); it needs a fetch that
  doesn't use the visible browser (step 6).
- The Move tree from inside the Favorites sheet replaces the sheet (one shell sheet at a time).
