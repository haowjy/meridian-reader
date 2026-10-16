# Library screens: working notes

What the user sees is in `../../../docs/NAVIGATION.md` → "The Library". The model and its rules
(placement, deleting, `sortKey`) are `Core/Persistence/Library/` and `docs/TECHNICAL_SPEC.md`.

- **Screens read, `LibraryStore` writes.** Lists come from `@Query` with `LibraryQueries`; every
  change goes through `LibraryStore` (never `context.delete` here). What rows do is in
  `LibraryActions`, so a row and a header play and open the same way.
- **Play buttons ask `playState(of:)` and press through `press(_:start:)`** (`.page(key)` for rows,
  `.folder(id)` for a folder's button: a book's, or any folder whose pages play). Opening never
  plays; playing never navigates. `FolderProgress` is what a folder's row and header show (its
  place, how far, time left), for books and plain folders alike.
- **Drops don't reach a SwiftUI List** (on this iOS, neither `onDrop`, `dropDestination` nor
  `onInsert` fire over one). So rows only lift (`libraryDrag`, SwiftUI's `onDrag`, which hands
  over from the long-press menu natively) and report their frames (`libraryDropRow`); the
  surface lays a UIKit `UIDropInteraction` over itself while a row is dragged
  (`libraryDropZone`), finds the row under the drag on the screen on top (`LibraryScreenKey`),
  and files or places through `LibraryActions` (`file`, `place`) with `LibraryStore`'s refusals
  (`moveRefusal`). Its `sessionDidEnd` is what ends a drag. The zone takes only the drag's hit
  tests (`UIDragEvent`), never a touch: a row lifts as its long press opens the menu, and let go
  there no drag starts, so the next touch, with no drop session in, ends that lift.
- **A draggable row's open menu never lets XCUITest go idle** (the platform's lift and menu
  together; `.draggable` does the same): every UI action while the menu is up waits ~60 s. Tests
  that open a draggable row's menu take ~2 min each; run FolderUITests in two halves.
  The Library surface owns the zone and screen key.
- **Swipe actions follow AGENTS.md's rule.** A folder's *Delete* only asks, so it takes
  `Palette.destructive`: with the role, *Cancel* would leave the row missing and the delete abort
  in UIKit. A page's *Remove* takes the tint too: its row goes once the remove is stored, and a
  save that fails keeps it (a toast says so); with the role, the List would have taken the row
  out first and aborted on the update. `FolderDeleteUITests` checks both.
- **Which lists a page is in is `LibraryQueries`' alone** (in the Library, played without saving,
  or removed: in none). *Remove* stamps `removedAt`, so a played page doesn't come back as "Not
  saved" as it plays on (a listen from its article clears it, `recordPlayback`); a view never re-derives a list from `addedAt` or `lastPlayedAt` itself. The Downloads
  list follows the same line (`DownloadCenter` drops what left the Library after each stored
  edit, `LibraryStore.editStored`).
- **A saved delete reaches views one redraw early.** Rows, a folder's screen and a relationship's
  stale members still hold the deleted model for a redraw, and reading an attribute it hadn't
  loaded traps in SwiftData. Check `isLive` (`isDeleted` reads false again once the delete is
  saved): rows draw `DeletedRow`, a folder's screen `FolderGoneView`, and the home, folder
  screens and search keep only live models.
- **One ☆ for pages: `FavoriteFlow`** (the browser's, the Reader's and Now Playing's ⋯ by
  address, a row's menu by page): the same toasts, failure text and icon fetch everywhere, and
  every label reads `LibraryStore.isFavorite(_:)`. A row offers ☆ when the page is in the Library
  or has a web address (`LibraryStore.canFavorite(_:)`), so a chapter can be starred.
- **Edit and the dialogs live in `LibraryScreenState`**, on the Library surface, shared through
  the environment: the bottom bar acts on the selection, and
  `libraryDialogs` shows delete / rename / new folder once. The delete question is
  `FolderDeletePrompt` (unit-tested): one destructive choice, deleting with contents (no keep-contents choice, D18).
- **One ⋯ for the Library surface.** `LibraryScreenMenu` decides the rows and actions for the
  screen on top; the surface supplies its root and big-button actions.
- **Deletes, removes and Save go through `LibraryStore`'s audio journal** (`planDelete`,
  `planEphemeral`, `planSaved`): the audio changes only after the save, and a failed save is
  rolled back. Work that waited acts on the page as it is when it runs. Save also moves audio
  when an older page holds the address under another key (`ArticleSaveCoordinator` then rekeys
  the live session too, without a restart), or, for a page not playing, through
  `prepareListenIdentity` (legacy v1 adoption, alignment).
- **Edits can fail.** `LibraryStore`'s edits stage inside `edit(_:_:)`, which saves once and
  rolls back a failed save, throwing `LibraryStoreError.saveFailed`; nothing commits while an
  edit is staged. Call them through `shell.attempt("Couldn’t …") { try … }` (or
  `LibraryActions`, which does) and run what follows success (clearing Edit's selection,
  `onMoved`, `onDeleted`, closing the Move tree, a success toast) only when it returns non-nil;
  never `try?`. One user action is one store call, so it can't half-succeed (Remove passes all
  its pages to `remove(_:)`). Edit's *Remove* is the exception by design: the pages are removed
  first, then the folders after their question (`LibraryActions.removeSelection`,
  `deleteFolders`); the folders stay selected until their delete is saved.
