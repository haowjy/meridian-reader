# Downloads: working notes

What the user sees is in `../../../docs/NAVIGATION.md` → "Downloads"; how it renders is
`../../../docs/LISTEN_PLAYBACK.md` → "Render queue" (Downloads). Decision D16.

- **No render path of its own.** `DownloadCenter` hands one page at a time to the render queue as
  an ordinary bake job (`LocalTTSCoordinator.queueDownload` → `startBakeIfNeeded`) and looks
  again at each render-queue change, its job's end included (`scheduleCheck`). Priority behind
  the playhead, the thermal / Low Power hold and the background rules (`RenderAdmission`, bursts
  for the playing article only) come from the queue. Don't add a loop that renders, and don't let
  a download job count as playing (`playingCacheKeys`): that would let it render in the background.
- **It asks the speech stack only through `DownloadRendering`** (the coordinator conforms in
  `LocalTTSCoordinator+Downloads`); nothing hands it the render queue or the audio cache. It
  assigns nothing on its collaborators: `AppComposition.makeDownloads` wires the coordinator's
  `onRenderStateChange` to `scheduleCheck`, the library's `editStored` to `followLibrary`, and
  `needsAudio` from the session and the staged chapter. Both events do nothing until `start()`,
  which runs after the launch's library maintenance.
- **Nothing new starts in the background.** `advance` checks `AppRunState`; a link page's fetch
  needs a window (`URLPageFetcher`). Downloads resume on the next phase change.
- **The list records intent and outcome, the cache answers voice and readiness.** A record's
  entries say queued / done / speaksLive / failed; which voice a page is in is read from its audio
  (`ArticleAudioCache.renderedVoice`), so a voice change shows without touching the list.
  *Keep* stores the voice accepted (`keptVoice`).
- **Render-queue events arrive inside the queue's work** (`noteBakeMarksChanged` is called mid
  drain): `scheduleCheck` looks afterwards, coalesced. Don't act on the queue synchronously from
  the observer.
- **Downloads never take away what listening needs** (`DownloadCenter.needsAudio`: the page bound
  to the session, in any phase, and the chapter staged after it). `purgeAudio` is the one way
  *Remove* and both *Delete Downloads* delete audio, and it skips those keys; `stopActive` leaves
  their job in the queue (`removeBakeJob` takes any other out: removing a job fails its chunk
  waiters). *Delete Downloads* on the playing page still takes it out of every download; its
  audio stays for the session, saved or ephemeral as the library keeps the page.
- **The list keeps downloads of what is in the Library** (`isInLibrary`, the line
  `LibraryQueries` draws): at `start`, and after each stored library edit
  (`LibraryStore.editStored`), a download whose page was removed from the Library, or whose page
  or folder was deleted, leaves the list without touching audio (the library already made it
  ephemeral or deleted it). A folder download's page that left the Library fails as "no longer in
  the Library" when its turn comes; the one rendering stops at once (`followLibrary`).
- **A folder's download is its Download switch** (`DownloadRecord.followsFolder`). It lists the
  folder's pages when turned on: a book's or story's chapters that play and
  aren't finished (D7 trims finished ones' audio anyway), any other folder's own pages. While it
  is on, pages added later join it after each stored library edit (`takeInNewPages`, the same
  pass that drops what left the Library), except the ones in `deleted` (P8: *Delete Downloads* on
  a page records it there; turning the switch on again empties it). Turned off (`turnOff`), its
  queued pages leave it and done ones stay, so the rows keep their ✓. A list written before the
  switch decodes as on (`DownloadRecord.init(from:)`).
- **Link pages are fetched through Follow** (`fill`, `FollowCenter.fill`): one queue for every
  out-of-sight fetch, so a story's chapter Follow is already fetching is waited for, not fetched
  twice. The text is stored in place (`storeFetchedText`); the download then queues the render.
- **A row's Downloaded ✓ is the *Downloaded* section's rule (`done`), per page** (`DownloadCenter.isDownloaded`,
  `DownloadOverview.isDownloaded` → `DownloadRecord.hasDownloaded`): an entry `.done` and its
  audio there, in a voice its download accepts (`DownloadRecord.accepts`: the download voice now,
  or the one *Keep* stored). So after *Keep* the rows are marked and a folder's Download button is
  done. *Delete Downloads* keeps the two in step (`forget`): the page leaves every download, a
  download of just that page goes and a folder's drops it from its list, never queuing it again.
  The folder's button then shows ⬇ (not all its pages are downloaded); tapping it lists the
  folder's pages afresh (`request` → `requeue`), and only then, or a play, renders the page.
  While queued, a Download control's ring shows `DownloadOverview.fraction(of:active:)`, the
  list's own figure (`DownloadCenter.state(of:isDownloaded:)`). A
  folder row passes the pages it already holds (`covers`, the same filter a folder download
  uses), so it fetches nothing; the cache's indexes are in memory.
- **`DownloadOverview` is pure** (sections, statuses, the progress line, a link page's fetch as
  `.fetching`); `DownloadOverviewTests` pins the accept rule, and the sheet reads only it. The bottom
  chrome reads only `DownloadCenter.progress`, which reads no voices.
- **The list changes through `updateRecords` / `withRecord`**: a copy, assigned once, so each
  change writes `Downloads.json` once (pausing everything too).
- **Probes on the Simulator** use the Debug test voice (`-testVoice`, `-selectEngine test.voice`):
  the Simulator has no Kokoro model. `-resetLibrary` empties the download list and puts the voice
  back on One.
