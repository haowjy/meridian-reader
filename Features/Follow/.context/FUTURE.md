# Follow: deferred

- **Generic Follow, beyond serials.** This is the owner's direction: "make it more generic than
  Royal Road", so you can follow any site, blog or newsletter. Planned as its own PR after #22.
  A followed address would find what to follow from three sources, in order:
  1. **A feed, when the page advertises one**
     (`<link rel="alternate" type="application/rss+xml|atom+xml">`). It gives titles, dates and
     order. Add it as a `ContentsReader` in `TableOfContents.readers`, ahead of the others.
  2. **The page's list of links** (today's `Generic`), scored on more than chapter words: dates,
     and links that repeat one shape.
  3. **No site rules. This blocks the App Store release** (the owner's call): it ships before
     the next submission. The owner wants the Royal Road code gone ("hopefully our generic thing
     can follow Royal Road"). Delete `TableOfContents.RoyalRoad` and make the generic path cover it:
     - **from a chapter to its index:** when the page has no list of chapters, follow the link on it
       whose path is the longest proper prefix of the page's own path. Royal Road's chapter
       `/fiction/<id>/<slug>/chapter/<n>/…` links to `/fiction/<id>/<slug>`; a blog post links to
       its blog. That is at most one extra fetch, through `FetchQueue`.
     - **the list:** today's scoring already prefers Royal Road's chapters table (numbered titles,
       each row's date links to the same chapter, deduped).
     - **the site's name in notices:** `og:site_name`, which `URLPageFetcher` can read with the
       author meta, falling back to the host without "www.".
     - **text and previews:** the copy, placeholders and previews that name Royal Road or use
       `royalroad.com` addresses (AddressLabel, HeaderCards,
       FollowStatus, FollowingSheet and the preview sheet's comments) switch to `example.com`, as
       AGENTS.md requires.
     - **verification:** an offline synthetic fixture shaped like that site (story page with a
       chapters table, chapter pages with the prefix link), added to the `reader-test://` pages,
       then a live check on the owner's phone.

  On screen:
  - keep Add a Link as the address entry and a known page’s *Follow…* as the direct entry;
  - the review says *Posts* or *Chapters* for what it found;
  - a blog lists newest first, a serial in order.

  Unchanged: the paced `FetchQueue`, nothing in the background, and the daily check while the app
  is open.