- **The Move tree's pick reports success.** `MoveRequest.onPick` returns false when the change
  couldn't be saved, and the tree stays up (`MoveRequest.pick`); return true only once it is
  saved (the browser's *Save to Library…*, which extracts first, returns true and reports its own
  failure). `MoveTreeList` is the tree itself, shared with the import sheet's *Add to*: it hands
  a pick and a *New Folder* name to its caller, and both callers make the folder through
  `MoveTreeList.makeFolder` (`attempt`), so one that can't be saved picks nothing and leaves the
  tree up.
- **A book import is one edit.** `addBook` and `replaceBook` stage inside `edit`; the import
  sheet shows a failed save as its one-line failure (`BookImportError.couldNotSave`), not a
  toast. *Replace* stops the chapters it changes before it stages anything.
- **Rows for UI tests.** A row's title `Text` is its accessibility element (the status is its
  value; the rest is hidden). XCUITest still lists the texts under an element that ignores its
  children, so a combined element would answer to a title twice; tests find rows by title.
- **A folder row's link sits behind the row** (`LibraryFolderRow`): a `NavigationLink` as the
  row's content gets the List's own disclosure, at its own x. Behind the row the List draws
  none, a tap still follows it (and Edit's selection still takes the tap), and the row's own ›
  shares the ▶ column centred on the ⋯ slot (`ListRow.trailingColumnPadding`).
- **The home never changes size with playback** (decision D14): no section depends on what is
  playing or part-way. Pages played without saving (`LibraryQueries.playedNotSaved`) join
  *Pages* on their first play, which is the one insert playback causes, animated.
- **Download and Delete Downloads go through `DownloadCenter`** (`DownloadActions` for the toast):
  *Delete Downloads* also drops the page's or book's download, or the list would render it again.
  Rows offer *Download* only when that page or folder isn't downloading already
  (`DownloadCenter.isQueued`).
- **Headers sit on the page margin with the cards** (`FolderHeader`, `FolderPlayButtons`): the
  section header is already at the margin in a Library list, so the header adds no padding of its
  own; the bar and the button row span the width, so all four edges line up
  (`BookFolderUITests.testHeaderBlocksShareTheCardsEdges` checks them).
- **Books and series are folders** (decision D19): one screen (`FolderScreen`), one page row
  (`LibraryPageRow`), one ⋯ (`LibraryMenu.Screen.folder`), one delete question. Nothing refuses
  a move, a drop, a sort or a subfolder because of `kind`: only cycles (`LibraryTreeError`).
  `kind` is a hint of where a folder came from
  (`FolderKind.isBookOrSeries`): the row appearance comes from details; kind still supplies
  symbol, *Replace*'s lookup, a series' fetchable links, D7's trim, the bar's source. *Replace*
  finds a book's chapters through its record (`BookSourceState.chapterKeys`), written at import
  and *Replace*, and recorded once at launch for books stored before (`recordBookChapters`).
- **Details are not a kind** (decision D17): *Edit Details* (`FolderDetailsSheet`, a shell sheet)
  writes a folder's name, byline and cover in one `LibraryStore.setDetails`. `Folder.hasDetails`
  picks the header's look (`FolderHeaderStyle.detailed`), a book's too. `FolderPlayButtons` is
  the header's button row. UI tests read the look from `folderHeaderLook` (the cover tile is
  hidden from accessibility); `-pickTestCover` stands in for the Files picker.
- **Rows ask `DownloadCenter.isDownloaded`** (a page, or a folder with the pages its row already
  sorted) and `state(of:isDownloaded:)` for their Download control; `ListRow` only draws the
  `ListRow.Download` it is given.
- **Long lists stay cheap**: a row reads its stored paragraphs only when part-way
  (`PageProgress.of`); counts come from relationships, not fetches.
- **D20 home:** `LibraryHomeView` renders the Everything/Favorites tab (`ShellState.favoritesOnly`)
  over one folder/page collection, filtered by the band's search (`ShellState.librarySearch`,
  D22). Star flags never change location. Filtered (Favorites or a search), the list sets
  `LibraryScreenKey.filtered` and the rows read it: none lifts or takes a drop, a row in a folder
  shows the folder's path, and a folder row pushes `LibraryStore.path(to:)`, so ‹ goes to its
  parent as from anywhere else. Folder rows use large artwork; rows have Download and Play side by side. A folder
  header has Continue, From Start and Download.
- **D21: action rows never wrap; page rows are two lines.** A row of buttons is an
  `ActionButtonRow` (full labels → short titles → no details → symbols), never an HStack or a
  stack that can wrap; give every button a symbol. A page row is its title on one line and one
  status line; in a folder (`page.folder != nil`) it leaves out the byline the header shows. Imported pages are standard page rows; folder sort remains
  the source chapter order until the user changes it. The old Favorites folder is converted by
  `LibraryStore.migrateFavoritesFolder` before the first screen.
