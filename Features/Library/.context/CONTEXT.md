# Library screens: working notes

What the user sees is in `../../../docs/NAVIGATION.md` → "The Library". The model and its rules
(placement, deleting, `sortKey`) are `Core/Persistence/Library/` and `docs/TECHNICAL_SPEC.md`.

- **Screens read, `LibraryStore` writes.** Lists come from `@Query` with `LibraryQueries`; every
  change goes through `LibraryStore` (never `context.delete` here). What rows do is in
  `LibraryActions`, so a row and a header play and open the same way.
- **Rows and the header play through `LibraryActions`** (`play` → `press(_:start:)` with
  `.page(key)` for a page row's tap, `playFolder` with `.folder(id)` for the header's ▶ and
  *Continue*), and show `playState(of:)`. A page row's tap plays, except the page you hear, which
  opens (`open`: Now Playing), so a tap never pauses it; *Read* in its menu opens it. `FolderProgress` is what a folder's row and header show (its
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
  together; `.draggable` does the same): every UI action while the menu is up waits ~60 s, so
  a UI test or probe that opens a draggable row's menu takes minutes.
  The Library surface owns the zone and screen key.
- **Swipe actions follow AGENTS.md's rule.** A folder's *Delete* only asks, so it takes
  `Palette.destructive`: with the role, *Cancel* would leave the row missing and the delete abort
  in UIKit. A page's *Remove* takes the tint too: its row goes once the remove is stored, and a
  save that fails keeps it (a toast says so); with the role, the List would have taken the row
  out first and aborted on the update. `CoreFlowsUITests` swipe-removes a playing page, which stops.
- **The home's lists are `LibraryQueries`' too**: the starred folders (`favoriteFolders`), the
  top level's folders (`topLevel`, a filter after the fetch: no predicate on `parent`), and the
  search (`searchPages`, `searchFolders`). The home picks the descriptors in its `init` from the
  tab and the search text; it filters nothing itself but `isLive`.
- **Which lists a page is in is `LibraryQueries`' alone** (in the Library, played without saving,
  or removed: in none, nor the bar's resume, `lastPlayed`). *Remove* is one `LibraryStore.remove`
  from every path (rows, Edit, the Now Playing bar, and `PageActions`' 🔖 and ⋯ through
  `LibraryActions.remove`); it never clears the star or deletes. Once it is saved, the page you
  hear stops through the store's one playback hook (`stopPlaybackIfPlaying`, as a delete), and so
  does a session a waiting merge would move onto it (`keysWaitingToMerge`), so nothing shows a
  removed page playing. It stamps `removedAt`, so a played page doesn't come back
  in Recent (a listen from its article clears it, `recordPlayback`); a view never re-derives a list from `addedAt` or `lastPlayedAt` itself. The Downloads
  list follows the same line (`DownloadCenter` drops what left the Library after each stored
  edit, `LibraryStore.editStored`).
- **A saved delete reaches views one redraw early.** Rows, a folder's screen and a relationship's
  stale members still hold the deleted model for a redraw, and reading an attribute it hadn't
  loaded traps in SwiftData. Check `isLive` (`isDeleted` reads false again once the delete is
  saved): rows draw `DeletedRow`, a folder's screen `FolderGoneView`, and the home, folder
  screens and search keep only live models.
