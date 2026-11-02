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
- **Generic rules, no site rules.** `TableOfContents.readers` (Core/Sources) is three
  `ContentsReader`s, first that finds a list wins: the page's list of links (`Generic`), the page a
  chapter or post links back to (`Parent`: the link whose path is the longest proper prefix of the
  page's own, never the root; one more fetch), a feed (`Feed`, the page's own or advertised).
  Don't add a rule for one host; nothing in Features checks one. **Feed is last on purpose**: a
  serial's feed holds only its last ten chapters and its chapter pages advertise it, so a feed first
  lists 10 of 109 chapters. The list gate (at least half the list's links chapter-like or dated)
  keeps a blog's archive, or an author's "3 Fictions / 0 Posts" links, from passing as a chapter
  list. *Posts* = a feed or a dated list running newest first; else *Chapters*. The contents URL
  stored on the folder is the page or feed the list was read from; a check reads it again through
  the same rules. The site name is `og:site_name` or the host, kept in `FollowState.siteName`.
  Dates come from `<time datetime>` (a page whose script fills it in is undated).
  New posts of a *Posts* folder still go at its end, like chapters (see FUTURE).
- **Text lands in place, nothing renders** (`LibraryStore.storeFetchedText`): the folder's Prepare
  switch decides audio. The chapter keeps its key, title and place.
- **A story is `FolderKind.series` with a `FollowState`.** The waiting-chapter rule is one
  property, `Article.isWaitingChapter`; playback stops before such a chapter (`ChapterAdvance`).
  `play` and `status(of:)` take any link page (*Add a Link…*'s too): ▶ fetches it, then plays; only a
  story's chapters are fetched by the loop or show *Waiting*.
- **One input and review sheet.** Add a Link and a known page’s Follow use `FollowFlow` and
  `FollowSheet`; `InputSheet` owns only the common framing. Add a Link starts at medium, reads
  through `FollowCenter`, and grows to large for the shared chapter review. A non-story or failed
  read saves the original URL with `LibraryStore.saveLink`, into the folder on screen; an address
  already in the Library is left where it is (a toast says so). The story’s folder stays at the top
  level. Cancelling a contents read never saves; ✕ during a save cancels it and nothing is stored. A
  failed save leaves the sheet up with its reason. A known page’s Save This Page Only uses
  `ArticleActions`’ save path at `.keep` (never moving the page) and waits for browser extraction
  and persistence before closing; it never toggles an already saved page off.
- **Preview and sheet gestures.** Follow is a system sheet. While its chapter preview is open the
  sheet's only detent is large and interactive dismissal is disabled, so the preview’s own pull
  closes it without resizing or losing the review.
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
- **Probes**: `-browseTestPages` page one links to `reader-test://story/toc`, to a chapter of a
  serial shaped like a serial site (`reader-test://serial/story/40512/the-copper-orchard`: chapters
  table, chapters linking back, none listing) and to a blog with an RSS feed (`reader-test://blog/`);
  both in `App/Fixtures/TestSitePages.swift`. Add a Link with `-addLinkText … -submitAddLink`; `-testStoryChapters N`
  lengthens it (a check then finds new chapters); `-testStoryThrottles` makes chapter 6 fail once.
  A custom scheme's reply carries no HTTP status, so a real 429 is checked against a live site.
