# Shell

Navigation state (`ShellState`), the ⋯ menu's content, the Now Playing bar, and the iPad sidebar and
clustered dock. Working notes and contracts: [`.context/CONTEXT.md`](.context/CONTEXT.md). What the
user sees: [`docs/NAVIGATION.md`](../../docs/NAVIGATION.md).

- **Compact width draws one chrome host** (`Chrome/ChromeHost.swift`) with three destinations (Reader,
  Library, Browser): `docs/NAVIGATION.md`, "Bottom chrome" (the redesign's PR2 to PR4 under "Planned"). Each destination hands the host a `ChromeScreen` (field, arrows, ⋯);
  the host owns the pill, the play button, collapse (`ChromeScroll`, fed by `chromeScrollSource`; what is drawn is a `ChromeState`, laid out by the pure `ChromeGeometry` from `ChromeMetrics`) and
  the glass or strip skin (`ChromeSkin`; App sets `ChromeSkin.forcesStrip` for `-chromeFallback`). Screens reserve `ChromeMetrics.footprint` at the bottom (the Reader `collapsedFootprint`)
  (`CompactChromeInsets`) and report their scroll with `CompactChromeScroll`. `SurfaceBand` remains
  for regular width. Every piece is a capsule or circle (radius = height / 2), one 44 pt height; the Reader is a destination under
  the chrome (collapses like the other screens; full screen removes it); the compact address pill ends in reload (iPad's field keeps 🎧).
  Change the host, never one screen.
- **Two size classes.** iPad layout is gated on `horizontalSizeClass == .regular` and compact (iPhone,
  iPad in a compact window) draws the chrome host; regular width keeps `SurfaceBand` and the dock. When you touch shell chrome, check both.
- **Sizes are tokens** in `../DesignSystem/Tokens/RegularLayout.swift`; don't hard-code a width in a view.
- Add a screen as a case in `ShellState`, not a presentation flag in a view.
