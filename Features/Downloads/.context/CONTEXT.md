# Downloads: working notes

What the user sees is in `../../../docs/NAVIGATION.md` → "Downloads"; how it renders is
`../../../docs/LISTEN_PLAYBACK.md` → "Render queue" (Downloads). Decision D16.

- **No render path of its own.** `DownloadCenter` hands one page at a time to the render queue as
  an ordinary bake job (`LocalTTSCoordinator.queueDownload` → `startBakeIfNeeded`) and waits for
  its `bakeCompleted` (`RenderQueueObserver`). Priority behind the playhead, the thermal / Low
  Power hold and the background rules (`RenderAdmission`, bursts for the playing article only)
  come from the queue. Don't add a loop that renders, and don't let a download job count as
  playing (`playingCacheKeys`): that would let it render in the background.
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
  waiters). *Delete Downloads* on the playing page still takes its download off the list; its
  audio stays for the session, saved or ephemeral as the library keeps the page.
- **The list keeps downloads of what is in the Library** (`isInLibrary`, the line
  `LibraryQueries` draws): at `start`, and after each stored library edit
  (`LibraryStore.editStored`), a download whose page was removed from the Library, or whose page
  or folder was deleted, leaves the list without touching audio (the library already made it
  ephemeral or deleted it). A folder download's page that left the Library fails as "no longer in
  the Library" when its turn comes.
- **Folder downloads list their pages when asked**: a book's or series' chapters that play and
  aren't finished (D7 trims finished ones' audio anyway), any other folder's own pages. Pages added
  later need *Re-download*.
- **A row's Downloaded ✓ is the *Downloaded* section's rule (`done`), per page** (`DownloadCenter.isDownloaded`,
  `DownloadOverview.isDownloaded` → `DownloadRecord.hasDownloaded`): an entry `.done` and its
  audio there, in a voice its download accepts (`DownloadRecord.accepts`: the download voice now,
  or the one *Keep* stored). So after *Keep* the rows are marked and a folder's Download button is
  done. *Delete Downloads* keeps the two in step (`forgetDone`): a download of just a page whose
  audio it deleted goes, and a folder's download puts the page back in its queue while it covers
  it (so it leaves *Downloaded* and renders it again), else takes it off its list.
  While queued, a Download control's ring shows `DownloadOverview.fraction(of:active:)`, the
  list's own figure (`DownloadCenter.state(of:isDownloaded:)`). A
  folder row passes the pages it already holds (`covers`, the same filter a folder download
  uses), so it fetches nothing; the cache's indexes are in memory.
- **`DownloadOverview` is pure** (sections, statuses, the progress line, a link page's fetch as
  `.fetching`); `DownloadOverviewTests` pins its rules, and the sheet reads only it. The bottom
  chrome reads only `DownloadCenter.progress`, which reads no voices.
- **The list changes through `updateRecords` / `withRecord`**: a copy, assigned once, so each
  change writes `Downloads.json` once (pausing everything too).
- **UI tests** use the Debug test voice (`-testVoice`, `-selectEngine test.voice`,
  `-testVoiceDelay`): the Simulator has no Kokoro model. Every UI-test launch's `-resetLibrary`
  empties the download list and puts the voice back on One.
