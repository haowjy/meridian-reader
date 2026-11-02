# Follow: deferred

- **Generic Follow, beyond serials.** This is the owner's direction: "make it more generic than
  Royal Road", so you can follow any site, blog or newsletter. Planned as its own PR after #22.
  A followed address would find what to follow from three sources, in order:
  1. **A feed, when the page advertises one**
     (`<link rel="alternate" type="application/rss+xml|atom+xml">`). It gives titles, dates and
     order. Add it as a `ContentsReader` in `TableOfContents.readers`, ahead of the others.
  2. **The page's list of links** (today's `Generic`), scored on more than chapter words: dates,
     and links that repeat one shape.
  3. **Site rules** (`RoyalRoad`) only where those two fail.

  On screen:
  - name it "Follow a Site" (it is *Follow…* today);
  - the review says *Posts* or *Chapters* for what it found;
  - a blog lists newest first, a serial in order.

  Unchanged: the paced `FetchQueue`, nothing in the background, and the daily check while the app
  is open.
