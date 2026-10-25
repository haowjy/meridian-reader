# Shell

Navigation state (`ShellState`), the ⋯ menu's content, the Now Playing bar, and the iPad sidebar and
clustered dock. Working notes and contracts: [`.context/CONTEXT.md`](.context/CONTEXT.md). What the
user sees: [`docs/NAVIGATION.md`](../../docs/NAVIGATION.md).

- **A chrome redesign is in progress, not shipped.** Compact width is moving from `SurfaceBand` to one
  chrome host with three destinations (Reader, Library, Browser): `docs/NAVIGATION.md`, "Planned".
  `ShellState` gains the destination; it still owns navigation. Until the PRs merge, the notes below
  describe the shipped band.
- **Two size classes.** iPad layout is gated on `horizontalSizeClass == .regular` and compact (iPhone,
  iPad in a compact window) keeps the phone chrome unchanged. When you touch shell chrome, check both.
- **Sizes are tokens** in `../DesignSystem/Tokens/RegularLayout.swift`; don't hard-code a width in a view.
- Add a screen as a case in `ShellState`, not a presentation flag in a view.
