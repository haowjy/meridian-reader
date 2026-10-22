# Changelog

## Unreleased

- C149: no behavioral difference between a book and a folder. A Book/Folder toggle in Edit Details changes only labels ("chapters" vs "articles"). All folders get the same add menu (New Folder, Import from, Paste Text), subfolders, reorder via drag handles, Sort, and Cancel/Done edit mode. EPUB imports default to Book, preserving initial chapter order, now freely reorderable. Kept book-specific: voice per folder (C138, one voice for all chapters in a book/series), chapter display in Now Playing, Follow series creation.
- C148: folder edit mode: Cancel (left) and Done (right) in the bar. Reordering starts only from the drag handle (≡) on the right of each row; touching elsewhere scrolls or selects. All changes during an edit session (reorders, renames, moves, deletes, new folders) are staged and committed together on Done; Cancel reverts every change. A "New Folder…" row (plus-folder icon, accent tint) at the top of the list in edit mode. Articles reorderable in edit mode regardless of current sort (reordering switches to Manual). Subfolders can be created inside any folder.
- Reader player: the save (bookmark) icon is flush with the scrubber's trailing edge, keeping its 44 pt tap area.
- C147: no shadows on any player card (mini player, Reader, Now Playing). The Reader and Now Playing players sit flat on the page, Spotify-style: cover tile with title and source, thin scrubber with times, then a prev / big green play / next row, with a hairline divider and no card.
- C146: the Library and Browser mini player is now the same card as the Reader and Now Playing player card: same fill, grey cover tile, 40 pt tile, 12 pt inset, one soft shadow, 4 pt progress line in the scrubber's colours.
- C145: Reader and Now Playing share one bottom band: same control row and player card at the same positions, one shadow (the card's own shadow removed), even 8 pt spacing, and the Reader card shows the scrubber and speed before Listen.
- C144: visual audit — transport disc 64→52 pt so Now Playing's controls match the app's lightweight chrome; skip icons switched to outline weight to match bookmark and ⋯; ad-hoc radii and padding aligned to design system tokens.
- C143: Reader and Now Playing thumb layout: no address row; the control row moves up so play sits where the thumb rests, the player card below it.
- C142: the Library and folder add menus drop Follow… and Save from Website… (both done from the browser); Paste Text…, Import from… and New Folder… stay.
- C141: Reader and Now Playing get one compact bottom area: a floating player card (title, scrubber, speed), the address field, and one control row (bookmark, previous, play, next, ⋯); the title shows once; the ⋯ menu is unchanged; full screen still shows only the text and the play button.
- C140: every ⋯ menu ends in the same icon row, Settings, Saved, Reader (Settings leaves the list; Favorites, History and Website leave the row); Bahh, Wobble, Jester, Organ, Superstar and Albert hidden from the voice picker.
- C139: Apple default voice for English prefers Nora / "Voice 4", then Premium/Enhanced, then
  Samantha, Daniel, Karen, Moira, Tessa among Standard voices. Voice picker now lists Standard
  non-novelty voices below Enhanced/Premium.
