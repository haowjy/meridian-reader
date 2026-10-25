# Shell

Navigation state (`ShellState`), the ⋯ menu's content, the Now Playing bar, and the iPad sidebar and
clustered dock. Working notes and contracts: [`.context/CONTEXT.md`](.context/CONTEXT.md). What the
user sees: [`docs/NAVIGATION.md`](../../docs/NAVIGATION.md).

- **Compact width draws one chrome host** (`Chrome/ChromeHost.swift`) with three destinations (Reader,
  Library, Browser): `docs/NAVIGATION.md`, "Bottom chrome". Each destination hands the host a
  `ChromeScreen` (field, arrows, ⋯); the Reader and Now Playing hand it their player card
  (`ChromeCard`). One state (`ChromeState`), one pure layout (`ChromeLayout`, from `ChromeMetrics`:
  `barHeight` 48, footprints 116 and 60, ▶ in one slot left of ⋯) and one scroll controller
  (`ChromeScroll`, a continuous progress, the Reader re-expands on scroll up like the others); the host
  draws translucent glass (`ChromeSkin`; App sets `ChromeSkin.forcesMaterial` for `-chromeFallback`)
  with only a gradient fade behind. Screens reserve `ChromeMetrics.footprint` at the bottom (the Reader
  `readerFootprint`) (`CompactChromeInsets`) and report their scroll with `CompactChromeScroll`.
  `SurfaceBand` remains for regular width. Every piece is a capsule or circle one 48 pt high; the Reader
  is a destination under the chrome (no sheet, Close pill or pull-down); full screen is a middle tap;
  the compact address pill ends in reload (iPad's field keeps 🎧). Change the host, never one screen.
- **Two size classes.** iPad layout is gated on `horizontalSizeClass == .regular` and compact (iPhone,
  iPad in a compact window) draws the chrome host; regular width keeps `SurfaceBand` and the dock. When you touch shell chrome, check both.
- **Sizes are tokens** in `../DesignSystem/Tokens/RegularLayout.swift`; don't hard-code a width in a view.
- Add a screen as a case in `ShellState`, not a presentation flag in a view.
