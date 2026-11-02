# Menus

Every menu option is defined once, in `MenuRegistry` (`Features/DesignSystem/Components/MenuRegistry.swift`, decision C98). An option's spec says:

- **kind**: article, folder, prepare or screen;
- **places**: where it can ever show (`row`, `bar`, `history`, `reader`, `nowPlaying`, `browser`, `header`, `libraryHome`, `folderScreen`, `prepared audio`);
- **applies**: a fact about the item that no state change in that place undoes (an article in no folder never gets *Playback ›*; an article in the Library never gets *Remove from History* (the tab)); false hides it;
- **enabled**: whether it can run now; false greys it out;
- order (the spec order), block (a divider before block 1) and parent (a submenu).

**Grey or hidden (DR-09, refined by C99):** grey when some other state could make the option usable in that place for that item; hidden when nothing could. It's judged per menu and per option. The generated table below lists every case.

Every menu is assembled from the registry by kind and place (`MenuRegistry.rows` / `blocks`); a menu file (`ArticleMenu`, `FolderMenu`, `PrepareMenu`, `MenuContext.screenRows`) only gives each option its title, symbol and action. Menus are built only when they open: a list row hands its menu over as a view and never reads its rows; a row's swipe uses `ArticleMenu.swipe` / `FolderMenu.swipe`, which read only the item's flags. `PrepareCenter.hasPreparedAudio(_:articles:)` caches its disk checks per page until a prepare changes. `RenderTiming` (signposts plus a 5 s `render_timing` log line) measures row bodies and menu builds.

`MenuRegistryTests` checks the table: kind × place × state → shown options in order, greyed or not.

## The menus (C98)

