# Shell

Navigation state (`ShellState`), the ⋯ menu's content, the Now Playing bar, the compact chrome
host, and the iPad sidebar and clustered dock. How it fits together:
[`.context/CONTEXT.md`](.context/CONTEXT.md). What the user sees:
[`docs/NAVIGATION.md`](../../docs/NAVIGATION.md).

- **Two size classes.** Regular width is gated on `horizontalSizeClass == .regular` and keeps
  `SurfaceBand` and the dock; compact (iPhone, iPad in a compact window) draws the chrome host. A
  change to shell chrome is checked at both. Sizes are tokens (`Control`, `ChromeMetrics`,
  `../DesignSystem/Tokens/RegularLayout.swift`), never a width in a view.
- **Change the chrome host, never one screen.** Every chrome measure derives from
  `Control.chrome` and `Control.tabBar` in `ChromeMetrics`; those two are the values to change.
- **Only the screen showing drives the chrome.** A new surface that scrolls needs a `ChromeSource`
  case and a `chromeOwner` branch, or its reports are silently dropped; a new input to
  `chromeOwner` needs the same `didSet` handover (`ChromeScroll.hand(to:)`) as the others.
- **Listen is not under the chrome** and its full screen is its own `ReadingChrome`: never wire it
  to `chromeScroll`. Closing Listen is the only "back" from it and must leave whatever was under it
  (surface, reader, search, fold) untouched.
- Add a screen as a case in `ShellState`, not a presentation flag in a view.
- **Settings is a surface on compact width only.** Every entry point calls `showSettings()`, never
  `present(.settings)`; regular width presents the sheet.
