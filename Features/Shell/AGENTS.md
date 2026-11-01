# Shell

Navigation state (`ShellState`), the ⋯ menu's content, the Now Playing bar, and the iPad sidebar and
clustered dock. Working notes and contracts: [`.context/CONTEXT.md`](.context/CONTEXT.md). What the
user sees: [`docs/NAVIGATION.md`](../../docs/NAVIGATION.md).

- **Compact width draws one chrome host** (`Chrome/ChromeHost.swift`) over three destinations (Library,
  Browser, Settings: `docs/NAVIGATION.md`, "Bottom chrome"). Row 1 is the screen's field and the Listen button
  (`ChromeListenButton`), row 2 the pill alone; there is no ⋯ or ▶ in the chrome. Each destination hands the
  host a `ChromeScreen` (field, arrows, bubble title). A screen's ⋯ is on its title line (`TitleMenuButton`,
  `LibraryTitleMenu`, drawing `MenuContext.blocks`); the Browser's is `AddressField`'s `holdMenu`. One state (`ChromeState`), one pure layout (`ChromeLayout`, from
  `ChromeMetrics`: `Control.chrome` 40, 92 pt of rows ending on the home indicator's strip) and one scroll controller (`ChromeScroll`: on a
  folding screen a scroll down folds it; a scroll up of `revealDistance`, the bubble's tap or the top of the text expand it); Library Read and Browse reader
  mode open in place via `ReaderSurface` and feed it; their ⋯, Aa and ▶ Listen are the reading pages' top group
  (`ReadingTopGroup`, the page's header, shown unless the page is in full screen), which Listen has too (⋯, Aa). The host draws translucent glass (`ChromeSkin`; App
  sets `ChromeSkin.forcesMaterial` for `-chromeFallback`) with only a gradient fade behind. Screens reserve
  `ChromeHome.clearance(step: 0)` above the safe area (`CompactChromeInsets`) and report their scroll with
  `CompactChromeScroll`, naming their `ChromeSource`. What scrolling does is `ChromeScroll.policy` (`ChromePolicy`,
  set by `ChromeHost`): `.folds` on pages, lists and Settings; `.holds` on the start page, in Edit and under
  VoiceOver; `.reads` on an in-place reader, which is expanded or full screen (`ChromeScroll.fullScreen`, the one
  value the chrome and the page's `ReadingChrome.hidden` both read), never folded. Only the driver's reports count (`ShellState.chromeDriver`,
  the surface showing, nil under Listen, the Reader, any sheet or the Files picker; every property it reads
  hands it to `ChromeScroll.drive` from its `didSet`). A new surface that scrolls needs a `ChromeSource` case and a
  `chromeDriver` branch, or its reports are dropped. Listen and the top group's ⋯ and Aa share one round face, `ChromeCircleFace`. Change the host, never one screen.
- **Listen is not under the chrome.** `isNowPlayingPresented` draws `NowPlayingScreen` above the chrome
  in `BrowseStartView.layers`, as a `Sheet` that covers the screen (`ReadingShowing.cover`), below the ⋯
  menu overlay and the sheet presenters so Voice, Save to Folder, ⋯ and the debug panel open over it.
  Its full screen is its own `ReadingChrome`; never wire it to `chromeScroll`. It has no close button:
  a pull down (grabber, card, or the text at its top) closes it (VoiceOver: escape). Its top row (the top group, the grabber between ⋯ and Aa) takes
  hold a further `Control.bar` down, unseen, over the top of the text (`Sheet`'s `grabReach`); a tap there is still the text's. Closing it must leave whatever was under it (surface,
  reader, search, fold) untouched: that is the only "back".
  Idle Listen binds the page played last paused (`SpeechController.prepare`), never a second "current
  article"; with nothing to bind it opens on *Nothing Playing* (`NowPlayingScreen`), and a showing that
  loses what it showed closes.
- **Two size classes.** iPad layout is gated on `horizontalSizeClass == .regular` and compact (iPhone,
  iPad in a compact window) draws the chrome host; regular width keeps `SurfaceBand` and the dock. When you touch shell chrome, check both.
- **Sizes are tokens** in `../DesignSystem/Tokens/RegularLayout.swift`; don't hard-code a width in a view.
- Add a screen as a case in `ShellState`, not a presentation flag in a view.
- **Settings is a surface on compact width only** (`Surface.settings`, `showSettings()`, `settingsPath`,
  `settingsSearch`); regular width presents `ShellSheet.settings`. Every entry point calls `showSettings()`,
  never `present(.settings)`. `isCompact` turning false on the Settings surface moves it to the sheet.
