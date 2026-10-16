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
- **Only `cancelDownload` takes a job out**, and never the page playing or staged: removing a
  job fails its chunk waiters.
- **The list keeps downloads of what is in the Library** (`isInLibrary`, the line
  `LibraryQueries` draws): at `start`, and after each stored library edit
  (`LibraryStore.editStored`), a download whose page was removed from the Library, or whose page
  or folder was deleted, leaves the list without touching audio (the library already made it
  ephemeral or deleted it). A folder download's page that left the Library fails as "no longer in
  the Library" when its turn comes.
- **Folder downloads list their pages when asked**: a book's or series' chapters that play and
  aren't finished (D7 trims finished ones' audio anyway), any other folder's own pages. Pages added
  later need *Re-download*.
- **A row's Downloaded ✓ is the Done section's rule, per page** (`DownloadCenter.isDownloaded`,
  `DownloadOverview.isDownloaded`): an entry `.done` and its audio in the download voice now.
  While queued, a Download control's ring shows `DownloadOverview.fraction(of:active:)`, the
  list's own figure (`DownloadCenter.state(of:isDownloaded:)`). A
  folder row passes the pages it already holds (`covers`, the same filter a folder download
  uses), so it fetches nothing; the cache's indexes are in memory.
- **`DownloadOverview` is pure** (sections, statuses, the progress line); `DownloadOverviewTests`
  pins its rules. The bottom chrome reads only `DownloadCenter.progress`, which reads no voices.
- **UI tests** use the Debug test voice (`-testVoice`, `-selectEngine test.voice`,
  `-testVoiceDelay`, `-resetDownloads`): the Simulator has no Kokoro model. Each `-testVoice`
  launch resets the voice to One.
