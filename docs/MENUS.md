# Menus

Every menu option is defined once, in `MenuRegistry` (`Features/DesignSystem/Components/MenuRegistry.swift`, decision C98). An option's spec says:

- **kind**: article, folder, prepare or screen;
- **places**: where it can ever show (`row`, `tile`, `bar`, `history`, `reader`, `nowPlaying`, `browser`, `header`, `libraryHome`, `folderScreen`, `prepared audio`);
- **applies**: a fact about the item that no state change in that place undoes (an article in no folder never gets *Playback ›*; an article in the Library never gets *Remove from Recent*); false hides it;
- **enabled**: whether it can run now; false greys it out;
- order (the spec order), block (a divider before block 1) and parent (a submenu).

**Grey or hidden (DR-09, refined by C99):** grey when some other state could make the option usable in that place for that item; hidden when nothing could. It's judged per menu and per option. The generated table below lists every case.

Every menu is assembled from the registry by kind and place (`MenuRegistry.rows` / `blocks`); a menu file (`ArticleMenu`, `FolderMenu`, `PrepareMenu`, `MenuContext.screenRows`) only gives each option its title, symbol and action. Menus are built only when they open: a list row hands its menu over as a view and never reads its rows; a row's swipe uses `ArticleMenu.swipe` / `FolderMenu.swipe`, which read only the item's flags. `PrepareCenter.hasPreparedAudio(_:articles:)` caches its disk checks per page until a prepare changes. `RenderTiming` (signposts plus a 5 s `render_timing` log line) measures row bodies and menu builds.

`MenuRegistryTests` checks the table: kind × place × state → shown options in order, greyed or not.

## The menus (C98)

- **Page** (row ⋯ and long press, Favorites tile, Now Playing bar, History, Reader, Now Playing, browser): Read (from the Library: in place, no destination switch), Prepare / Remove Prepared Audio, Voice: <name> (C138), Favorites, Move to… / Save to Folder…, Mark as Finished, Playback › (Mark All Above as Finished in a list row, Skip in Playback; a page in a folder only), Share, Save / Remove from Library (not in the Reader, Now Playing or the browser: the bookmark is there), Remove from Recent (out of the Library). The bar adds Stop Listening, History adds Remove from History, and Now Playing has Go to <folder> instead of Read.
- **Folder** row and tile (an imported EPUB or followed story is a folder too, the same menu: C100): Continue, Prepare / Turn Off Prepare / Remove Prepared Audio (one row by state), Voice: <name> (a book or series only, C138), Favorites, Move to…, Edit Details… (holds the name), Delete.
- **Folder header More**: Play from Start, Remove Prepared Audio, Voice: <name> (a book or series), Favorites, Move to…, Edit Details…, Delete, then the create group into this folder (C126).
- **Library home ⋯**: Sort ›, Prepared Audio, then [Settings][Saved][Listen], with [History] before Listen on compact width (regular width has 🕘). Listen goes to Now Playing when audio is playing, greyed otherwise. Saved opens the Library home (already there: harmless).
- **Folder screen ⋯**: Sort ›, Prepared Audio, then [Settings][Saved][Listen], with [History] before Listen on compact width (regular width has 🕘). Listen goes to Now Playing when audio is playing, greyed otherwise.
- **Create group** (C126, `LibraryCreateMenu`, one definition at `.add` and `.edit`): New Folder…, Import from… (the EPUB/PDF file picker), Paste Text… (a sheet: optional title, the text, prefilled from the clipboard; Save makes a text article here; never grey, C127). Shown by ＋ (Library home and folder screen), a folder header's More and Edit's ＋; shown in every folder including imported EPUBs and followed stories (C149). Follow… and Save from Website… are not here; users do those from the browser.
- **Folder header More** ends with Delete Folder… alone at the bottom, after the create group (C130). Mark as Finished uses the outline `checkmark.circle` (C130).
- **Edit bar** (folder screen in Edit): Move to… (slot 1), Mark as Finished (middle), ＋ (slot 4: the create group; its New Folder… files the selection into the new folder, C122), Remove.
- **Reader / Now Playing ⋯**: on compact width the chrome's ⋯ (`ReadingPageMoreButton`), at regular width the transport's: the article's options, then Prepared Audio, then [Settings][Saved][Listen], with [History] before Listen on compact width (regular width has 🕘). Listen is disabled (already there). Website stays reachable via Share in the article's own rows. Favorites stays reachable from the item's own menu row and from the Library's Favorites tab; it leaves the tile row (C140).
- **Browser ⋯**: the page's options, then Follow…, Reload, Prepared Audio, then [Settings][Saved][Reader], with [History] before Reader on compact width (regular width has 🕘). Reader opens the current page in the Reader (greyed when the page isn't readable). No New Search: a tap on the address field starts one.
- **Prepare on a page out of the Library** (C104): enabled; it saves the page to the Library's top level first. Grey only on a browser page not yet loaded as a page.
- **Prepared Audio row** (one article, C110): Prepare Again (that article), Remove Prepared Audio (that article). Pause All in the section header; a folder's prepare is turned off on its screen.

