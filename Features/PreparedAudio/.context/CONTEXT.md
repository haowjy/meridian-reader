# Prepared Audio: working notes

What the user sees is in `../../../docs/NAVIGATION.md` → "Prepared Audio"; how it renders is
`../../../docs/LISTEN_PLAYBACK.md` → "Render queue" (Prepared Audio). Decision D16.

- **No render path of its own.** `PrepareCenter` hands one page at a time to the render queue as
  an ordinary bake job (`LocalTTSCoordinator.queuePrepare` → `startBakeIfNeeded`) and looks
  again at each render-queue change, its job's end included (`scheduleCheck`). Priority behind
  the playhead, the thermal / Low Power hold and the background rules (`RenderAdmission`: bursts
  for the playing article, a prepare's turn while it is safely ahead, C94) come from the queue.
  Don't add a loop that renders, and don't let a prepare job count as playing
  (`playingCacheKeys`): it renders in the background only on its turn (`markPrepare`).
- **It asks the speech stack only through `PrepareRendering`** (the coordinator conforms in
  `LocalTTSCoordinator+PreparedAudio`); nothing hands it the render queue or the audio cache. It
  assigns nothing on its collaborators: `AppComposition.makePreparedAudio` wires the coordinator's
  `onRenderStateChange` to `scheduleCheck`, the library's `editStored` to `followLibrary`, and
  `needsAudio` from the session and the staged chapter. Both events do nothing until `start()`,
  which runs after the launch's library maintenance.
- **In the background, only while audio plays on the CPU route** (`mayHandOver`,
  `rendersPreparedAudioInBackground`, C94). A link article's fetch needs a window (`URLPageFetcher`) and
  waits for the foreground. Otherwise prepared audio resume on the next phase change.
- **The list records intent and outcome, the cache answers voice and readiness.** A record's
  entries say queued / done / speaksLive / failed; which voice an article is in is read from its audio
  (`ArticleAudioCache.renderedVoice`), so a voice change shows without touching the list.
  *Keep* stores the voice accepted (`keptVoice`).
- **Render-queue events arrive inside the queue's work** (`noteBakeMarksChanged` is called mid
  drain): `scheduleCheck` looks afterwards, coalesced. Don't act on the queue synchronously from
  the observer.
- **Prepared Audio never take away what listening needs** (`PrepareCenter.needsAudio`: the article bound
  to the session, in any phase, and the chapter staged after it). `purgeAudio` is the one way
  an article's *Remove Prepared Audio* and a folder's *Remove Prepared Audio* (in their menus and the Prepared Audio list) delete audio, and it skips those keys; `stopActive` leaves
  their job in the queue (`removeBakeJob` takes any other out: removing a job fails its chunk
  waiters). *Remove Prepared Audio* on the playing article still takes it out of every prepare; its
  audio stays for the session, saved or ephemeral as the library keeps the article.
- **The list keeps prepared audio of what is in the Library** (`isInLibrary`, the line
  `LibraryQueries` draws): at `start`, and after each stored library edit
  (`LibraryStore.editStored`), a prepare whose article was removed from the Library, or whose article
  or folder was deleted, leaves the list without touching audio (the library already made it
  ephemeral or deleted it). A folder prepare's article that left the Library fails as "no longer in
  the Library" when its turn comes; the one rendering stops at once (`followLibrary`).
