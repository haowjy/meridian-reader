# Prepared Audio: deferred

- **Rendering while charging, with the phone locked.** Not built: with the app in the background and nothing playing,
  no call starts (while audio plays, prepares render on). It needs a `BGProcessingTask` with
  `requiresExternalPower` (Info.plist `BGTaskSchedulerPermittedIdentifiers`, the `processing`
  background mode), registered at launch, under which the render policy may start calls while
  nothing plays, and that stops at expiry. The launch it may cause runs
  in the background (library maintenance, the Kokoro load), which nothing has been measured for
  yet. Ties in with Speech's deferred overnight baking (`../../Speech/.context/FUTURE.md`). Needs a
  Release build and a locked, charging phone to verify (timing log).
- A book's *Replace* that revises the playing chapter drops its queued render
  (`stopIfPlaying` → `removeBakeJob`). When that chapter is also a prepare page in flight,
  `checkActive` requeues it once with the paragraphs it took before the *Replace*, so it may
  render the old text; the prepare should take the revised chapter's paragraphs.
- Storage is measured per prepare from its pages' audio folders; pages shared by two prepared audio
  count in both.
