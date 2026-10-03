# Article identity

One article per canonical URL. The reader over a web page and the reader from the library show
the same article, with the same playhead and the same audio, whether or not it is saved; Save and
Unsave only flip the bookmark. (The reader screen itself: `NAVIGATION.md` → "The reader".)

## Rules (identity v2)

| Concern | Rule |
|---------|------|
| Canonical URL | Lowercased scheme and host, no fragment, default port dropped, tracking parameters removed (`utm_*`, `fbclid`, `gclid`, `mc_*`, `igshid`, `si`, …), trailing slash trimmed except at the root (`ArticleIdentity.canonicalURLString`, `ArticleIdentityTests`). |
| Article key | `ArticleIdentity.articleKey(canonicalURL:)` = SHA-256(namespace v2, canonical URL) → UUID. No content in the key. |
| Saved row | `SavedArticle.canonicalURL`. Saves use `id = article key`; rows saved before identity v2 keep their random id and are found by canonical URL. |
| Open from a page | A saved row for the canonical URL → its id, playhead and filled bookmark; else the URL key. |
| Save | `ArticleLibrary.save` is idempotent: an existing row for the canonical URL is reused (content refreshed if the listen text changed); else a row is inserted with `id = reader key`. The audio cache is only marked saved and the queue job turns non-ephemeral; nothing moves, the session and playhead are untouched. |
| Unsave | The row is deleted; its audio stays, marked ephemeral (pruned after 7 days or past 500 MB). Deleting from the library list deletes the audio too. |
| Content change | `ArticleIdentity.contentFingerprint(paragraphs:)`, over the listen blocks after anti-copy stripping, only detects change. |
| Per-paragraph reuse | Every cached paragraph stores `textHash` (`ArticleIdentity.paragraphHash`). On open, `ArticleAudioCache.reconcile` keeps matching units, moves shifted ones to their new index and drops edited ones, so only changed paragraphs re-render. |
| Older caches | v1 ephemeral dirs (URL + content key) are adopted into the v2 key on open when the v2 dir is empty; unhashed saved units are stamped with the saved copy's stored paragraphs. |
| Duplicates | `ArticleLibrary.migrate` (launch, idempotent) backfills `canonicalURL` and merges rows that share it (keeper = furthest playhead, then oldest), merging their audio into the keeper, hash-reconciled. Logged as `[ArticleLibrary] merge duplicate …`. |

## Why content is not in the key

Pages differ from load to load even when the article doesn't: some sites randomize class names and
insert hidden anti-copy lines on every load. The visible-text snapshot (`ReaderVisibleSnapshot`)
strips most of that, but any leak would change a content-based key and re-render the whole
article. With the URL as the key and a hash per paragraph, a leak costs at most that one
paragraph. Re-extracting the article when the reader opens is expected (fast, local); it doesn't
re-render audio.
