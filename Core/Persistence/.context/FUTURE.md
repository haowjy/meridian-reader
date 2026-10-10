# Persistence: deferred

- **Save's move under an older key is outside the audio journal.** When an older page holds the
  address under another key than the reader's, `ArticleSaveCoordinator.save` moves the reader's
  audio under the page's key (`migrateListenCache`) and rekeys the live session after the save
  is stored. If the app dies between the two, that audio stays under the reader's key, ephemeral:
  the page doesn't get it back (opening it adopts only v1 keys, `ReaderArticle.legacyCacheKeys`),
  so it is rendered again, and the age prune takes the old copy. Journaling it needs a record that
  can move audio under a live player; the `merge` record reconciles files and isn't safe for that.

- **A key that comes back and goes again under a waiting `delete` or `align` loses the later
  chapter's audio.** Sequence: a *Replace* edits chapter three and aligning its audio fails,
  so `align(three)` waits; a *Replace* drops three, so `delete(three)` waits behind it; a
  *Replace* brings key three back with new text, which is rendered and played; a *Replace* finds
  that text under a new key, five (`merge(three→five)`). When the work runs, no page holds key
  three, so the `align` and the `delete` act on its directory, which now holds the returned
  chapter's renders, and delete them before the merge can move them: five ends with no audio and
  renders it again. The session moves to five and listening is recorded there; in this sequence
  only audio is lost. Combined with other key reuse it can also cost listening, never move it:
  progress is written only on a page holding the text playing, and a session follows a merge only
  onto such a page (`LibraryStore.holds`). A fix for `delete`: leave a key that a later record
  names to that record, as `merge` does (`namedLater`). `align` can't simply do the same:
  `align(A)` then `merge(A→B)` in one save is the layout pass followed by dedupe.
- **Listening isn't recorded while a merge waits.** A session playing a merged page's key keeps
  that key until the merge record runs and moves it (`keyMerged`). While no page holds the key,
  `ListeningProgressRecorder` records nothing, and the kept page keeps the spot carried when the
  merge was planned; the whole wait is lost, an end included. A later *Replace* can give the key
  to another chapter (bring it back with other text): then a page holds the key, but not the
  text playing, so nothing is recorded either (`LibraryStore.holds`). A merge waits only when it, or
  an audio record before it, fails. Seen in a probe: chapter three plays to paragraph 1, a
  *Replace* finds its text under a new key while the merge waits, playback reaches paragraph 2,
  and the new key still holds paragraph 1. A fix: the recorder resolves a key with no page
  through the waiting merge to the kept page while that page still holds the text playing,
  without the early rekey's side effects (a start, the book's place, the D7 trim).
- **A waiting merge whose kept chapter's text moves to another key leaves its session on a key no
  page holds.** Sequence: chapter three plays; a *Replace* finds its text under `renamed` and the
  merge waits; a second *Replace* finds that text under five (`merge(renamed→five)`). Neither
  *Replace* stops the session, since the chapter's text is unchanged. When the work runs,
  `merge(three→renamed)` finds no kept page, so it moves neither the session nor the audio
  (three's audio goes on the ephemeral TTL), and `merge(renamed→five)` moves only what `renamed`
  has, which is nothing. Seen in a probe: the session plays on under key three, recording
  nothing, and five has no audio. It stays unrecorded after the work drains, and five's audio is
  rendered again. If a later *Replace* brings `renamed` back with other text before the work
  runs, the first merge does find a kept page, but it holds other text: the session stops there
  instead of being moved onto it (`rekeyActiveSession`), and nothing of the old text is written
  on it. A fix: a merge whose kept page was merged in turn follows it onto the next kept page
  while that page holds the text playing.
