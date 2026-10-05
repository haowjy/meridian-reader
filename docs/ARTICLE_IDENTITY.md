# Article identity

One article per canonical URL. The reader over a web page and the reader from the library show
the same article, with the same playhead and the same audio, whether or not it is saved; Save and
Unsave only flip the bookmark. (The reader screen itself: `NAVIGATION.md` → "The reader".)

## Rules (identity v2)

| Concern | Rule |
|---------|------|
| Canonical URL | Lowercased scheme and host, no fragment, default port dropped, tracking parameters removed (`utm_*`, `fbclid`, `gclid`, `mc_*`, `igshid`, `si`, …), trailing slash trimmed except at the root (`ArticleIdentity.canonicalURLString`, `ArticleIdentityTests`). |
| Article key | `ArticleIdentity.articleKey(canonicalURL:)` = SHA-256(namespace v2, canonical URL) → UUID. No content in the key. |
| Library page | `Page.canonicalURL`, one page per canonical URL app-wide, whatever its state (link, saved, or played without saving). `Page.key` is the audio cache key: pages made since identity v2 use the article key; pages copied from saves made before it keep that save's random id, copied verbatim at migration and never recomputed, and are found by canonical URL. |
| Open from a page | `LibraryStore.readerArticle`: the page for the canonical URL → its key, position and filled bookmark (if saved); else the URL key. A page holding text is refreshed when the listen text changed; a link stays a link. |
| Save | `LibraryStore.save` (through `ArticleSaveCoordinator`) is idempotent: the page for the canonical URL turns saved in place, keeping its folder; else a page is inserted with `key = reader key`. Once that is stored, the audio cache is only marked saved and the queue job turns non-ephemeral; nothing moves, the session and playhead are untouched. A save that can't be stored is rolled back and touches no audio. |
| Play without saving | The first play of a page the library doesn't have keeps it as a page not in the Library (`addedAt == nil`) with its text and position, pruned 7 days after it was last played. Playing a link keeps it a link and its text as a cache. |
| Unsave | A favorite stays in Favorites as a link; a page in no folder leaves the Library (kept 7 days as a played page). Its audio stays, marked ephemeral once that is saved (pruned after 7 days or past 500 MB). *Remove from Library* on a row does the same as unsaving a page in no folder; deleting a folder with its contents deletes its pages and their audio. |
| Content change | `ArticleIdentity.contentFingerprint(paragraphs:)`, over the listen blocks after anti-copy stripping, only detects change. |
| Per-paragraph reuse | Every cached paragraph stores `textHash` (`ArticleIdentity.paragraphHash`). On open, `ArticleAudioCache.reconcile` keeps matching units, moves shifted ones to their new index and drops edited ones, so only changed paragraphs re-render. |
| Older caches | v1 ephemeral dirs (URL + content key) are adopted into the v2 key on open when the v2 dir is empty; unhashed saved units are stamped with the saved copy's stored paragraphs. |
| Duplicates | `LibraryStore.dedupe` (launch, idempotent) merges pages that share a key or a canonical URL (keeper = saved over link, then furthest position, latest play, oldest), copying in content the keeper lacks and, once that is saved, merging the other's audio into the keeper, hash-reconciled (`LibraryAudioWork`). Logged as `[Library] dedupe page …`. |
| Migration | Saved articles (`SavedArticle`, frozen) were copied once into pages with the same key; a receipt saved with the copy records what was copied, so a page deleted later never comes back and rows made by an older build during a rollback are copied on the next launch. No audio moved. |

## Why content is not in the key

Pages differ from load to load even when the article doesn't: some sites randomize class names and
insert hidden anti-copy lines on every load. The visible-text snapshot (`ReaderVisibleSnapshot`)
strips most of that, but any leak would change a content-based key and re-render the whole
article. With the URL as the key and a hash per paragraph, a leak costs at most that one
paragraph. Re-extracting the article when the reader opens is expected (fast, local); it doesn't
re-render audio.
