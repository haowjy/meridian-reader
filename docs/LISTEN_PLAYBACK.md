# Listen playback

How Meridian Reader speaks an article: Apple TTS, or Kokoro on the device (engines: `TTS_ENGINES.md`).
One ownership story, so Play continues, Pause matches what you hear, and rendering ahead makes
starts fast.

## Model

```
UI ──intent──► SpeechController ──command──► bound ListenEngine
                │ PlaybackSessionState ▲          ├─ AppleListenEngine (AVSpeechSynthesizer)
                │ (document, position, │          └─ LocalListenEngine → LocalListenPlayer
                │  phase, resume point)│                                   └─ ListenUnitSource (per play)
                └──────────────────────┴── engine events                     ├─ ArticleAudioCache (rendered paragraphs)
                                           (PlaybackEngineEvent)             └─ GlobalSynthQueue → LocalSynthService (model)

Render queue: GlobalSynthQueue renders chunks ahead of the playhead (and bakes saved articles)
into ArticleAudioCache, admitted by RenderAdmission.
```

### Playback session (the one source of truth)

`PlaybackSessionState` (held by `SpeechController.playback`) owns:

| Field | Meaning |
|--------|---------|
| `articleID` | Session identity (the saved article's id / `SpeechSession.id`) |
| `folderID` | The folder the article is in, which playback carries on through (nil: it plays to its end and stops) |
| `document` | Ordered paragraphs (one article: paragraph indices stay article-local in a book) |
| `playhead` + `utf16Offset` | The position: paragraph and document UTF-16 offset of the spot being spoken |
| `phase` | `idle → prepared → playing ↔ paused → finished` |

The scrubber, the paragraph highlight, Now Playing and crash resume all read the position from
here, and every change is published synchronously. `resumePoint` (article + paragraph while
playing, with the text fingerprint; nil otherwise) is what crash resume reopens; the controller
writes it to `ListenResumePointStore` whenever it changes.

Phase and position change only through:

- **intents** from the UI and remote commands: `play`, `pause`, `resume`, `toggle`, `stop`,
  `skip`, `seekOffset`;
- **engine events**: `becameAudible`, `becamePaused`, `position(paragraph, utf16)`, `finished`
  (`statusChanged` only tells the controller to re-read the listen-bar status);
- **advancing** inside a folder (`PlaybackSessionState.advance`, "Books, series and folders"
  below): the next chapter replaces the article in place.

Rules:

- The session settles the position before it asks an engine to play or seek; the commands carry
  none, and the controller speaks from `utf16Offset`. A start spot (`ListenSpot`: a paragraph,
  and an offset that counts only while it lies in that paragraph) goes in through `bind`.
- Pause sends `.pause` to the engine; the phase turns paused on `becamePaused`, or at once when
  the engine snapshot already shows it paused.
- Engines never clear the session. They emit `finished`; the controller decides whether a book
  carries on, and otherwise the session finishes.
- At the end of an article (or of a book or series) the engines stop, the audio session deactivates
  and the lock screen clears, but the article stays bound in `finished`: the Now Playing bar keeps it
  with ▶ and ◉ Finished. Only *Stop Listening* (the bar's long-press) unbinds it, or the
  library changing the article under it: removed from the Library (once that is saved), deleted,
  its text revised by a *Replace*, or moved by a merge onto an article holding other text
  (`LibraryStore.stopPlaybackIfPlaying`, `rekeyActiveSession` → `SpeechController.stopIfPlaying`,
  which ends the session as Stop Listening does but renders nothing more for the article: no gap
  fill, and its queued render goes).
- On a finished article, `resume`, `toggle` and `play` from the playhead play it again from its top
  (paragraph 0, offset 0), whatever spot the voice finished at: the on-screen ▶, headphones, the
  lock screen and CarPlay all replay it, and the lock screen shows it again.
- `toggle`: playing **or** the engine audible → pause; paused → resume; else play.
- Seek (scrubber release) moves the playhead and offset; playing keeps playing from there, paused
  stays paused (the engine re-queues without sounding), prepared / finished just move where Play
  starts.

### What you hear, as the screens see it

`SpeechController` derives everything the screens show about what you hear from the session:

- **`nowPlaying`** (`NowPlaying`): the bound article's key, canonical URL, title (nil when the article
  has none), source (its host, or the book's or series' name for a chapter), its line one (`lineOne`:
  the title, else the source, else the address; what the bar and the lock screen name it by), byline (the lock screen's subtitle), artwork, where it plays from
  (`PlayingFrom.folder(id:name:)` for an article in a folder, else `.site(host:)`), whether it is a chapter (an article of a
  book or series) and phase. nil only before anything has played and after Stop
  Listening or the article's removal or delete. `isFinished` (phase `.finished`) is what the bar and Now Playing read for "◉ Finished".
- **Time left** is `ListeningTime`'s: one reading rate (180 words a minute, a word being 6 UTF-16
  units of the listen text; an article not yet played by its stored word count), one way to write it
  ("9 min left", "6 h 10 min left"), and an explicit playback rate at every call. Every surface
  passes the current speed (`SpeechController.rateMultiplier`): rows, folder headers, the resume
  bar, the Reader's length and Listen, the bar and Now Playing all count at the speed you hear,
  lengths and time left alike, and follow a speed change at once.
- **`playState(of:)`** for a `ListenTarget` (`.article(key)`, `.webPage(canonicalURL:)`, compared
  as strings so a saved article with a pre-v2 random id still matches its article, or `.folder(id)`,
  current while any article of that folder is bound): `idle`,
  `preparing` (the target of the current `beginPreparing` request, e.g. 🎧 while its article is
  extracted; a newer request, Stop Listening and every other playback intent end it, and only a
  request that `isStillPreparing` may start),
  `playing`, or `paused` (`.prepared` and `.finished` show as paused). Every ▶ / ⏸ / 🎧 comes from
  it.
- **`press(_:start:)`**: playing → pause; paused → resume (a finished article from its top); anything
  else runs `start`, which replaces what is playing. Pressing never navigates.
- **`userPerform(_:)`**: every intent the user asks for (▶ / ⏸, ⏮ / ⏭, a swipe, the scrubber,
  ☝︎, headphones and the lock screen, its speed change included) first forgets an auto-resume
  after an interruption and ends a preparation, then goes to the session. What the app does on
  its own (the next chapter, an interruption) goes straight to the session.
- **`start(_:at:)`** is the one way an article starts: a `SpeechSession` from a `ListenSpot`, replacing
  what plays. `listen(to:at:)` wraps it for a `ReaderArticle` (the Reader's Listen, 🎧), handing the
  article to `onListen` first; `playArticle` (Contents, *Play from Here*) loads a library article and
  starts it at its top. A library article starts at `Article.listenStart`: its saved spot, or its top
  once it is finished; the Reader's Listen label, its underlined sentence, a row's ▶ and 🎧 all use
  it. Continue on a folder starts at `LibraryStore.continueStart`'s spot.
- Now Playing's reading content isn't the controller's: Now Playing looks the playing article up by
  its key when it changes (`LibraryStore.nowPlayingContent(for:)`). The library has every article
  that has played (an article played without saving, or removed from the Library, is kept while it is in the last 50 of Recent (C134)
  after its last play), so it is there after a relaunch too. When nothing is bound any more
  (the article you heard removed or deleted) Now Playing closes itself.

### Engine adapters (`ListenEngine`)

`SpeechController.speak` binds one adapter per utterance. An adapter takes
`play(ListenPlayRequest)`, `pause`, `resume`, `stop` and `setRate`, reports `PlaybackEngineEvent`s
through `onEvent`, and answers `snapshot` (audible / paused). The controller drops events from an
engine that isn't bound (a cancelled utterance, a cleared player). Speed is a setting every
adapter keeps, bound or not, and always one of `ListenRate.options` (0.75× to 2×): the setter, the
lock screen's speed command and a stored value from an older build all snap to the nearest one,
so the players, the Apple voice and the lock screen agree. Adapters report facts; they own no bake policy and no UI phase.

- **`AppleListenEngine`**: one `AVSpeechUtterance` holding the rest of the article from the
  start offset; `pauseSpeaking(at: .word)` / `continueSpeaking`. The delegate reports
  `becameAudible`, `becamePaused`, `position` (the word about to be spoken) and `finished` (the
  live utterance's `didFinish`). Callbacks from a stopped or replaced utterance are dropped. A
  speed change re-speaks from the word being spoken. A paused `play` holds nothing; Resume plays
  from the playhead.
- **`LocalListenEngine`** drives `LocalListenPlayer` (file player + producer; plays rendered
  CAF units only). Each play binds one `ListenUnitSource` (`QueueUnitSource`: the article's
  paragraphs in one voice, over the audio cache and the render queue); the player never touches
  the model. A `play` or `stop` that arrives while the model loads wins: the waiting play returns
  without starting. Pause keeps `AVAudioPlayer.currentTime` and is confirmed at once; resume plays
  on with no re-queue. The end of the article is decided only by the player
  (`ChunkPlaybackQueue`): the producer calls `endOfInput()` once it has enqueued every paragraph,
  and the player finishes when its queue drains. A unit that can't sound (its file won't open or
  is empty, `play()` refuses, a decode error) leaves the player as done and the next one plays;
  only a unit that sounds is reported as started. Position inside a paragraph is player time, which
  has no callbacks, so while audio is wanted and the app is in front (active or inactive) the
  engine samples it 5×/s: it reports `position` once the spot moved a few characters
  (`ListenPositionMapper`: chunk boundaries plus time into the chunk, never before the offset the
  play started at) and `statusChanged` when the listen-bar status changed. In the background (the
  phone locked) the clock stops, so a locked listen doesn't wake the app 5×/s: a unit starting
  still reports its paragraph, and the player running dry (or a play or resume waiting for audio)
  holds `ReaderListenGap` until a unit starts, it pauses or stops. Back in front the clock starts
  again and catches up. Speed is a pitch-preserving time-stretch on the
  player (`AVAudioPlayer.enableRate` / `rate`; everything is rendered at 1×). If the host fails
  to load it calls `LocalSynthService.noteSpeakFailed`, and engine binding re-speaks the spot with
  Apple.

### Engine binding

- `LocalSynthService` (`LocalTTSCoordinator.synth`) holds the on-device model: the one resident
  host behind `LocalChunkRenderer`, the Apple renderer for text the engine can't produce
  (`AppleFallbackRenderer`: a synthesizer per render, so the render queue's fallback and the
  player's never wait on each other and none outlives a media-services reset; a synthesizer that
  sends nothing for 10 s is stopped and the render fails like any other), and the
  lifecycle `state` (`LocalEngineState`). A reload, an engine switch, a voice pack's swipe *Remove Download*, Settings'
  cancel or a failed start lets the host go: its load in flight stops, its models are released and
  the model call in flight on it finishes, and only then does the next host load, so two hosts'
  models (two ORT sessions, ≈1 GB) are never resident together. The states: `off` (Apple speaks), `warming(id, progress, task)`
  (prepare / load in flight; `task` is the single load, cancelling it abandons the load),
  `ready(id)`, `failed(id, message)` (Apple speaks; Settings shows the message). On every change
  the coordinator persists `reader.tts.engineID`, calls `onEngineChange` and tells the render
  queue what renders now (`renderTarget`, Render queue).
- `speak` picks the engine once from the article's selection (C138a, `ListenRoute`: `.apple(voice)`
  for an article in an Apple voice, `.local(VoiceSelection)` for one in an on-device voice, and
  `.appleStandIn`, D9's explicit unsaved exception) and binds it. Pause, resume, the play icon,
  "Preparing next…" and stop go to the bound engine until stop or the next `speak`. An on-device
  engine that isn't loaded loads for the article (`loadEngineIfNeeded`; one is loaded at a time);
  the player waits for it (`awaitEngine`) and fills any gap with temporary Apple audio (C129).
- Nothing moves a live utterance to another engine or voice: engine state changes don't
  re-route (`EngineHandover` is gone). Changing an article's voice stops its playback
  (`ArticleVoiceChange`).
- Views only call `setDefaultSelection` (Settings), `ArticleVoiceChange.apply` (an article's or a
  book's picker), `deleteModel` or `synth.cancelDownload`; they never restart playback themselves.

### UI binding

Views bind to `phase` and the position (and the paragraph highlight derived from them), never a
second "is playing" flag. The live offset is read only in small leaf views (`PlayheadReader`, the
Now Playing bar's progress, Now Playing's sentence underline), so a tick redraws only those. The
Reader never scrolls by itself once open (it opens at a saved spot's sentence); Now Playing
follows the spoken sentence until you scroll (`NAVIGATION.md`).

While the phase is playing but nothing is audible and more units remain (`isBufferingNext`), the
listen bar shows a spinner and "Preparing next…". That is not paused.

The listening position is saved from the session, whatever is on screen, by
`ListeningProgressRecorder` (built at the composition root, over `LibraryStore`):
`SpeechController.onProgress` reports each new paragraph and every phase change (pause, finish,
stop, and the stop that comes before an article is replaced) synchronously, and the recorder also
writes the live offset when the app leaves the foreground. Never per tick. It writes the article's
position, dates each start (`lastPlayedAt`, unfinished again) and marks the end (`finishedAt`),
holding the article it writes to rather than fetching it per paragraph. An article started from a
`ReaderArticle` (`SpeechController.onListen`: the Reader's Listen, 🎧) is recorded from it on its
first start, so an article the library doesn't have is kept with its text: played without saving,
not in the Library, removed once it leaves the last 50 of Recent (C134). For an article in a folder (a book's or
series' chapter, or an article in any folder you made) the same writes also move the folder's place
(`Folder.currentArticleKey`) to the article that starts (`LibraryStore+Chapters`); whether the folder is
finished is worked out from its pages (`FolderProgress.isFinished`), never stored. A page
filed elsewhere takes the place off its old folder (to the article before it). A write whose save fails waits in the context for the next save, and
a failed edit's rollback doesn't drop it: `LibraryStore` keeps the progress it hasn't stored
(`PendingListening`: a start, and the text it played when the store may not hold it, from the
article it came from or a copy of the article's own; the position; the end) and writes it again
after the rollback, with the dates it was made at and in the order it played, making again a
article only a play had made. It is forgotten once a save stores it. A position recorded while an
edit is being staged (stopping the playing article it deletes) isn't saved on its own: it waits for
the edit's save, so it can't store the edit half made.

Progress lands only on the text that was played. The session carries a fingerprint of its
document (`PlaybackSessionState.textFingerprint`, `ArticleIdentity.contentFingerprint` of its
paragraphs, hashed once per page bound), and every write (a start, a position, an end, the
chapter carried past) goes to the article for the session's key only while that article holds the same
text (`LibraryStore.holds`, which compares the stored listen blocks and keeps the last hash, so a
paragraph's write costs no hash). A key can name other text by then: a book's *Replace* brought
another chapter back under it, the article was refreshed on open while it played, a paused session
resumed or a staged next chapter is older than its article. Such a session plays on in its own text
and nothing it reaches is written; the article keeps its own listening. Kept progress is in one text
too: a rollback writes it again only on an article holding the text it was made in, and a play of
other text on the article starts it over. A session moves to another key only onto an article holding
its text: a merge whose kept page holds other text when it runs, or a Save landing on an older
article while the session plays older text, stops it instead (`rekeyActiveSession`, through
`stopIfPlaying`: no gap fill renders under the key left behind, which no article holds).

Crash resume runs only after a death the engine caused (`TTS_ENGINES.md` → "Crashes"): a
terminated process clears its in-flight marker, and a marker the process outlived, or one left by
a memory kill in the background, is logged and ignored, so nothing reopens or plays. Crash resume
follows the text too. The resume file keeps the playing paragraph with the
session's text fingerprint, and the layout pass and merges that move it map the paragraph into
the text they move it to and give it that text's fingerprint (a point in other text than the article
they move keeps its paragraph and text). At launch (`AppLaunch.resumeAfterCrash`) the paragraph is
applied only on an article holding that text: then the article plays again there (a crash under 20
minutes ago while playing) or opens paused there, as before. On an article holding other text by then
(refreshed on open while an older session played on, another chapter brought back under its key)
the article opens in Now Playing paused at its own stored spot, paragraph and offset, and keeps it;
nothing plays until ▶. A target that names no text (the crash marker's, used when nothing was
playing, or a resume file an older build wrote) counts only when it is the article's own stored
paragraph, which the recorder writes on every paragraph; otherwise it opens the article paused at its
own spot the same way. The position is then the recorder's to store, from the session bound.

### Books, series and folders

An article in a folder carries on through it, article to article, then stops; an article in no folder plays to
its end and stops. Every folder (a book, a series, Favorites, a folder you made) plays in its
sort, which is the order its screen shows (decisions D15, D19); a book's starts as the book's
order.
`SpeechSession.folder` (`PlaybackFolder`: id, name, whether it is a book or series) says which
folder an article is in: a library article's session fills it (`SpeechSession.article`), and `listen(to:)`
asks the library for an article started from an article (the Reader's Listen, 🎧). A book's name is
the bar's source; any other folder's pages keep their site there, and Now Playing's "Playing
from" names the folder either way. The rule is `ChapterAdvance`, pure, on a snapshot of the
folder's pages in their full play order (`LibraryStore.chapterSnapshot`, skipped ones included
and flagged): after an article, the next one that isn't skipped: an article with text plays; a followed
story's chapter still waiting for its text (a link, `Article.isWaitingChapter`) ends playback there,
so a story is never heard out of order (Follow fetches the chapter after the article playing ahead
of the others, `FollowCenter`, and ▶ on a waiting chapter fetches it, then plays it). A link article
anywhere else (a favorite) is skipped. Continue on a folder (`ChapterAdvance.start`, `LibraryStore.continueStart`) starts at its
place (the article that last played, which the recorder keeps), at the saved spot while
unfinished, else at the next page; with no place yet, at the first page's own saved spot; a
finished folder starts again from its first article. Catch-up baking at the end of an article, and the
D7 trim of finished chapters' audio, stay with books and series. The controller reaches the library through `NextChapterProviding`
(`chapters(of:)`, `load`, `articleFinished`), injected by `AppComposition`, so the speech
stack never touches SwiftData.

When the engine reports `finished`, the controller decides before the session sees it
(`SpeechController+Advance`):

- **Next chapter**: the library marks the chapter finished, and the session's `advance` binds the
  next one in place at its start, phase still playing. `speak` stops the engines as for
  any play, but nothing deactivates the audio session, clears the session or clears the lock
  screen (it only changes title), so locked listening goes on. The engine is picked again for it.
- **No next chapter** (the end, or a chapter still waiting for its text): the session finishes as
  for any article. Nothing waits silently for a fetch: a fetch needs the app in front, and iOS may
  suspend an app holding a silent audio session.

`playArticle(key)` (Contents) plays a chapter from its start, and the book carries on from it.
Headphone and lock-screen skips stay paragraph skips (D4).

**Rendering across the boundary.** Once the chapter's rendering has reached two paragraphs before
its end, the next chapter is staged in the render queue (`GlobalSynthQueue.stageNext`, "Render
queue"), so its opening is on disk when it starts; not when its audio is held for unfinished
library work (`ArticleAudioCache.held`), which a render would overwrite. On a host that can't render in
the background, no model call starts there, so a chapter not rendered in full (a paragraph with
words still needs audio, "Audio cache") plays in Apple's
voice until the app is in front again, when the on-device engine takes over at the next paragraph
(D9). Kokoro renders in the background on either route (the Core ML route hands over to ONNX) and
keeps its voice; there the next chapter's opening
renders in a background burst, once less than 4 min of the chapter playing is ready ahead
("Rendering in the background"). The catch-up bake at the end of a
page runs only for pages outside books and series, and finished chapters more than 2 behind the
book's place lose their audio, keeping their text (D7), except audio held for unfinished library
work.

Each boundary logs `chapter_advance` (what plays next) and, once the next chapter is audible,
`chapter_boundary`: `gap_ms` from the end of one chapter to the first audio of the next, and
whether the audio session was `deactivated` or the lock screen cleared in between (neither should
happen; "Diagnostics").

## Rendering ahead (on-device engine)

### Render queue

One **`GlobalSynthQueue`** owns all on-device synthesis, live and ahead. A single worker renders
one **chunk** per iteration, so the playhead can preempt bake-ahead between chunks; two model
calls never run at once (`SynthRenderGate.shared`). Actions reorder the queue through one
upsert, `enqueue(at:)` with a placement (`.front`, `.back`, `.behind` the playing chapter), and
`focusPlayhead`; nothing builds its own render loop. The coordinator's one entry for the Reader
opening an article and for listening starting or jumping is `LocalTTSCoordinator.openArticle`.

**What it renders for.** The coordinator owns one render target
(`LocalTTSCoordinator.renderTarget`, `RenderTarget`): the loaded on-device engine in its selected
voice, as the audio cache's engine and voice keys. Jobs and pending jobs carry no voice; every
readiness check, chunk file and publish reads the target at that step. While no engine is loaded
(Apple selected, a model loading or failed, every voice pack removed / model cleared, a cancelled download) there is no
target and nothing renders: the worker parks before its next chunk (the call in flight finishes
and files nothing), a listener's chunk plays with Apple, and the queue never loads a model itself.
Once an engine is ready the coordinator restarts it (`GlobalSynthQueue.renderTargetChanged`) and
the queued jobs, prepared audio and saves included, render in that engine's voice.

1. Open an article → it becomes #1; render from the resume point to the end, then fill gaps
   above it.
2. Skip / jump / seek → still #1; the cursor moves to the new paragraph.
3. Open another article → new #1; the previous one is demoted (its cache is kept).
4. The next chapter of a book or series is **staged** (`stageNext`) directly behind the job of
   the chapter playing, or at the front once that job is done (its audio all rendered), and kept
   there as the queue changes: ahead of demoted save and bake jobs, which in the background may
   park and would hold it back. It renders at bake-ahead priority (never listener), and only its
   first 3 paragraphs until it plays and becomes #1; at that cap it steps aside, so jobs behind it
   run. Its opening goes before the playing chapter's paragraphs above the playhead (the plan's
   fill from the top): listening reaches the next chapter before it comes back to them. So the
   playing chapter renders from its playhead to its end, then the next chapter's opening, then
   the playing chapter above its playhead, and only then the jobs behind them (saves,
   prepared audio). A later stage replaces it; another article playing, or the end of the book, unstages
   it (a job that was queued before stays). It counts as playing for admission (`playingCacheKeys`: the
   article playing and the staged chapter).
5. Pending jobs fold in once the engine is ready and the launch's maintenance has finished
   (`adoptPending`; Audio cache, Pending jobs): the article being listened to stays #1; any
   other job is #1 only if the queue is empty; the rest keep their plans, demoted.

`BakePriorityPlan(resume:count:)` is the explicit cursor: from its start to the end, then the
missing paragraphs above it:

| Event | Plan |
|-------|------|
| Article save | from 0: `0…end`, queued at the back |
| Reader open, listen start / jump | from `p`: `p…end`, then missing `0..<p`, at the front |
| Playback finished / stopped (outside books and series) | `startBakeIfNeeded` (from 0, at the back): fill leftover gaps |
| The article you hear removed, deleted or revised, or merged onto an article holding other text | its job leaves the queue (`removeBakeJob`); no gap fill |

Saving an article that is already queued, #1 included, keeps its place and plan; the job turns
saved (`.back` keeps a queued job where it is).

**Prepared Audio** (decision D16, `PrepareCenter`) add no render path of their own. The prepare list
(`Downloads.json`, `PrepareListStore`) is worked through one page at a time: a link page's text is
fetched through Follow's one fetch queue (`FollowCenter.fill` → `FetchQueue`, one fetch at a time,
paced per site) and stored in place, then the article's paragraphs go
to the queue as an ordinary bake job (`LocalTTSCoordinator.queuePrepare` → `startBakeIfNeeded`, a
plan from paragraph 0, queued at the back (#1 when nothing else is), kept in the pending jobs while the
engine loads). When the job leaves the queue (`bakeCompleted`, through
`LocalTTSCoordinator.onRenderStateChange`) the article is done once no paragraph needs audio in the
prepare voice (the one rule, `ArticleAudioCache.missingParagraphs`); a job that left unfinished goes back once, then
the article is marked failed. So the article playing and the staged chapter always go first, the
thermal / Low Power hold applies. In the background a prepare's job parks, except on its turn
(C94): while audio plays on a route that renders there (Kokoro's ONNX CPU route) and the playing
article needs nothing now (no burst: at least the low-water mark ahead; or nothing of it left), the
same one-thread worker renders it, weighed again before every chunk, so a burst of the playing
article takes the worker back at once (`bg_prepare_turn` / `bg_prepare_yield`). Then the next
article is handed over in the background too; a link article's fetch waits for the foreground (it needs
a window). Paused or stopped in the background, nothing goes on. Nothing renders for prepared audio while Apple's voice is
selected (`wantsLocalBake`). Pause and *Remove* take the article's job out of the queue
(`removeBakeJob`), and *Remove Prepared Audio* and *Remove Prepared Audio* delete audio (`PrepareCenter.purgeAudio`),
never for what listening needs (`needsAudio`: the article bound to the session, playing, paused or
finished, and the chapter staged after it): its job and its audio stay. *Remove Prepared Audio* (an article, in its menu or the Prepared Audio list) or *Remove Prepared Audio* (a folder, the same) takes
the article out of every prepare (a folder's prepare drops it, never queues it again), the article
playing too, whose audio stays for the session, saved or ephemeral as the library keeps the article. The voice a prepare is shown in is read
from its audio (`ArticleAudioCache.renderedVoice`: the voice most of its paragraphs are in), so a
voice change shows at once; finished prepared audio aren't re-rendered by it (*Prepare Again* does that).
A folder's prepare is its Prepare toggle (the header's Prepare control): while it is on, pages added to the folder later join
it after each stored library edit (`PrepareCenter.takeInNewArticles`), except pages whose prepared audio
were deleted (`PrepareRecord.deleted`); turned off, its waiting pages leave it and its done ones
stay. Turned back on over a folder all prepared (`PrepareCenter.prepare(folder)`'s `turnOn`),
its done pages and *Keep* stay as they are and only pages it doesn't list join; otherwise
*Prepare Audio* on a folder queues every article it covers afresh (`PrepareRecord.requeue`).

**Priority and admission.** Chunks of an article someone is listening to (a producer waits on
one, or its audio is playing) render at `RenderPriority.listener` (`.userInitiated`); bake-ahead
runs at `.utility`. Bake-ahead is held while the thermal state is `.serious` or worse or Low Power
Mode is on (`BakeConditions`) and resumes on the change notification. Before every chunk, in
`ensureChunk`, on every app-phase change and when a render fails, one pure rule decides
(`RenderAdmission.decide`):

| App phase | Kokoro, either route (renders in background) | A host that can't render in the background |
|---|---|---|
| active | render | render |
| inactive | render | listener's chunks only; bake-ahead parks |
| background | listener's chunks; bake-ahead of the playing article and the staged next chapter during a burst (below); other articles park | no model call: a listener's chunk plays with Apple, bake-ahead parks |

With no engine loaded (no render target) no model call starts in any phase: a listener's chunk
plays with Apple, bake-ahead parks.

The renderer checks it again right before each model call (`LocalChunkRenderer`,
`RenderAdmission.modelCallsAllowed`). No Core ML call ever starts in the background (no GPU
there, and the CPU fallback is the libBNNS crash path): Kokoro's Core ML route
(`KokoroSplitHost`) renders on ONNX from its first background load or call until the process
ends.

**Producer.** The player keeps a short buffer of rendered units and stops producing when it is
full. Chunk 0 plays as soon as it is rendered; the producer doesn't wait for the paragraph. Seek /
jump cancels the producer's pending units and restarts it at the new playhead; pause and resume
leave it alone. `ChunkPlaybackQueue` primes the next `AVAudioPlayer` while the current unit plays,
so joins between rendered units stay near zero; a gap only appears when rendering can't keep
ahead of the playhead (counted as a starve event).

**Head-start rule** (`HeadStart`, `RenderPace`): before rendering a chunk for a listener, the
engine projects whether rendering at the measured speed would starve playback by more than 2 s;
if so that paragraph plays with Apple ("Kokoro fell behind", `render_behind`), and the render
queue moves on to the next paragraph at once (`ListenUnitSource.focus`) instead of finishing the
one Apple speaks and falling behind again there; the skipped paragraph is rendered later, from
the top. A chunk the engine fails on does the same. Only listener calls feed `RenderPace`.

**Never silent, never skipped.** A chunk the engine can't render is rendered with Apple
(ahead), or the rest of the paragraph is spoken with Apple (live), both in the Apple voice for the
article's language: the user's pick when it speaks that language, else the best installed voice
for it (`SpeechController.appleVoice(forLanguage:)`, handed to the coordinator as
`appleVoiceForArticle`). Only if Apple also fails is
the paragraph skipped, logged as `SKIP pN` in the debug overlay and `skip` in the timing log.
A live Apple unit is a one-off file in `tmp/ReaderTTSLive`, never cached: it is deleted once the
unit leaves the player (`ChunkPlaybackQueue.onItemDone`: played out, dropped when the engine
takes over again in front, stopped), or at once when it isn't queued, and the first player of a
launch empties the folder of an earlier process's files.
Failed units go into `failedUnits`, so the worker never loops on them; a live request retries
once. An overflowing call (`inputTooLong`) is re-split down to 24 units.

### Chunking

The paragraph is the listen unit; internally `TextChunker` cuts it into chunks sized per engine
(`OnDeviceTraits.limits` in its descriptor; units ≈ characters, digits count 3). Invariant (unit-tested):
`chunks.joined(" ") == normalize(text)`. One owner keeps the plans, `ChunkPlans` (on the
coordinator, keyed by engine and text, bounded to the paragraphs asked about last, kept across a
voice change): the render queue, the player, the audio cache's alignment and the "still needs
audio" rule all read it.

| Limits | Target | Hard max | First chunk | Used by |
|---|---|---|---|---|
| `kokoroCPU` | 240 | 280 | 80 (a whole first sentence ≤ 104) | Kokoro, either route |

- **Sentences first.** Whole sentences are packed up to the chunk's budget (abbreviation-,
  initial-, "U.S.A."- and decimal-aware). A sentence that fits the hard max is split only to make
  the short first chunk or the ramp; longer ones are cut by `balancedSplit` (sentence-like
  `etc. The` > `; : —` > `,` > before a conjunction > space, pieces balanced). Aside dashes become
  commas, intra-word hyphens stay, a dash glued to punctuation goes ("etc-." → "etc.").
- **First chunk** (fast first audio):
  1. the whole first sentence if ≤ `firstTarget + 24`;
  2. else its head at the best clause boundary inside `firstTarget` (`; : —` > comma > before
     and/but/which/when…), at least a third of the budget long;
  3. else up to `firstTarget + 40` (120 units): the whole sentence, or the nearest clause boundary
     past the budget. On the phone the ONNX route renders ≈ 0.35 s + 23 ms per char (median,
     28 ms worst), so 120 units is ≈ 3 s to first audio, the most that still feels prompt;
  4. only for a clause-free run longer than that: a space cut inside the budget.
  A tiny first sentence ("Yes.") takes the next sentence, or its head at a clause, while it stays
  ≤ 120 (`growShortFirst`), so it doesn't play out before chunk 1 is ready.
- **Ramp.** Chunk k renders while chunks 0…k−1 play, at ≥ 2× real time, so chunk k ≤
  2·u₀ + u₁ + … + u_{k−1}; the second chunk is at most 160. A whole sentence may overshoot by
  25 % rather than be cut mid-phrase, and a sentence with no clause boundary inside the budget
  stays whole: on ordinary paragraphs the ramp is a target, not a guarantee.
- **Joins.** Kokoro pads every call with ≈0.3 s of leading and ≈0.5 s of trailing silence.
  `ChunkEdgeTrim` (hosts with `trimsEdgeSilence`: the ONNX route) keeps 40 ms before speech and a
  trailing pause by boundary: sentence 360 ms, clause 180, word 40, paragraph end 520. A cut
  before a conjunction counts as a clause (the queue passes the next chunk's first word). Joins
  are ≈0.40 s at sentences and ≈0.22 s at commas, like Kokoro's own pauses.

### Long paragraphs

Paragraphs over **1,200 characters** are split at sentence ends into balanced pieces for display,
navigation and audio alike (`ParagraphSplitter`, listen layout v3), so tap-to-seek, resume,
highlight and the paragraph picker stay fine-grained.

- A paragraph of length L > 1,200 is cut into k = ⌈L/900⌉ pieces (≥ 2) by a DP that minimises
  the squared deviation from L/k with every piece ≥ 300 characters; if no such cut exists it
  tries fewer pieces, else the paragraph stays whole (a single giant sentence stays whole; the
  chunker still splits it for synthesis). Sentence starts come from `TextChunker.isBoundary`.
  Deterministic.
- **The HTML is split, not a side list.** `ListenHTMLBlocks.splitLongBlocks` rewrites leaf `<p>`,
  `<blockquote>`, `<dd>` blocks, closing and reopening inline tags at each cut (ids stay on the
  first piece). `li`, `td`, headings and `pre` are never split. The reading HTML
  (`ParagraphDocument.readingHTML`) and the listen paragraphs (`ParagraphDocument.forListening`)
  come from the same split HTML, so web-view block index = listen / queue / cache paragraph
  index. Plain text splits the same way (`ParagraphDocument(plainText:)`).
- **Migration** (`LibraryStore.migrateParagraphLayout`, run inside the library migration on
  the copied pages before they are deduped, and by `AppLaunch` before the launch dedupe pass and
  crash resume): library pages holding text with `listenBlocksVersion < 3` get new blocks, and
  the reading position maps by character offset (`ParagraphPositionMap`). Once that is saved
  (`LibraryAudioWork`, see `TECHNICAL_SPEC.md`), the resume point and the in-memory crash-resume
  target (with the new text's fingerprint) and any pending bake job are remapped; cached audio of
  unchanged paragraphs moves by text hash, and a split paragraph's CAF is sliced sample-exact
  (`ArticleAudioCache.reconcile`, by `chunkDurations`) into each piece whose chunk
  plan equals a contiguous run of the old chunks; other pieces re-render. Logged as
  `paragraph_layout_migration` (paragraphs, position) and `library_audio_work` (audio kept,
  moved, sliced, dropped). The same remap runs for unsaved reader keys in
  `LocalTTSCoordinator.prepareListenIdentity`.

## Audio cache

`ArticleAudioCache`, `Application Support/TTSCache/<article key>/`:

- **Not backed up.** The launch flags `TTSCache` to stay out of iCloud and computer backups
  (`BackupExclusion`, before anything renders; the flag on the folder covers every article in
  it, the ones already there included): the app can render the audio again, and a prepared
  10-hour book is about 1.7 GB. The engines' downloads (`fluidaudio/`, `CPURoute/`) and
  `ListenTiming/` are flagged the same way.
- `index.json` + `p-NNNN.caf` per rendered paragraph, written incrementally so a partial render
  plays. Each entry stores the paragraph's `textHash` and, for stitched paragraphs,
  `chunkDurations` (mid-paragraph seek and resume). The index is read once per article and kept in
  memory; every write goes through it, so ready / playable reads never touch the disk.
- **Changes are copy-on-write.** Aligning an article's audio with new paragraphs
  (`reconcile`: shifted units move, split paragraphs are sliced, a merged article's units fill the
  gaps) and moving it under another key (`rekeyCache`) never remove or rename a CAF the saved
  index lists before the index replacing it is saved. New CAFs are written first under new names
  (`m-NNNN-…` for a unit on a new paragraph or from another key, `s-NNNN-…` for a slice;
  `p-NNNN.caf` stays the render queue's name for paragraph NNNN), the index is saved in one
  atomic write, and only then is what it no longer lists deleted, with any `m-` / `s-` file an
  interrupted change left. An app that dies at any step leaves an index whose every CAF exists
  (a cold load drops nothing), and running the change again finishes it. A key with no directory takes
  another's whole, in one rename.
- Chunk scratch: `chunks/p-NNNN-<texthash>-<voice>/c-KK.caf`, filed by cache voice: a call in
  flight when the voice changes writes into its own voice's folder, never where the new voice
  looks, and a chunk rendered for a target that changed during the call is neither handed to a
  listener nor stitched. Once every chunk of a paragraph exists the
  worker stitches them off the main actor into a file of their own in that scratch
  (`paragraph-<id>.caf`). Back on the main actor it is published only if the queue still wants
  that text on that paragraph in that voice: its job still has the article with the same text
  hash there (an alignment of the article's audio, opening it with newer text, or clearing,
  deleting or rekeying it may have landed meanwhile) and the render target is unchanged;
  otherwise it is dropped. Every alignment of an
  article's audio with new paragraphs (opening it, Save) gives its job those paragraphs too,
  keeping the job's place and plan, so a job never renders old text onto them. Publishing renames
  it over `p-NNNN.caf` (a CAF that may be playing is never written into) and records it in the
  same main-actor step, so no alignment runs between the file and its entry.
  Replays use the stitched file. Scratch is disposable at launch;
  while an article has a queue job, scratch whose text hash still matches its paragraphs (in any
  voice) is kept
  (`removeChunkScratch(for:keepingCurrent:)`), because every extra Kokoro call is exposure to the
  libBNNS crash.
- **Keys** (`ARTICLE_IDENTITY.md`): one per canonical URL, saved or not. Leaving an unsaved
  reader keeps its audio; audio from listening is cleared once its article leaves the last 50 of Recent (C134); prepared audio never is, except audio
  held for unfinished library work (`TECHNICAL_SPEC.md`, Audio work waits for the save). Save
  marks the cache saved once the save is stored, and *Remove from Library* marks it
  ephemeral again, both through the library's audio work; deleting a saved row deletes its audio.
  Saving the article that is playing, under its own key, moves no audio. When an article holds the
  address under an older key, the reader's audio moves under the article's key and the live session
  is rekeyed, without a restart, while it plays the saved text (otherwise it stops); saving a
  article that isn't playing aligns its audio with the saved text and can adopt a legacy v1 cache
  (`prepareListenIdentity`, as on open).
- **What still needs audio** has one rule, `ArticleAudioCache.missingParagraphs`: a paragraph
  with something to speak (its chunk plan, `ChunkPlans`, has chunks) and no CAF in exactly this
  engine and voice. A paragraph with nothing to speak (a bare "—") never gets audio and is never
  missing. The render queue's work and job completion, the voice-switch cleanup, Prepared Audio,
  staging the next chapter and Apple standing in (D9) all ask it; the bake marks show
  `readyIndices`.
- **One voice per article, and per book (C138, C138a).** Each article stores its selection, the
  engine and voice together (`VoiceSelection`, stored in `Article.voiceID` as
  `local.kokoro/af_heart` or `apple/<voice identifier>`; `apple/` is the best Apple voice for its
  language). It is the only source of what plays, renders, prepares and is looked up in the cache,
  resolved once per article (its own, else its book's, else for a brand-new article the Settings
  default, or Apple when the default's engine can't speak its language) and passed explicitly
  (`ListenPlayRequest.selection`, `QueueUnitSource.selection`, `RenderTarget`). No global engine or
  voice is read on those paths; Settings holds only the default for new articles. The render
  queue never files Apple audio in an article's cache: an engine failure fails the unit and the
  player fills the gap live with temporary, unsaved Apple audio (C129). A book or series chapter
  speaks in its folder's (`Folder.voiceID`), so a book never changes voice between chapters.
  The voice is set when its first audio is about to render (`LocalTTSCoordinator.lockedRenderTarget`,
  from the render queue's step and the listen player's source): the voice selected in Settings
  then. Changing the voice in Settings only affects articles and books with no audio yet. The
  render queue renders each job in its article's voice (`renderTarget(for:)`; the host switches
  voice per chunk, `ChunkRenderRequest.voice`), and readiness, bake marks, Prepared Audio and
  the listen player all ask in that voice. Playback plays only CAFs in the article's voice
  (`playableAudioURL` no longer falls back to another voice's file), so voices never mix.
  The index's top-level `engineID` / `voiceID` is still the voice of its last write; entries of
  another voice are stamped and never count or play; once nothing is missing in the article's
  voice, `finalizeVoiceSwitch` deletes them.
- **Changing an article's or book's voice** (its menu's *Voice: Heart*, `ArticleVoiceChange`):
  downloads the voice's files if needed, stops playback of it if it is playing (it plays again
  all in the new voice), stores the voice, then prepared audio renders again (Prepare Again; the
  old files go once the new audio is whole) and audio from listening is cleared. The picker asks
  first with the sizes.
- **Migration (C138, once, `AppComposition.adoptArticleVoices`):** an article with audio takes the
  voice most of its paragraphs are in (`ArticleAudioCache.renderedVoice`); a book, the voice most
  of its chapters' audio is in; articles with no audio get none. C138a, once: a voice stored as a
  cache voice key (`kokoro.af_heart`) becomes a selection with its engine (`LibraryStore.convertVoices`).
  The Settings default comes from the engine and voices chosen before (`loadDefaultSelection`).
- **Language gate.** Only when a brand-new article takes its selection: one in a language the
  default's engine can't speak takes Apple (`LocalTTSCoordinator.localLanguageGate`). An article
  with a selection keeps it.

**Pending jobs.** Articles saved or opened while the engine was cold are kept as pending bake
jobs in `Application Support/PendingBakeJobs.json` (`PendingBakeJobStore`: the paragraphs and the
paragraph to start from; they render in the voice selected when they do) and fold into the queue
once the engine is ready. At launch the queue is held from the first audio-cache step
(`AppComposition.prepareAudioCache`, before the first frame) until the library's launch
maintenance has finished (`AppLaunch.maintainLibrary`: left audio work, layout pass, dedupe,
prune): it adopts no pending job and renders nothing, though the engine loads meanwhile
(`LocalTTSCoordinator.holdRenderingForLaunch`). So nothing renders on paragraphs that maintenance
rebuilds or merges, and the jobs it remaps are adopted as it leaves them.
Nothing bakes while the app is suspended: the app registers no
background task, and full-article rendering in the background is not promised.

**Core ML compile cache.** Core ML adds compiled bundles under
`Library/Caches/<bundle>/com.apple.e5rt.e5bundlecache/<os build>/` after every install and never
evicts the stale ones (a development phone reached 16.7 GB). `CoreMLCompileCacheJanitor`, one of
FluidAudio's launch steps, runs once per install (`reader.coreml.e5janitor.installID` = the install's container UUID; bundle file
dates read as the epoch on device) and deletes bundle dirs whose newest file predates this launch.
Logs `coreml_cache_prune`.

## Language

- **Detection** (`ListenLanguage`): `NLLanguageRecognizer` over the first 4,000 characters of the
  listen blocks; needs ≥ 24 letters and confidence ≥ 0.5. Stored in
  `Article.detectedLanguageCode` (written with the listen blocks, backfilled on open for older
  pages); articles the library doesn't have use an in-memory memo. Passed through
  `SpeechSession.detectedLanguage`.
- **Resolution** (`ListenLanguageResolution.resolve`): "Automatic (match article)" (the default,
  `reader.languageAutomatic`) or a manual language. If the selected engine doesn't speak it
  (`EngineDescriptor.supportedLanguages`; Kokoro is English only), that article speaks with the
  best Apple voice for the language, without changing settings, and the listen bar and the
  Language footer say so ("Apple voice for French (Kokoro is English-only)").

## Settings › Listening

`ListeningSettingsSection` in Settings (⋯ → *Settings*, `NAVIGATION.md` → "Settings"), on the
Library's list style: chrome cards on paper, `SectionHeader`s, notes in secondary ink. Every
choice row is one `SettingsChoiceRow` (title, optional one-line subtitle, fixed accessory and
check slots, min height 48), so state changes never move rows.

1. **Voice ›** (`VoicePage`): the default voice for new articles and books, from the one voice
   switcher (`VoiceSelectionList`, C138a), the same list an article's or a book's *Voice* picker
   shows. Engines are its sections: Kokoro's curated voices with samples (the default one marked
   "(default)"; the model's download progress, tap to cancel, or *Remove Download* below them;
   crash and failure notices in its footer), then Apple's: "Best for <language>" and the
   installed voices for the language, Premium, then Enhanced, then the rest. Picking a voice
   picks its engine; there is no Engine control. The row's value names it ("Heart", "Ava (Apple)").
2. **Language ›** (`LanguagePage`), 3. **Speed**, the six speeds in one line.

The version row at the bottom of Settings toggles developer options (a 2 s long-press); Settings
› Developer then holds **Listen debug**.

## Background listening

Leaving the app (Home, lock, app switcher) keeps Listen playing. Closing Now Playing or a Reader
keeps it playing too; the Now Playing bar shows it.

**Audio session** (`ListenAudioSession`): `UIBackgroundModes: [audio]` (`project.yml`). Category
`.playback`, mode `.spokenAudio`, no options: a mixable (ducking) session never becomes the Now
Playing app, so other apps' audio pauses while Meridian Reader speaks, like a podcast app. Only the
category is set at launch; the session activates when playback starts or resumes and deactivates
with `.notifyOthersOnDeactivation` on stop or finish. Address-bar dictation borrows it through
`ListenAudioSession` (`lendForRecording`, `.record` while the mic is open, then `reclaim`): Listen
pauses first, gets its category back after, and resumes if it was playing; a session Listen
wasn't holding is released, so other apps' audio can resume.

**Lock screen / Control Center** (`NowPlayingController`):

- `MPNowPlayingInfoCenter`: title = the article's title, else its site, artist = "site – Paragraph N of M" (plain text, so an
  en dash joins the parts; for an untitled article, whose title already is its site, "Paragraph N of M", as the bar leaves
  the site out), album = site,
  chapter number and count (paragraphs), progress N/M, favicon artwork, rate 0 while paused. For
  a chapter of a book or series: title = the chapter's, else the book's or series' name, artist =
  "<the book's byline> – Paragraph N of M", album = the book or series, artwork = the chapter's,
  else the book's cover. Built from `nowPlaying`, as the bar is (the title is `NowPlaying.lineOne`,
  never a made-up one; the subtitle's byline is `NowPlaying.byline`), with the artwork made once per picture rather than every paragraph. Shown
  while playing or paused, and kept across a chapter boundary; cleared on stop or at the end.
- `MPRemoteCommandCenter` (decision D4: headphone and lock-screen skips are paragraph skips, like
  the on-screen ⏮ ⏭): play, pause, togglePlayPause, nextTrack (next paragraph),
  previousTrack (previous paragraph; off at the first, as ⏮ is) and changePlaybackRate (snapped to
  the listen-bar rates). Skip, seek and position commands are off.
- Every command goes through `SpeechController.handleRemoteCommand` → `RemoteCommand.intent` →
  `userPerform` → `PlaybackSessionState.handle`, the same path as the on-screen buttons. Now Playing is
  re-derived from `playback` on every change; identical updates are skipped.

**Interruptions and route changes** (`ListenInterruptionPolicy`, a pure rule; every pause
and resume goes through session intents):

| Event | Action |
|---|---|
| Call, Siri or alarm starts while playing | Pause; remember it was playing |
| Interruption ends with `.shouldResume`, and it was playing | Reactivate the session and resume |
| Interruption ends without `.shouldResume` | Stay paused |
| `appWasSuspended` notice | Not a real interruption; never auto-resume |
| User does anything during an interruption (play, pause, skip, seek, stop, a speed change on the lock screen) | Forget the auto-resume |
| Route change `oldDeviceUnavailable` (headphones out, Bluetooth lost) | Pause |
| Media services reset | Reconfigure the category; the engines drop their dead audio objects (Apple builds a new synthesizer), and an article playing or paused is bound again paused at its spot, so Play speaks through new ones |

**Rendering in the background.** `AppRunState` mirrors `UIApplication` (active / inactive /
background), thread-safe; admission follows the table in "Render queue". On a host that can't render in the background a
paragraph that isn't rendered yet plays with Apple (`AVSpeechSynthesizer.write` into a temp CAF,
played in order, not cached) until the app is back in the foreground; a chunk that failed because
of backgrounding is never replaced with Apple audio in the cache.

The ONNX route renders in the background, within limits: rendering a whole article back to back
there got the app killed by iOS about a minute after the phone locked (3 threads, 1.0–1.3 GB).
So in the background:

- **One thread.** Kokoro's ONNX session runs 1 intra-op thread in the background and the
  configured count in front (every core but one, 3 to 6: 5 on an iPhone 17 Pro;
  `KokoroRouteSettings.defaultThreads`). ONNX Runtime fixes the count when a session is built, so the
  first call after a phase change rebuilds the session, between chunks (`KokoroONNXSessionSlot`,
  `kokoro_cpu_threads_switch`); the old session is released first.
- **Bursts between watermarks** (`BackgroundRenderWatermarks`, `BackgroundRenderBursts`). The
  measure is the listening time ready ahead: the rest of the unit playing, the units queued in the
  player and the rendered paragraphs after them up to the first gap, in seconds at the listen
  speed (`LocalListenPlayer.readyAheadSeconds`). Bake-ahead of the playing article (and of the
  staged next chapter) starts a burst below 4 min and renders chunk after chunk until 8 min are
  ready; between the two marks nothing new starts. Between bursts the worker is idle: each unit
  that starts playing, and a resume, wakes it if less than 4 min is left (no timer, no polling).
  A chunk the player is waiting for renders whatever is ready ahead. Only paragraphs from the
  playhead on render in the background: after listening from mid-article, the paragraphs above
  the playhead wait for the foreground (they add nothing ahead, so a burst rendering them would
  never reach 8 min). In front (inactive included) the marks don't apply.
- **No background task per chunk.** Playing audio keeps the app alive while it renders.
  `BackgroundGrace` (`beginBackgroundTask`) holds `ReaderSynthDrain` only so the chunk in flight
  when the app leaves the foreground can finish and write its CAF, and `ReaderListenGap` while the
  player waits for audio in the background; neither permits GPU work.

When rendering can't keep up (one thread, a fast listen speed), the head-start rule and the
fallbacks above still apply: a paragraph that would starve playback plays with Apple.

## Diagnostics

Developer options on (`NAVIGATION.md` → "Developer options"):

- **Listen debug** (Settings › Developer): a **Debug** chip on the listen bar opens a live overlay
  above the controls: article identity (`eph:` / `svd:` + short id), queue #1 and demoted count,
  active / next unit, worker busy or idle, warming model, article render % (ready / total),
  phase, last render event, render mode ("active · …", "inactive · …", "background · …": the
  app phase, the engine and its host's routing), paragraphs ready ahead, what the last background stretch played, and recent log lines.
- **Listen debug panel** (Settings › Developer › Listen Debug Panel, or long-press ▶︎): the same plus buffer / starve /
  handoff numbers, the audio-session state, each voice library's own sections
  (`SpeechEngineProvider.debugSections`; Kokoro's route toggle and ONNX threads), and the last
  lines of `ListenDebugLog`; Debug builds add the engine probe and Kokoro's CPU route benchmark.

**Timing log.** `Application Support/ListenTiming/timing.jsonl` (rotates at 2 MB to
`timing.1.jsonl`): launch, open, play, model load, every `synth` call (chars, wall ms, audio s,
phonemes, `mem_mb`), chunk / paragraph ready and failed, waits, first audio, buffering, Apple
fallback, skips, app phase and background events, remote commands, interruptions, migrations,
cache prunes, chapter boundaries (`chapter_advance`, `chapter_staged`, `chapter_boundary`), a
session stopped rather than moved onto a key holding other text (`session_rekey`), background
bursts (`bg_render_burst_start` with `ready_ahead_s`; `bg_render_burst_stop` with `ready_ahead_s`,
`reason`, `chunks`, `wall_s`, `cpu_s` and `cpu_pct`, the process's CPU over wall time, 100 = one
core) and ONNX thread switches (`kokoro_cpu_threads_switch`).
A few lines (`chapter_advance`, `chapter_boundary`) also go to the unified log, readable live in
Console.app with the filter `subsystem:com.jimmyyao.Reader category:ListenTiming`. Pull the
file from a device:

```sh
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier com.jimmyyao.Reader --source "Library/Application Support/ListenTiming" \
  --destination /tmp/timing
```

**Debug-build tools** (launch arguments compile only in Debug; `LaunchOptions` parses them and
`AppComposition` / `LaunchHooks` hand them on):

- `-engineProbe [-probeOnly Kokoro]` or the panel's "Run engine probe": per engine, init,
  first-chunk latency and wall vs audio time for 60 / 150 / 400 characters, into
  `Documents/engine_probe.txt` (written before each step, so a crash shows where it died). Like
  the stress run and the CPU route benchmark it runs with the model to itself
  (`LocalTTSCoordinator.withRenderingQuiet`): the app's load settles, the render worker holds and
  the app's host goes (a second loaded copy of the same Core ML models fails on device, and a
  second ORT session doubles the memory), then it builds its own host per engine; the queue's next
  render loads the app's engine again.
- `-bakeArticle <saved id prefix>`: render that saved article top-down in the foreground without
  playing it, then pull ListenTiming and TTSCache.
- `-seedDemoBook`: a synthetic book (a skipped title page and three chapters of about a minute and
  a half each) and one article in no folder (`DemoBook`), replacing what an earlier launch seeded and
  leaving the rest of the library alone: it removes only rows it marked (the book by its
  `sourceIdentifier`, the article by `DemoBook.looseArticleMarker`), and gives no seeded article an address
  another article already has. `-chainDemoChapters`: once launched, play it from where
  Continue would, after the on-device engine has loaded, and let it carry on; each boundary logs
  `chapter_boundary`. Together, the locked-screen chapter-boundary check.
- `-importTestEPUB`: *Import from…* takes a synthetic EPUB built in code (`TestEPUB`: a title
  article, then the demo book's three chapters, the first with a line loose in a `<div>` and a
  footnote) instead of opening the Files picker, which a probe or UI test can't drive; the import sheet
  and import are the real ones. `-playTestEPUB`: at launch, import it into the Library's top
  level (no sheet; an earlier import of it is deleted first, with its audio), then play it from
  where Continue would (chapter 1, not the title page). The offline test pages' page one links to
  the same book as a `blob:` URL, for the `.epub` link path.
- `-selectEngine local.kokoro|apple`, `-kokoroUnits <label>` (Core ML route routing).
- `-KokoroStress coreml|onnx` (`KokoroStressRun`): with the app in front, renders a fixed corpus
  of 320 Kokoro calls (paragraphs of 1 to 10 sentences from the demo book, cut by the ONNX
  chunker) through one route: `KokoroHost` alone or `KokoroCPUHost` at the front thread count.
  The app's Kokoro host is unloaded and the queue paused. `Documents/KokoroStress/<route>.jsonl`
  gets a synced `begin` line before each call and an `end` line after it (wall ms, audio s, RTF,
  ms per audio second, stage or ONNX ms, memory, thermal). Launched again with the same argument
  after a crash, it counts the crash at the call that began (with the Core ML breadcrumb's stage)
  and carries on from the next call, stopping at 5 crashes; at the end
  `Documents/KokoroStress/<route>-summary.json`. `-KokoroStressCalls N`, `-KokoroStressFresh`.
  Pull with `xcrun devicectl device copy from --device <id> --domain-type appDataContainer
  --domain-identifier com.jimmyyao.Reader --source Documents/KokoroStress --destination <dir>`.
- **CPU route benchmark** (panel → "CPU route benchmark"): `KokoroONNXSession` at 1–6 threads and
  QoS variants on a fixed 501-phoneme passage and its first three sentences (load ms, cold / warm
  times, × real time, CPU-s per audio-s, thermal, memory), plus a lock-screen soak that renders
  continuously for N minutes. The benchmark pauses the queue, lets the app's host go and holds the
  render gate; the soak runs beside listening. Output
  `ListenTiming/cpubench.jsonl` and a sample WAV.

Measure on a device with a **Release** build: FluidAudio in Debug is ~3× slower per decode step.
To use these tools in an optimized build, build Release with `READER_EXTRA_CONDITIONS=DEBUG`
(`project.yml`: it adds `DEBUG` to the app target only; the packages stay Release).

## Verify

- Apple: while audible the button shows Pause, and a tap always pauses.
- Kokoro: Play continues past paragraph 1; Pause mid-paragraph and Play resume at the same spot.
- A partly rendered article starts from the cache for rendered units.
- Consecutive paragraphs have near-zero gaps when rendered ahead.
- A unit Kokoro can't render plays with Apple; playback never goes silent or freezes.
- Skip / jump re-prioritizes from the new playhead; after listening from mid-article, rendering
  returns to the top (in front) so the whole article ends up on disk.
- Background: baked audio plays, the playing article renders in bursts on one thread on the ONNX
  route (`bg_render_burst_*` lines; the app survives a locked listen), nothing
  renders with Core ML.

Playback is verified by probing the running app (the launch arguments above, the debug log,
`ListenTiming`) and on the phone for timing and background behavior. Unit tests pin only the
chunking and long-paragraph split invariants (`TextChunkerTests`, `ParagraphSplitTests`) and the
engine crash guard's marker (`EngineCrashGuardTests`).

## Retention and Prepared Audio (C134, C135, C136)

- **Three states.** *Prepared*: saved and you chose *Prepare Audio*; its audio is never cleared automatically. *Saved*: in the Library; listening renders audio as it goes, and saving or starring no longer renders the whole article. *Being read*: opened or played without saving, listed in Recent.
- **Recent is the last 50 articles started.** At launch and when an article starts, unsaved articles beyond those 50 are deleted with their audio; saved articles beyond them lose only their audio from listening. Audio the session or the staged chapter needs is never touched. The finished-chapters trim skips prepared audio.
- **Prepared Audio list** (⋯ › Prepared Audio, Settings): the prepared sections (Now, Waiting, Prepared, Different Voice) and **From Listening** (audio rendered while listening, no ↓, with a footer about Recent 50); every row names its voice (C138). Every row has *Delete Audio* (swipe and ⋯), which never deletes the article. The list's ⋯ (`MenuRegistry`, `.deleteAllPrepared`, `.clearListeningAudio`) has **Delete All…** ("Delete N articles and their prepared audio? This can't be undone.": deletes every prepared article and its audio, folders stay) and **Clear Audio From Listening…** (that audio only), each shown only when its section has rows.
- **Naming.** The feature is *Prepare*, in the UI and in code (`PrepareCenter`, `PrepareRecord`, `PreparedAudioSheet`, `Features/PreparedAudio`). *Download* stays only for real file downloads (voice models, the CPU model, EPUB files). On-disk names are kept: `Downloads.json`, its keys, `downloads.wordsPerSecond`.