- **A folder's prepare is its Prepare toggle** (`PrepareRecord.followsFolder`), its header's
  Prepare control and one *Prepare Audio* / *Turn Off Prepare Audio* row in its menus (its face is
  `isOn`, not the state). It lists the
  folder's pages when turned on: a book's or story's chapters that play and
  aren't finished (D7 trims finished ones' audio anyway), any other folder's own pages. While it
  is on, pages added later join it after each stored library edit (`takeInNewPages`, the same
  pass that drops what left the Library), except the ones in `deleted` (P8: *Remove Prepared Audio* on
  an article records it there; turning the toggle on again empties it). Turned off (`turnOff`), its
  queued pages leave it and done ones stay, so the rows keep their ✓. *Prepare Audio* with the toggle
  off over a folder all prepared (the header's ✓) only turns it back on (`turnOn`): done
  entries and `keptVoice` stay and only pages not listed join, since `requeue` would check
  every article again and re-render what *Keep* accepted. A list written before the toggle decodes
  as on (`PrepareRecord.init(from:)`).
- **Link pages are fetched through Follow** (`fill`, `FollowCenter.fill`): one queue for every
  out-of-sight fetch, so a story's chapter Follow is already fetching is waited for, not fetched
  twice. The text is stored in place (`storeFetchedText`); the prepare then queues the render.
- **One answer for where a prepare stands: `PrepareCenter.state(of:)`** (`PrepareState`:
  not prepared, preparing(fraction), paused(fraction), prepared), read by an article row's mark, the
  *Prepare Audio* / *Remove Prepared Audio* face of the article's menu (`PageMenu`, wherever it shows),
  and (for a folder, with the pages its row or screen already holds) the folder row and its
  header's Prepare control. An article is preparing while any prepare (its own or its folder's)
  has its entry queued, paused too, and that wins over prepared; its fraction is always 0
  (nothing reads it), so a book screen's queued rows don't each measure the article rendering on
  every paragraph. A folder is preparing while its own prepare has pages queued, at the
  list's figure (`PrepareOverview.fraction(of:active:)`). Prepared is the *Prepared*
  section's rule (`done`), per page (`PrepareOverview.isPrepared` →
  `PrepareRecord.hasPrepared`): an entry `.done` and its audio there, in a voice its prepare
  accepts (`PrepareRecord.accepts`: the prepare voice now, or the one *Keep* stored). Audio a
  listen rendered never counts. An article out of the Library has none; a folder is prepared when
  every article it covers is (`covers`), or, covering none, while its toggle is on (a story you're
  caught up on). *Remove Prepared Audio* / *Remove Prepared Audio* keep the two in step (`forget`): the article
  leaves every prepare, a prepare of just that article goes and a folder's drops it from its list,
  never queuing it again. The folder's control then shows ↓ (not all its pages are prepared);
  tapping it lists the folder's pages afresh (`request` → `requeue`), and only then, or a play,
  renders the article. The cache's indexes are in memory, so rows asking is cheap.
- **`PrepareOverview` is pure** (sections, statuses, the progress line, a link article's fetch as
  `.fetching`); `PrepareOverviewTests` pins the accept rule, and the sheet reads only it. The bottom
  chrome reads only `PrepareCenter.progress`, which reads no voices.
- **The list changes through `updateRecords` / `withRecord`**: a copy, assigned once, so each
  change writes `Downloads.json` once (pausing everything too).
- **Probes on the Simulator** use the Debug test voice (`-testVoice`, `-selectEngine test.voice`):
  the Simulator has no Kokoro model. `-resetLibrary` empties the download list and puts the voice
  back on One.
- **Paused reads paused everywhere** (`PrepareState.paused`): a folder whose prepare is paused,
  and an article whose every queued prepare is, draw the same mark in grey (its row's tile, its
  header's control, the list's control), captioned *Paused*.
- **The list's rows are `ListRow`s** with the prepare's one menu (`PrepareMenu`, the same rows
  in every section, from the ⋯ and the long press) and the pause control in `ListRow.accessory`,
  before the ⋯. Its remove row and swipe are the item's own action (`PrepareCenter.remove` runs
  `deletePreparedAudio(of:)` on the article or folder, *Remove Prepared Audio* / *Remove Prepared Audio*); only a
  prepare whose article or folder has left the library is dropped alone.

## Retention and Prepared Audio (C134, C135, C136)

- **Three states.** *Prepared*: saved and you chose *Prepare Audio*; its audio is never cleared automatically. *Saved*: in the Library; listening renders audio as it goes, and saving or starring no longer renders the whole article. *Being read*: opened or played without saving, listed in Recent.
- **Recent is the last 50 articles started.** At launch and when an article starts, unsaved articles beyond those 50 are deleted with their audio; saved articles beyond them lose only their audio from listening. Audio the session or the staged chapter needs is never touched. The finished-chapters trim skips prepared audio.
- **Prepared Audio list** (⋯ › Prepared Audio, Settings): the prepared sections (Now, Waiting, Prepared, Different Voice) and **From Listening** (audio rendered while listening, no ↓, with a footer about Recent 50). Every row has *Delete Audio* (swipe and ⋯), which never deletes the article. The list's ⋯ (`MenuRegistry`, `.deleteAllPrepared`, `.clearListeningAudio`) has **Delete All…** ("Delete N articles and their prepared audio? This can't be undone.": deletes every prepared article and its audio, folders stay) and **Clear Audio From Listening…** (that audio only), each shown only when its section has rows.
- **Naming.** The feature is *Prepare*, in the UI and in code (`PrepareCenter`, `PrepareRecord`, `PreparedAudioSheet`, `Features/PreparedAudio`). *Download* stays only for real file downloads (voice models, the CPU model, EPUB files). On-disk names are kept: `Downloads.json`, its keys, `downloads.wordsPerSecond`.
