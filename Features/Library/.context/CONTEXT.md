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
  `libraryDialogs` shows delete / rename / new folder once.
- **Rows for UI tests.** A row's title `Text` is its accessibility element (the status is its
  value; the rest is hidden). XCUITest still lists the texts under an element that ignores its
  children, so a combined element would answer to a title twice; tests find rows by title.
- **Long lists stay cheap**: a row reads its stored paragraphs only when part-way
  (`PageProgress.of`); counts come from relationships, not fetches.
