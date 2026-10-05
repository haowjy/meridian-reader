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
| Save | `LibraryStore.save` (through `ArticleSaveCoordinator`) is idempotent: the page for the canonical URL turns saved in place, keeping its folder; else a page is inserted with `key = reader key`. The audio cache is only marked saved and the queue job turns non-ephemeral; nothing moves, the session and playhead are untouched. |
| Play without saving | The first play of a page the library doesn't have keeps it as a page not in the Library (`addedAt == nil`) with its text and position, pruned 7 days after it was last played. Playing a link keeps it a link and its text as a cache. |
| Unsave | A favorite stays in Favorites as a link; a page in no folder leaves the Library (kept 7 days as a played page). Its audio stays, marked ephemeral (pruned after 7 days or past 500 MB). Deleting from the library list deletes the page and its audio. |
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

## Imported books

A book chapter has no web address; its key comes from the book (`BookIdentity`), so importing
the same file again gives the same keys, and its audio is reused.

| Concern | Rule |
|---------|------|
| Book key | SHA-256(namespace `book.v1`, `"identifier"`, the OPF unique identifier, the title) → UUID. The title is in it because editions share identifiers. An identifier that is missing or a placeholder of zeros gives `"file"` and the file's SHA-256 instead. Stored as the book folder's `sourceIdentifier`; one book folder per key. |
| Chapter key | SHA-256(namespace `book-chapter.v1`, the book key, the spine file's path, the anchor) → UUID, the anchor being the file's start, an id the book gives, or the first block's text and how many chapters before it in that file open the same way. Not through `canonicalURLString`, which drops fragments. `Page.key`; `Page.locator` keeps `href#fragment`. |
| Final keys | Chapters are settled on their listen blocks before any key is stored (`BookChapterFinalizer`): a chapter dropped or joined to a neighbour leaves no key behind; the chapter it joins keeps its own. |
| Importing a book already in the Library (D13) | *Cancel* changes nothing. *Replace* rebuilds the pages in the same folder, which keeps its place, its name and its listening (`LibraryStore.replaceBook`). A key match alone doesn't prove a chapter is the same text: a chapter whose key and listen text both match keeps everything; one whose key matches but text changed keeps its audio per paragraph (aligned by text hash) and its position only if the paragraph it is in is still there word for word, else it starts again, and playback of it stops; a chapter under a new key whose text matches an old page takes over that page's position and audio (merged, as dedupe does), and a session playing it follows. Pages no chapter comes from are deleted with their audio. |