- **Voice: <name>** (C138, C138a, `menuVoice`): the voice the article speaks in, engine included ("Heart", "Ava (Apple)", "Apple" for the best Apple voice) (its book's for a chapter; the one in Settings while it has no audio yet). It opens the voice picker (`VoicePickerSheet`, the one voice switcher `VoiceSelectionList`, engines as sections): picking another asks first when there is audio (how much prepared audio is made again and how much audio from listening is cleared), then remakes it in that voice.

## Grey / hidden table (generated by `MenuRegistry.table`)

### article at row

| Option | Hidden when | Greyed when |
|---|---|---|
| read | never | no page or address |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | Apple's voice is selected |
| favorite | never | it can’t be starred |
| move | never | nothing to save yet |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › markAllAbove | not in a folder; outside a list row | not saved |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| save | never | nothing to save yet |
| removeFromRecent | in the Library | not in Recent |

### article at tile

| Option | Hidden when | Greyed when |
|---|---|---|
| read | never | no page or address |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | Apple's voice is selected |
| favorite | never | it can’t be starred |
| move | never | nothing to save yet |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| save | never | nothing to save yet |
| removeFromRecent | in the Library | not in Recent |

### article at bar

| Option | Hidden when | Greyed when |
|---|---|---|
| read | never | no page or address |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | Apple's voice is selected |
| favorite | never | it can’t be starred |
| move | never | nothing to save yet |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| save | never | nothing to save yet |
| removeFromRecent | in the Library | not in Recent |
| stopListening | never | nothing loaded |

### article at history

| Option | Hidden when | Greyed when |
|---|---|---|
| read | never | no page or address |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | Apple's voice is selected |
| favorite | never | it can’t be starred |
| move | never | nothing to save yet |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| save | never | nothing to save yet |
| removeFromRecent | in the Library | not in Recent |
| removeFromHistory | never | never |

### article at reader

| Option | Hidden when | Greyed when |
|---|---|---|
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | Apple's voice is selected |
| favorite | never | it can’t be starred |
| move | never | nothing to save yet |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| removeFromRecent | in the Library | not in Recent |

### article at nowPlaying

| Option | Hidden when | Greyed when |
|---|---|---|
| goTo | never | nowhere to go |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | Apple's voice is selected |
| favorite | never | it can’t be starred |
| move | never | nothing to save yet |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| removeFromRecent | in the Library | not in Recent |

### article at browser

| Option | Hidden when | Greyed when |
|---|---|---|
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | Apple's voice is selected |
| favorite | never | it can’t be starred |
| move | never | nothing to save yet |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| removeFromRecent | in the Library | not in Recent |

### folder at row

| Option | Hidden when | Greyed when |
|---|---|---|
| continueFolder | never | nothing in it plays |
| folderPrepare | never | empty, nothing downloaded, toggle off |
| folderVoice | a plain folder (each article keeps its own voice) | Apple's voice is selected |
| folderFavorite | never | never |
| folderMove | never | never |
| editDetails | never | never |
| deleteFolder | never | never |

### folder at tile

| Option | Hidden when | Greyed when |
|---|---|---|
| continueFolder | never | nothing in it plays |
| folderPrepare | never | empty, nothing downloaded, toggle off |
| folderVoice | a plain folder (each article keeps its own voice) | Apple's voice is selected |
| folderFavorite | never | never |
| folderMove | never | never |
| editDetails | never | never |
| deleteFolder | never | never |

### folder at header

| Option | Hidden when | Greyed when |
|---|---|---|
| playFromStart | never | nothing in it plays |
| removePreparedAudio | never | nothing downloaded or downloading |
| folderVoice | a plain folder (each article keeps its own voice) | Apple's voice is selected |
| folderFavorite | never | never |
| folderMove | never | never |
| editDetails | never | never |
| deleteFolder | never | never |

### prepare at preparedAudio

| Option | Hidden when | Greyed when |
|---|---|---|
| reprepare | audio from listening | still preparing |
| removePrepare | never | never |

### screen at reader

| Option | Hidden when | Greyed when |
|---|---|---|
| preparedAudio | never | never |

### screen at nowPlaying

| Option | Hidden when | Greyed when |
|---|---|---|
| preparedAudio | never | never |

### screen at browser

| Option | Hidden when | Greyed when |
|---|---|---|
| follow | never | browser: no web page up |
| reload | never | no page up |
| preparedAudio | never | never |

### screen at libraryHome

| Option | Hidden when | Greyed when |
|---|---|---|
| sort | the folder keeps its own order (imported, followed) | never |
| preparedAudio | never | never |

### screen at folderScreen

| Option | Hidden when | Greyed when |
|---|---|---|
| sort | the folder keeps its own order (imported, followed) | never |
| preparedAudio | never | never |

### screen at preparedAudio

| Option | Hidden when | Greyed when |
|---|---|---|
| deleteAllPrepared | nothing prepared | never |
| clearListeningAudio | no audio from listening | never |

### screen at add

| Option | Hidden when | Greyed when |
|---|---|---|
| newFolder | the folder keeps its own order (imported, followed) | never |
| importFile | the folder keeps its own order (imported, followed) | never |
| pasteText | the folder keeps its own order (imported, followed) | never |

### screen at edit

| Option | Hidden when | Greyed when |
|---|---|---|
| newFolder | the folder keeps its own order (imported, followed) | never |
| importFile | the folder keeps its own order (imported, followed) | never |
| pasteText | the folder keeps its own order (imported, followed) | never |

## Prepared Audio list ⋯ (C135)

| Option | Shown | Does |
|---|---|---|
| deleteAllPrepared (*Delete All…*) | something is prepared | confirms, then deletes every prepared article and its audio; folders stay |
| clearListeningAudio (*Clear Audio From Listening…*) | From Listening has rows | confirms, then deletes that audio only |

Row menu: *Delete Audio* (`menuDeleteAudio`) on every row; *Prepare Again* only on prepared rows (*Keep* is gone, C138: audio not in its article's voice never plays).

## Bottom-chrome glossary (C143)

The names for the chrome that runs along the bottom of every screen.

*On compact width the chrome host (`ChromeHost`, `docs/NAVIGATION.md` "Bottom chrome") draws the field, the pill, ▶ and ⋯; the ＋ rows are rows of its ⋯ and *History* a tile of it (`MenuContext.tiles`). `SurfaceBand` and the five-slot `BottomToolbarLayout` rows below are regular width's. Still planned (PR2 to PR4): the ⋯ panel sectioned with Settings first, growing out of the glass.*

| Name | Kind | What it is |
|---|---|---|
| `ChromeHost` | view | Compact width only: the one chrome above the Library, the browser and the Reader: two rows expanded, one collapsed, over `ChromeScreen`s from each destination. |
| `ChromeScreen` | struct | What a destination hands the host: its field, ‹ › callbacks and ids, ⋯ and edit bar. |
| `ChromeState` | struct | What the chrome shows: destination, collapse progress, `fullScreen`, played, history, keyboard, reader mode. |
| `ChromeScroll` | class | The one scroll controller: a continuous progress from scroll reports (90 pt a travel, snap at rest); `expand()` is the icon tap and a new page. |
| `ChromeLayout` | struct | The rect and opacity of every piece for a width and a `ChromeState` (the mockups' `rectsFor` and width table), sized by `ChromeMetrics`. |
| `ChromePieces` | view | Draws the pieces from a `ChromeLayout`; animatable in the progress. |
| `ChromeCard` | struct, preference | The Reader's or Now Playing's player card and ⋯ rows, handed to the host. |
| `ChromeSkin` | enum | `.system` (everything else), `.glass` (iOS 26), `.material` (earlier iOS, and `-chromeFallback`). |
| `SurfaceBand` | view | The regular-width address / search field with its ✕ while searching. |
| `ChromeMetrics` | enum (constants) | The compact chrome's one token set (`DesignSystem/Chrome`): heights, gaps, margins, the lit inset. |
| `BottomChrome` | enum (constants) | Control sizes both widths share (glyph, tap target, field, discs). |
| `BottomToolbarLayout` | layout | 5-slot evenly-spaced grid for regular width's toolbar rows (browser, Library, Now Playing transport). |
| `PlayerCard` | enum | Shared constants (artwork size, progress height) and the flat card surface for `NowPlayingBar`. |
| `NowPlayingBar` | view | The compact flat card (artwork, title, groove progress line, play/pause) on the `PlayerCard` surface (no shadow), in `SurfaceBand`'s top row. |
| `NowPlayingBarView` | view | The same card in the Reader's band; hides on Now Playing and while sheets are up. |
| `ReaderPlayerCard` | view | The compact Reader's and Now Playing's 152 pt card (art, title, Voice, Save, scrubber, transport), drawn by the chrome host on its glass. |
| `ReadingBottomBand` | view | The bottom band of the Reader and Now Playing: integrated controls flat on the page background, separated by a hairline divider. |
| `ReadingPage` | view | A reading page in place (compact) or in a `Sheet` (regular), laid out by `ReadingBars`. |
| `ReaderSheet` | view | The Reader's page: its band and Listen over `ReadingPage`. |
| `NowPlayingSheet` | view | Now Playing's page over `ReadingPage`. |
| `NowPlayingControls` | view | Status notes (buffering, language, debug) in Now Playing's band. |
| `ListenTransportView` | view | Speech-bound wrapper for `NowPlayingTransport` (skips, play/pause disc) with swipe gesture. |
| `NowPlayingTransport` | view | The 5-slot transport row component: skip-back, play/pause disc (52 pt), skip-forward. |
| `ReaderScrubRow` | view | The scrub bar in the bottom band (Now Playing: live; Reader: position 0). |
| `RoundIconButton` | view | The app's one round icon button (36 pt, field fill, hairline, 18 pt medium glyph via `roundFieldControl`): Voice, Aa, ☝︎. The card's bookmark (`SaveToggleButton(round:)`) and speed (`SpeedButton(round:)`) use the same face. |