- **Page** (row ⋯ and long press, Now Playing bar, Browsing History, Reader, Library Read, Listen, browser): first, as its own group everywhere, Save to Library / Remove from Library, Save to Folder… / Move to…, Follow… (only for a page with a web address, which can belong to a story; greyed while the page is being extracted; it opens the Follow sheet on the page's address); then Read (from the Library: in place, no destination switch), Prepare / Remove Prepared Audio, Voice: <Default or library> (C138), Mark as Finished, Playback › (Mark All Above as Finished in a list row, Skip When Playing; a page in a folder only), Share, Remove from History (the Library's History tab; out of the Library). The reading pages keep their 🔖 as well. The bar adds Stop Listening, a Browsing History visit adds its own Remove from Browsing History, and Listen has Go to <folder> instead of Read. Listen (`nowPlaying`) keeps to the save group, then Go to, Mark as Finished, then Share in a block of its own: Voice is on its card, and Prepare, Voice, Playback and Remove from Recent are left out.
- **Folder** row (an imported EPUB or followed story is a folder too, the same menu: C100): Continue, Prepare / Stop Preparing / Remove Prepared Audio (one row by state), Voice: <Default or library> (a book or series only, C138), Move to…, Edit Details… (holds the name), Delete Folder… (Delete Book… on a book).
- **Folder header More**: Play from Start, Remove Prepared Audio, Voice: <Default or library> (a book or series), Move to…, Edit Details…, Delete Folder… (Delete Book… on a book), then the create group into this folder (C126).
- **Library home ⋯**: Sort ›, Prepared Audio, then [Settings][Library][Listen]; on compact width (the title line's ⋯, a system menu) the create group first, then Sort ›, Prepared Audio, Library, Browsing History, Listen (no Settings: the chrome's pill has it; regular width has 🕘). Listen opens Listen when audio is playing, greyed otherwise. Library opens the Library home (already there: harmless).
- **Folder screen ⋯**: Sort ›, Prepared Audio, then [Settings][Library][Listen]; on compact width (beside Edit in the navigation bar) as the Library home's.
- **Library Read ⋯** (compact width: the top group's ⋯ and a press and hold on the field's reader icon, `LibraryChrome.readingMenu`): the page's options at `reader`, then the Library's compact rows as above. Listen opens Listen when audio is playing, greyed otherwise.
- **Create group** (C126, `LibraryCreateMenu`, one definition at `.add` and `.edit`): New Folder…, Import from… (the EPUB/PDF file picker), Paste Text… (a sheet: optional title, the text, prefilled from the clipboard; Save makes a text article here; never grey, C127). Add Link… (an alert: the address, prefilled from the clipboard; Save keeps it here as a link page, its text fetched when it first plays; never grey). Shown by ＋ (Library home and folder screen), a folder header's More and Edit's ＋; shown in every folder including imported EPUBs and followed stories (C149). Follow… is not here: it is a page's option (and the Library's ＋ tile *Follow a Site*).
- **Folder header More** ends with Delete Folder… (Delete Book… on a book) alone at the bottom, after the create group (C130). Mark as Finished uses the outline `checkmark.circle` (C130).
- **Edit bar** (folder screen in Edit): Move to… (slot 1), Mark as Finished (middle), ＋ (slot 4: the create group; its New Folder… files the selection into the new folder, C122), Remove.
- **Reader / Listen ⋯** (`ReadingPageMoreButton`, the transport's ⋯ at regular width): the article's options, then the Reader's Prepared Audio, then [Settings][Library][Listen]. Listen is disabled (already there). Website stays reachable via Share in the article's own rows.
- **Listen ⋯** (compact width, the top group's `listenMore`): a system menu, no tiles: the article's options at `nowPlaying` (Save / Remove, Save to Folder… / Move to…, Follow…; Go to …, Mark as Finished; Share), a section each, then Listen's own *Play from a Paragraph*.
- **Browser ⋯**: the page's options (Save, Save to Folder… and Follow… first), then Reload, Prepared Audio, then [Settings][Library][Reader] (regular width has 🕘). Reader opens the current page in the Reader (greyed when the page isn't readable). No New Search: a tap on the address field starts one. Compact width has no ⋯: a press and hold on the field's leading glyph (the reader icon, or 🔍) opens Open in Reader (Show Web Page), Listen, then the page's options, the screen's rows, Library and Browsing History.
- **Settings ⋯** (compact width, its title line): Library, Browsing History, Listen (Settings has no rows of its own).
- **Prepare on a page out of the Library** (C104): enabled; it saves the page to the Library's top level first. Grey only on a browser page not yet loaded as a page.
- **Prepared Audio row** (one article, C110): Prepare Again (that article), Remove Prepared Audio (that article). Pause All in the section header; a folder's prepare is turned off on its screen.

- **Voice: <Default or library>** (C138, C138a, `menuVoice`): the voice the article speaks in, said as Settings › Voice says it, never by the voice's own name: "Voice: Default" while it is the built-in default, else its voice library ("Voice: Kokoro") (`LocalTTSCoordinator.voiceSummary`; its book's for a chapter; the one in Settings while it has no audio yet). It opens the voice picker (`VoicePickerSheet`, the one voice switcher `VoiceSelectionList`, engines as sections; only its rows name voices): picking another asks first, "Change the Voice?", when there is audio (how much prepared audio is made again and how much audio from listening is made again as it plays; audio in the current voice is kept 7 days, so changing back plays it at once), then downloads the voice if it isn't on the device (its row shows the download and the ✓ stays until it is there; a failed download says *Couldn’t download* on its row) and changes it to that voice; a change the library can't save says "Couldn’t change the voice. Nothing was changed." Voices are removed in Settings › Voice, not here.

## Grey / hidden table (generated by `MenuRegistry.table`)

### article at row

