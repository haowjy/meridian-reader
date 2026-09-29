# Article identity / Reader–Save unification

Status: **identity v2 + one reader screen landed** (2026-09-24). Browse Reader Mode and Saved
render the same `ArticleReaderScreen`; one article per canonical URL; Save/Unsave only flips
the bookmark.

## One reader screen

`Features/Reader/ArticleReaderScreen.swift` is the only reader UI. Entry points:

| Entry | Close | Source of `ReaderArticle` |
|-------|-------|---------------------------|
| Browse → Reader | `xmark` (hide reader, back to web page; stops this article's audio) | `ArticleLibrary.readerArticle(url:extracted:)` |
| Saved → row | `chevron.left` (pop; audio keeps playing, row shows pause) | `ReaderArticle(saved:)` snapshot in `OfflineArticleView` |

Top row (single row, no second chrome row): `[close] [title] [bookmark] [Jump]`.
`bookmark` = unsaved (tap saves), `bookmark.fill` = saved (tap unsaves). Jump (`hand.tap`) is
last; while on it fills and a slim hint banner (“Tap a paragraph… Cancel”) floats over the
article top (no reflow). Body is the shared `ArticleListenSurface` (HTMLReadingView /
ParagraphReadingView, bake marks, highlight, listen bar, Preparing next, Debug chip).

The screen holds a value snapshot (`ReaderArticle`), never the `SavedArticle` model, and Saved
pushes by value (`navigationDestination(for: UUID.self)`), so Unsave inside the reader deletes the
row without popping the screen or stopping playback.

## Identity v2

| Concern | Rule |
|---------|------|
| Canonical URL | lowercased scheme/host, no fragment, default port dropped, `utm_*` / `fbclid` / `gclid` / `mc_*` / `igshid` / `si` / … removed, trailing slash trimmed (`ArticleIdentity.canonicalURLString`) |
| Article key | `ArticleIdentity.articleKey(canonicalURL:)` = SHA256(namespace v2, canonical URL) → UUID. **No content in the key.** |
| Saved row | `SavedArticle.canonicalURL` (new column). New saves use `id = articleKey`; legacy rows keep their random id and are found by canonical URL. |
| Resolve on open (Browse) | saved row for canonical URL → its id, playhead, `bookmark.fill`; else URL key. |
| Save | `ArticleLibrary.save` is idempotent: existing row for canonical URL is reused (content refreshed if the listen text changed); else insert with `id = reader key`. Cache `migrateListenCache(key → key)` is just `markSaved` + queue job flipped to non-ephemeral. No dir move, no session rekey, no teardown. |
| Unsave | Row deleted; audio kept and marked ephemeral (TTL prune owns it). Playhead/session untouched. Saved-list swipe-delete still deletes audio. |
| Content change | `ArticleIdentity.contentFingerprint(paragraphs:)` over listen blocks (post anti-copy strip/normalize) detects change only. |
| Per-paragraph reuse | Each CAF index entry stores `textHash` (`ArticleIdentity.paragraphHash`). `ArticleAudioCache.reconcile` on open keeps matching units, moves shifted ones to their new index, drops edited ones → only changed paragraphs re-bake. |
| Legacy caches | v1 ephemeral dirs (URL+content key) are adopted into the v2 key on open when the v2 dir is empty. Unhashed saved CAFs are stamped with the saved copy's stored paragraphs. |
| Duplicates | `ArticleLibrary.migrate` (launch, idempotent): backfill `canonicalURL`; merge rows sharing it (keeper = furthest playhead, then oldest), merge audio into keeper (hash-reconciled), delete extras. Logged as `[ArticleLibrary] merge duplicate …`. |

### Why “it downloaded again” (diagnosis, 2026-09-24)

Evidence from the device container (`TTSCache/*` + `default.store`):

- *The Witch's Bond ch. 2* was saved at 15:30:15 as `8B6A33E8` (random UUID; 16 CAFs). Ten seconds
  later a new ephemeral dir `7CEE1BF1` appeared and re-baked 15 paragraphs. Recomputing the v1
  ephemeral key from the **saved** copy's text gives exactly `7CEE1BF1`, so the page content was
  identical; the re-bake happened because v1 Browse keys (URL+content hash) never matched the
  random saved id, and Save moved the audio away from the Browse key.
- *Chapter 31* (`160CEFFB`, saved, 75 CAFs) has a second full 75-CAF bake under `ADD84B5B`,
  whose key also doesn't equal the v1 key of the saved text: that copy's extracted text differed.
  Royal Road randomizes per load: every `<p>` class name and a hidden anti-theft line
  (e.g. “Support the creativity of authors by visiting Royal Road…” vs “This tale has been
  unlawfully lifted from Royal Road…”, `display:none` via a random class). The visible-snapshot
  script strips most of it, but any leak changed the v1 key → full re-bake.
- Article re-extraction on Reader tap is expected (fast, local); it was not the “download”.

v2 fixes both: the key ignores content, and per-paragraph hashes limit any leak to that one
paragraph.

## Queue reshuffle (unchanged)

1. Open article → becomes #1; synthesize from resume → end (then gap-fill).
2. Skip/jump → same article #1; cursor moves to paragraph → end, gap-fill top.
3. Open different article → new #1; previous demoted (cache kept).
4. Single Core ML worker drains #1’s next missing unit.

Saving an article that is already #1 (Save mid-listen) keeps its playhead plan; only the job's
ephemeral flag flips (`GlobalSynthQueue.setEphemeral`). Before v2 a rekeyed job kept
`isEphemeral = true` and re-marked the saved cache ephemeral after every unit (prune risk).

## Recommended next (deeper)

- **Store `lastOpenedAt` / `lastListenedAt`** on SavedArticle so dedupe can keep “most recently
  read” and the Saved list can sort by it.
- **Unsaved playhead persistence**: an `ArticleState` table keyed by article key (playhead,
  last open) so unsaved reader progress survives relaunch — then SavedArticle becomes
  “ArticleState + saved flag” and Save is literally a boolean.
- **Close semantics**: Browse ✕ stops audio, Saved ‹ keeps playing. Unify once there is a global
  mini-player (so unsaved audio can keep playing with a visible control).
- **Swipe-back** in Saved is lost because the system nav bar is hidden for the shared top bar;
  add an edge-pan gesture or a custom `UINavigationController` delegate.
- **Server-side identity hints**: prefer `<link rel=canonical>` / `og:url` from the page over the
  address-bar URL when present.
- **Content hash in extraction**: move anti-copy stripping into a tested pure function and
  fingerprint its output there, so the fingerprint is stable independent of the WebView.
