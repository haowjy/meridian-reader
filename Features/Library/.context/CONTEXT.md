# Library screens: working notes

What the user sees is in `../../../docs/NAVIGATION.md` → "The Library". The model and its rules
(placement, deleting, `sortKey`) are `Core/Persistence/Library/` and `docs/TECHNICAL_SPEC.md`.

- **Screens read, `LibraryStore` writes.** Lists come from `@Query` with `LibraryQueries`; every
  change goes through `LibraryStore` (never `context.delete` here). What rows do is in
  `LibraryActions`, so a row, a card and a header play and open the same way.
- **Play buttons ask `playState(of:)` and press through `press(_:start:)`** (`.page(key)` for rows,
  `.folder(id)` for a book's button). Opening never plays; playing never navigates.
- **Edit and the dialogs live in `LibraryScreenState`**, one per surface (the Library, the
  Favorites sheet), shared through the environment: the bottom bar acts on the selection, and
  `libraryDialogs` shows delete / rename / new folder once. The delete question is
  `FolderDeletePrompt` (unit-tested): never *Folder Only* when a book or series is selected.
- **One ⋯ for both surfaces.** `LibraryScreenMenu` decides the rows and actions for the screen on
  top; `LibrarySurface` and `FavoritesSheet` each supply their root and big-button actions. A
  system sheet hosts its own morph panel (`moreMenuHost`), since the shell's sits under sheets.
- **Deletes, removes and Save go through `LibraryStore`'s audio journal** (`planDelete`,
  `planEphemeral`, `planSaved`): the audio changes only after the save, and a failed save is
  rolled back. Save moves audio only when an older page holds the address under another key
  (`ArticleSaveCoordinator` then rekeys the live session too, without a restart).
- **Edits can fail.** `LibraryStore`'s edits roll back a failed save and throw
  `LibraryStoreError.saveFailed`. Call them through `shell.attempt("Couldn’t …") { try … }` (or
  `LibraryActions`, which does) and run what follows success (clearing Edit's selection,
  `onMoved`, `onDeleted`, closing the Move tree, a success toast) only when it returns non-nil;
  never `try?`. One user action is one store call, so it can't half-succeed (Remove passes all
  its pages to `remove(_:)`). Edit's *Remove* is the exception by design: the pages are removed
  first, then the folders after their question (`LibraryActions.removeSelection`,
  `deleteFolders`); the folders stay selected until their delete is saved.
- **The Move tree's pick reports success.** `MoveRequest.onPick` returns false when the change
  couldn't be saved, and the tree stays up (`MoveRequest.pick`); return true only once it is
  saved (the browser's *Save to Library…*, which extracts first, returns true and reports its own
  failure).
- **Rows for UI tests.** A row's title `Text` is its accessibility element (the status is its
  value; the rest is hidden). XCUITest still lists the texts under an element that ignores its
  children, so a combined element would answer to a title twice; tests find rows by title.
- **Long lists stay cheap**: a row reads its stored paragraphs only when part-way
  (`PageProgress.of`); counts come from relationships, not fetches.