| Option | Hidden when | Greyed when |
|---|---|---|
| save | never | nothing to save yet |
| move | never | nothing to save yet |
| follow | no web address (it can't belong to a story) | the page is being extracted |
| read | never | no page or address |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | never |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › markAllAbove | not in a folder; outside a list row | not saved |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| removeFromRecent | in the Library | not in Recent |

### article at bar

| Option | Hidden when | Greyed when |
|---|---|---|
| save | never | nothing to save yet |
| move | never | nothing to save yet |
| follow | no web address (it can't belong to a story) | the page is being extracted |
| read | never | no page or address |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | never |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| removeFromRecent | in the Library | not in Recent |
| stopListening | never | nothing loaded |

### article at history

| Option | Hidden when | Greyed when |
|---|---|---|
| save | never | nothing to save yet |
| move | never | nothing to save yet |
| follow | no web address (it can't belong to a story) | the page is being extracted |
| read | never | no page or address |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | never |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| removeFromRecent | in the Library | not in Recent |
| removeFromHistory | never | never |

### article at reader

| Option | Hidden when | Greyed when |
|---|---|---|
| save | never | nothing to save yet |
| move | never | nothing to save yet |
| follow | no web address (it can't belong to a story) | the page is being extracted |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | never |
| finished | never | not saved |
| playback | not in a folder | neither row inside can run |
| playback › skip | not in a folder | not saved and not a waiting chapter |
| share | no web address | never |
| removeFromRecent | in the Library | not in Recent |

### article at nowPlaying

| Option | Hidden when | Greyed when |
|---|---|---|
| save | never | nothing to save yet |
| move | never | nothing to save yet |
| follow | no web address (it can't belong to a story) | the page is being extracted |
| goTo | never | nowhere to go |
| finished | never | not saved |
| share | no web address | never |

### article at browser

| Option | Hidden when | Greyed when |
|---|---|---|
| save | never | nothing to save yet |
| move | never | nothing to save yet |
| follow | no web address (it can't belong to a story) | the page is being extracted |
| prepare | never | nothing to save yet (downloading saves it, C104) |
| voice | no page (a page in the browser only) | never |
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
| folderVoice | a plain folder (each article keeps its own voice) | never |
| folderMove | never | never |
| editDetails | never | never |
| deleteFolder | never | never |

### folder at header

| Option | Hidden when | Greyed when |
|---|---|---|
| playFromStart | never | nothing in it plays |
| removePreparedAudio | never | nothing downloaded or downloading |
| folderVoice | a plain folder (each article keeps its own voice) | never |
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

### screen at browser

| Option | Hidden when | Greyed when |
|---|---|---|
| reload | never | no page up |
| preparedAudio | never | never |

### screen at libraryHome

| Option | Hidden when | Greyed when |
|---|---|---|
| sort | never | never |
| preparedAudio | never | never |

### screen at folderScreen

| Option | Hidden when | Greyed when |
|---|---|---|
| sort | never | never |
| preparedAudio | never | never |

### screen at preparedAudio

| Option | Hidden when | Greyed when |
|---|---|---|
| deleteAllPrepared | nothing prepared | never |
| clearListeningAudio | no audio from listening | never |

### screen at add

| Option | Hidden when | Greyed when |
|---|---|---|
| newFolder | never | never |
| importFile | never | never |
| pasteText | never | never |
| addLink | never | never |

### screen at edit

| Option | Hidden when | Greyed when |
|---|---|---|
| newFolder | never | never |
| importFile | never | never |
| pasteText | never | never |
| addLink | never | never |

## Prepared Audio list ⋯ (C135)

| Option | Shown | Does |
|---|---|---|
| deleteAllPrepared (*Delete All…*) | something is prepared | confirms, then deletes every prepared article and its audio; folders stay |
| clearListeningAudio (*Clear Audio from Listening…*) | From Listening has rows | confirms, then deletes that audio only |

Row menu: *Delete Audio* (`menuDeleteAudio`) on every row; *Prepare Again* only on prepared rows (*Keep* is gone, C138: audio not in its article's voice never plays).

## Bottom-chrome glossary (C143)

The names for the chrome that runs along the bottom of every screen.

*On compact width the chrome host (`ChromeHost`, `docs/NAVIGATION.md` "Bottom chrome") draws the field, Listen and the `[Library | Browser | Settings]` pill, and no ⋯: the screens' ⋯ are on their title lines (the ＋ rows are rows of the Library's, *Browsing History* a row of each), the Browser's a press and hold on its field's leading glyph. `SurfaceBand` and the five-slot `BottomToolbarLayout` rows below are regular width's.*

| Name | Kind | What it is |
|---|---|---|
| `ChromeHost` | view | Compact width only: the one chrome above the Library, the browser and Settings (and the in-place readers): two rows expanded, one collapsed, over `ChromeScreen`s from each destination. |
| `ChromeListenButton` | view | Listen at the end of row 1: headphones or the playing bars; opens Listen on what plays or the page played last. |
| `ChromeScreen` | struct | What a destination hands the host: its field, ‹ › callbacks and ids, strip title and edit bar. |
| `ChromeState` | struct | What the chrome shows: destination, collapse progress, `fullScreen`, history, keyboard, reader mode. |
| `ChromeScroll` | class | The one scroll controller: a continuous progress from scroll reports (90 pt a travel, snap at rest); `expand()` is the icon tap and a new page. |
| `ChromeLayout` | struct | The rect and opacity of every piece for a width and a `ChromeState` (the mockups' `rectsFor` and width table), sized by `ChromeMetrics`. |
| `ChromePieces` | view | Draws the pieces from a `ChromeLayout`; animatable in the progress. |
| `ChromeSkin` | enum | `.system` (everything else), `.glass` (iOS 26), `.material` (earlier iOS, and `-chromeFallback`). |
| `SurfaceBand` | view | The regular-width address / search field with its ✕ while searching. |
| `ChromeMetrics` | enum (constants) | The compact chrome's one token set (`DesignSystem/Chrome`): heights, gaps, margins, the lit inset. |
| `BottomChrome` | enum (constants) | Control sizes both widths share (glyph, tap target, field, discs). |
| `BottomToolbarLayout` | layout | 5-slot evenly-spaced grid for regular width's toolbar rows (browser, Library, Listen transport). |
| `PlayerCard` | enum | Shared constants (artwork size, progress height) and the flat card surface for `NowPlayingBar`. |
| `NowPlayingBar` | view | The compact flat card (artwork, title, groove progress line, play/pause) on the `PlayerCard` surface (no shadow), in `SurfaceBand`'s top row. |
| `NowPlayingBarView` | view | The same card in the Reader's band; hides on Listen and while sheets are up. |
| `ReaderPlayerCard` | view | Compact Listen's player card, sized to its rows, no divider: title and Save; site and time left; scrubber; speed and Voice at the margins, the `card`-size transport centred between (Aa and ⋯ are the top group's, `ReadingTopGroup`). Drawn on glass by the cover band. |
| `ReadingBottomBand` | view | The bottom band of the Reader and Listen: integrated controls flat on the page background, separated by a hairline divider. |
| `ReadingPage` | view | A reading page in place (compact) or in a `Sheet` (regular), laid out by `ReadingBars`. |
| `ReaderSheet` | view | The Reader's page: its band and Listen over `ReadingPage`. |
| `NowPlayingSheet` | view | Listen's page over `ReadingPage`. |
| `NowPlayingControls` | view | Status notes (buffering, language, debug) in Listen's band. |
| `ListenTransportView` | view | Speech-bound wrapper for `NowPlayingTransport` (skips, play/pause disc) with swipe gesture. |
| `NowPlayingTransport` | view | The 5-slot transport row component: skip-back, play/pause disc (44 pt), skip-forward. |
| `ReaderScrubRow` | view | The scrub bar in the bottom band (Listen: live; Reader: position 0). |
| `IconButton` | view | The app's one icon button: on the round face (36 pt, field fill, hairline, 20 pt medium glyph (`BottomChrome.chromeGlyph`) via `roundFieldControl`) for Voice, Aa and ☝︎ in a sheet's top bar and beside the player's title, or a bare toolbar cell (`round: false`) in the compact card's tools row (Voice). Lit, it takes the accent. The bookmark (`SaveToggleButton(round:)`) draws the same two faces (`iconButtonFace`). |