- **One ☆ for pages: `FavoriteFlow`** (the browser's, the Reader's and Now Playing's ⋯ by
  address, a row's menu by page): the same toasts, failure text and icon fetch everywhere, and
  every label reads `Page.isFavorite`, the one flag Favorites lists (`LibraryQueries.favoritePages`,
  in the Library or not). A row offers ☆ when the page is in the Library, has a web address, or is
  starred already (`LibraryStore.canFavorite(_:)`), so a chapter can be starred and unstarred.
- **Edit and the dialogs live in `LibraryScreenState`**, on the Library surface, shared through
  the environment: the bottom bar acts on the selection, and
  `libraryDialogs` shows delete / rename / new folder once. The start page's Favorites tiles
  hold one of their own (`BrowseStartView.favoritesScreen`), so a folder tile's *Rename…* and
  *Delete Folder…* ask there. The delete question is
  `FolderDeletePrompt` (unit-tested): one destructive choice, deleting with contents (no keep-contents choice, D18).
- **One ⋯ for the Library surface.** `LibraryScreenMenu` builds the panel's `MenuContext` for the
  screen on top: on a folder's screen the folder's own menu first (`FolderMenu.rows`), then the
  screen's rows, the same on the home and a folder.
- **Deletes, removes and Save go through `LibraryStore`'s audio journal** (`plan(.delete`,
  `.ephemeral` or `.saved, key:)`): the audio changes only after the save, and a failed save is
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
  saved (the browser's *Save to Folder…*, which extracts first, returns true and reports its own
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
  none, a tap still follows it (and Edit's selection still takes the tap), and the row's ⋯
  (a `Menu`, which takes its own taps) stays centred on the toolbar's ⋯ slot
  (`ListRow.trailingColumnPadding`).
- **One menu definition per item kind** (decision C4): `PageMenu` and `FolderMenu` are each one
  ordered `[MenuRow]` (`rows`), and every way to that item's menu renders it: as a view
  (`MenuRows`) in a row's ⋯ and `.contextMenu`, the folder header's *More*, a Favorites tile, a
  History visit, the Now Playing bar; as the item block of the ⋯ panel (the folder's screen, the
  Reader, Now Playing, the browser). A place passes a `PageMenu.Place`, which only hides or dims
  rows; its own rows go in a block after. Add a row in the definition, never at an entry point.
  They take their collaborators as values (`PageActions`, `LibraryActions`, `DownloadCenter`,
  `LibraryScreenState`), not from the environment, which a menu's content may not get, and build
  their rows only when shown (the views' bodies), not on each row redraw. In Edit a row passes no
  ⋯ (`ListRow.menu` nil). A page's actions are `PageActions`' ("this page" anywhere: a row's
  Library page, the Reader's article, the browser's page, which saves by extracting first).
- **The home never changes size with playback** (decision D14): no section depends on what is
  playing or part-way. A page played without saving joins Recent (`LibraryQueries.recent`) on
  its first play, the one insert playback causes, animated; Everything never changes with it.
- **Recent's menu rows ask `LibraryQueries.isInRecent`** (the `recent` predicate itself,
  evaluated on a page in hand; Recent's search writes the rule again, as a predicate can't call
  another on iOS 17): *Remove from Recent* dims on a page out of the Library that isn't in it, and a row's
  swipe offers *Remove* in the Library or in Recent. The tab's stored raw value stays `"history"`
  (`LibraryHomeTab.recent`, `library.homeTab`), so a remembered tab survives the rename.
  The browser's History (pages visited, 🕘 in the band) is another concept and keeps its name.
- **Download, Remove Download and Remove Downloads go through `DownloadCenter`**
  (`DownloadActions` for the toast): *Remove Download* (a page) and *Remove Downloads* (a folder's
  menu) also drop the download, or the list would render it again.
- **The folder header is centred and sits on the page margin** (`FolderHeader`, a design-system
  component of plain values; `FolderScreen` fills it): the section header is already at the
  margin in a Library list, so the header adds no padding of its own. Its Download control's
  taps (download, or ask *Turn Off Download* while the toggle is on) are `FolderScreen`'s
  `headerActions`; the ▶ is `playFolder`; *More* is `FolderMenu`, as the top of the screen's ⋯ is. The *Turn Off Download*
  question is one modifier, `turnOffDownloadQuestion`, attached by each control that asks it
  (a confirmation dialog points its iOS 26 popover at the view it is attached to): the header's
  Download control and *More* (`FolderHeader`'s `anchor` slot, behind each side control), a
  folder row's ⋯ (`ListRow.menuAnchor`; its long press asks there too) and the band's ⋯
  (`LibrarySurface`). Each host keeps the folder being asked about in its own `@State`, so only
  that one presents; `FolderMenu` reports the tap through `onTurnOffDownload`.
- **Books and series are folders** (decision D19): one screen (`FolderScreen`), one page row
  (`LibraryPageRow`), one ⋯ (`FolderMenu`), one delete question. Nothing refuses
  a move, a drop, a sort or a subfolder because of `kind`: only cycles, and a page out of the
  Library, which has no place in the tree (`LibraryTreeError`).
  `kind` is a hint of where a folder came from
  (`FolderKind.isBookOrSeries`): the row appearance comes from details; kind still supplies
  symbol, *Replace*'s lookup, a followed story's (`series`) waiting chapters, D7's trim, the bar's source. *Replace*
  finds a book's chapters through its record (`BookSourceState.chapterKeys`), written at import
  and *Replace*, and recorded once at launch for books stored before (`recordBookChapters`).
- **Details are not a kind** (decision D17): *Edit Details* (`FolderDetailsSheet`, a shell sheet)
  writes a folder's name, byline and cover in one `LibraryStore.setDetails`. `Folder.hasDetails`
  picks the header's look (`FolderHeaderStyle.detailed`: the cover above the title), a book's too.
- **Rows, the page menu and the header ask `DownloadCenter.state(of:)`** (a page; a folder with
  the pages its row or screen already holds) for the one `DownloadState`; `ListRow` only draws
  the mark it is given (dimmed tile and ↓ while downloading, ✓ badge once downloaded).
- **Long lists stay cheap**: a row reads its stored paragraphs only when part-way
  (`PageProgress.of`); counts come from relationships, not fetches.
- **D20 home:** `LibraryHomeView` renders the Everything / Favorites / Recent tab
  (`ShellState.homeTab`, a `LibraryHomeTab`) over one folder/page collection, filtered by the
  band's search within that tab (`ShellState.librarySearch`, D22; `LibraryQueries.searchPages(_:in:)`).
  Star flags never change location. Filtered (Favorites, Recent or a search), the list sets
  `LibraryScreenKey.filtered` and the rows read it: none lifts or takes a drop, a row in a folder
  shows the folder's path, and a folder row pushes `LibraryStore.path(to:)`, so ‹ goes to its
  parent as from anywhere else. Rows have only ⋯ at their trailing edge. A folder
  header has Download, the big ▶ (Continue) and More.
- **D21: action rows never wrap; page rows are two lines.** A row of buttons is an
  `ActionButtonRow` (full labels → short titles → no details → symbols), never an HStack or a
  stack that can wrap; give every button a symbol. A page row is its title on one line and one
  status line; in a folder (`page.folder != nil`) it leaves out the byline the header shows. Imported pages are standard page rows; folder sort remains
  the source chapter order until the user changes it. The old Favorites folder is converted by
  `LibraryStore.migrateFavoritesFolder` before the first screen.
