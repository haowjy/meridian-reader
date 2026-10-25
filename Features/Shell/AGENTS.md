# Shell

Navigation state (`ShellState`), the ⋯ menu's content, the Now Playing bar, and the iPad sidebar and
clustered dock. Working notes and contracts: [`.context/CONTEXT.md`](.context/CONTEXT.md). What the
user sees: [`docs/NAVIGATION.md`](../../docs/NAVIGATION.md).

- **A chrome redesign is in progress (PR1 of four, not merged).** Compact width moves from `SurfaceBand`
  to one chrome host (`Chrome/ChromeHost.swift`) with three destinations (Reader, Library, Browser):
  `docs/NAVIGATION.md`, "Planned". Each destination hands the host a `ChromeScreen` (field, arrows, ⋯);
  the host owns the pill, the play button, collapse (`ChromeState`, fed by `chromeScrollSource`) and
  the glass or strip skin (`ChromeSkin`). Screens reserve `ChromeMetrics.footprint` at the bottom
  (`CompactChromeInsets`) and report their scroll with `CompactChromeScroll`. `SurfaceBand` remains
  for regular width. Every piece is a capsule or circle (radius = height / 2), heights 52 / 56 / 48; the Reader keeps
  the chrome (row 2 only, footprint `readerFootprint`); the compact address pill ends in reload (iPad's field keeps 🎧).
  Change the host, never one screen.
- **Two size classes.** iPad layout is gated on `horizontalSizeClass == .regular` and compact (iPhone,
  iPad in a compact window) keeps the phone chrome unchanged. When you touch shell chrome, check both.
- **Sizes are tokens** in `../DesignSystem/Tokens/RegularLayout.swift`; don't hard-code a width in a view.
- Add a screen as a case in `ShellState`, not a presentation flag in a view.
