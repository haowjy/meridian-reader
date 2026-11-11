# Verifying a change on the running app

A change is shown to work by driving the real app (the Simulator, or the phone for anything that
needs real hardware) and looking at the result, then by an AI review of the diff. The unit tests
guard only a few costly regressions; this page is what replaces the UI tests.

## What to check by hand

Check the flows a change touches. For motion, record a video and pull frames.

- **Save and play a browsed article**: open a page, save it, play, pause, stop.
- **The compact chrome** (`docs/NAVIGATION.md`, "Bottom chrome"):
  - On Browse web and Library home a scroll down folds the bottom chrome into its bubble; a scroll
    up of 24 pt or a tap on the bubble brings both rows back.
  - On Browse reader and Library Read in Scroll mode, 60 pt down in one gesture goes full screen
    (top group, chrome and status bar together), and 24 pt up brings them back. Pages mode never
    goes full screen by scroll. Library Edit stays expanded.
  - Listen slides up over the chrome, and a pull down closes it back to where you were; a pull
    pushed back up before release keeps it. Listen's floating pause pauses in full screen.
  - An in-place reader's full screen is the text alone, its background to the screen's foot and
    its last line scrolling just clear of the home indicator's strip.
- **Regular width**: a change to shell chrome is probed on an iPhone and an iPad Simulator.

## Launch arguments

Probes drive the app with launch arguments, Debug builds only. Every one is documented where it is
parsed, in `App/LaunchOptions.swift`; diagnostics (`-engineProbe`, `-KokoroStress`) are in
`docs/LISTEN_PLAYBACK.md`, "Diagnostics".

```sh
xcrun simctl launch <device> com.jimmyyao.Reader <args>                       # Simulator
xcrun devicectl device process launch … com.jimmyyao.Reader -- <args>         # phone
```

The ones most probes start from:

- `-uiTesting`: test markers on, still playing bars, Google suggestions off.
- `-resetLibrary`: stored settings cleared and the library emptied, as on a fresh install; it opens
  Listen paused on the welcome article. Add `-skipWelcome` for the empty start.
- `-selectEngine local.phonon` (or `local.kokoro`, `test.voice`); `-testVoice` renders prepared
  audio offline.
- Seeds: `-seedDemoArticle`, `-seedDemoBook`, `-seedDemoFolders`, `-seedMarketingLibrary` (the App
  Store screenshots' library), `-seedHistory`.
- `-browseTestPages`: offline `reader-test://` pages. Keep probes offline: use these, not live
  sites. `-openURL` is for screenshots only.
- `-readerProbe STEPS` scripts scrolls and taps on the first reading page and logs
  `ReaderProbe step=… fullScreen=…` after each.

Stored settings a launch overrides go through UserDefaults' argument domain instead
(`-reader.developerOptions YES`, `-reader.listenDebugEnabled YES`, `-reader.rateMultiplier 2`).
