# Follow: working notes

What the user sees is in `../../../docs/NAVIGATION.md` → "Follow a story"; how fetching is paced
is `../../../docs/TECHNICAL_SPEC.md` → "Fetching an article out of sight" and "Follow".

- **One queue for every out-of-sight fetch** (`Core/Web/FetchQueue`): Review's read,
  the chapter loop, the daily checks, and Prepared Audio' link pages (`FollowCenter.fill`). Strictly
  one load at a time; a site's pause or back-off lets another site's request go meanwhile. Don't
  make a `URLPageFetcher` of your own: it would go around the pace.
- **Nothing in the background.** The loop and the checks run only with the app in front (a load
  needs the window; WebKit is suspended behind). `start()` resumes both when the app comes back.
- **Which chapter next is derived, not stored** (`nextWaiting`): ▶'s chapter, the one after the
  article playing, then the oldest story's first waiting chapter. Failures (`failures`) and the
  check retry time are in memory only, so a launch tries again.
- **`fill` dedupes by article key**: a second caller waits for the fetch in flight. A transient
  failure (429, 5xx, no answer: `FetchQueue.outcome`) is retried after the site's back-off, four
  times; anything else (404, an article with nothing to read) fails at once.
- **A site's rule for reading a story is one `ContentsReader`** in `TableOfContents.readers`
  (Core/Sources): whether it reads an address, the contents article for it, the chapters on an article,
  the site's name. The generic reader is last and matches any address. A new site is one reader
  there; nothing in Features checks a host.
- **Text lands in place, nothing renders** (`LibraryStore.storeFetchedText`): the folder's Prepare
  switch decides audio. The chapter keeps its key, title and place.
- **A story is `FolderKind.series` with a `FollowState`.** The waiting-chapter rule is one
  property, `Article.isWaitingChapter`; playback stops before such a chapter (`ChapterAdvance`).
- **Follow covers the screen** (`ShellSheet.coversTheScreen`): inside a card sheet the system's
  pan takes the preview `Sheet`'s pull down.
- **The preview is the chapter's page in Browse's `WebView`** with its own
  `WebViewStore(staysOnPage: true)`: links, forms and back / forward to another address, and new
  windows, are cancelled; the article's own load, redirects, script navigations and anything back to
  its own address run (WebKit can't tell a challenge page's script form submit from a tap). It loads like a browser tab, not through `FetchQueue`: one page a tap asked
  for, in sight. Its address and 📄 sit in the header (`AddressLabel`, read only), not at the
  bottom: no bar of its own, and the app's band is left as it is. 📄 extracts the loaded article (no
  second request) into `HTMLReadingView`. The pull
  to close is `handsPullToSheet(from:)` on the web view's scroll view; `HTMLReadingView` wires
  its own. Review's state stays: the preview never leaves Follow. An article that fails to load stays
  blank, as in the browser.
- **Probes**: `-browseTestPages` page one links to `reader-test://story/toc`; `-testStoryChapters N`
  lengthens it (a check then finds new chapters); `-testStoryThrottles` makes chapter 6 fail once.
  A custom scheme's reply carries no HTTP status, so a real 429 is checked against a live site.
