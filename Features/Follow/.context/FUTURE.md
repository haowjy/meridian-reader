# Follow: deferred

- **A serial whose chapters don't sit under the story's path still offers its navigation as
  chapters.** A WordPress serial chapter at `/2017/03/03/rw1-00/` links "Previous Chapter",
  "Table of Contents" (`/table-of-contents/`) and "Next Chapter": no link is an ancestor of the
  page, and two of three read as chapter-like, so the list rule offers those three links as the
  story's *Chapters*. Fix direction: a rule that ends the class, such as requiring more than three
  links when every link is in one short list (or a list that is only prev/next/contents wording),
  so the page falls through to its contents page.

- **A blog's archive or post reads as nothing, because a feed is used only from its exact home
  address.** Tracked as [issue #29](https://github.com/haowjy/meridian-reader/issues/29), with the
  probe table and the proposed change (compare hosts, not addresses).

- **Limit a follow to the newest X.** Wanted for the next version, not scheduled (owner,
  2026-11-03). Following takes everything the list holds: Hacker News's front page is 30 entries,
  a blog's feed 25, a story's contents its whole archive — so Review opens with every row checked
  and Follow makes a folder of all of them. Today's workaround is *Select All*, which clears, then
  tick what you want.

  Shapes to weigh; none decided:
  - **Review checks the newest X** (say 10) instead of everything, *Select All* unchanged. One
    place, no stored setting, and the number can follow the list's kind (posts and chapters want
    different ones).
  - **A cap on what a check adds** per run, so a followed front page grows gradually.
  - **A limit remembered per folder** (a new optional field in `FollowState`, so no migration),
    applied when following and at each check.
  - **A cap on the folder's size**, dropping the oldest as new ones arrive. The most literal
    reading of "last X", and the one to be careful with: a folder's rows are library pages that can
    hold a position, prepared audio and saved state, so dropping one destroys something the user may
    have been listening to.

  Keep the reader simple and generic while doing it: no rule names a site, and no rule decides what
  a list means beyond *Chapters* or *Posts*. A list read wrongly shows up in Review as wrong rows
  with *Save This Page Only* under them, so how much to keep belongs in Review as the user's
  choice, not in detection. Whichever shape lands, the count Review shows and the Follow button's
  label must agree.
