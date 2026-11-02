# Follow: deferred

- **A serial whose chapters don't sit under the story's path still offers its navigation as
  chapters.** A WordPress serial chapter at `/2017/03/03/rw1-00/` links "Previous Chapter",
  "Table of Contents" (`/table-of-contents/`) and "Next Chapter": no link is an ancestor of the
  page, and two of three read as chapter-like, so the list rule offers those three links as the
  story's *Chapters*. Fix direction: a rule that ends the class, such as requiring more than three
  links when every link is in one short list (or a list that is only prev/next/contents wording),
  so the page falls through to its contents page.
