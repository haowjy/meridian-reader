# Invariants: how the code keeps them

The rules are in the root `AGENTS.md`, each with its reason. This page says, for each, what keeps
it, what checks it, and where that falls short.

## Closing a screen never stops audio

- **Kept by:** `ShellState` holds no playback: it only asks the session through the injected
  `isHearing`, so no close path (`readerDidClose`, `nowPlayingDidClose`, a destination switch) can
  stop audio. `PlaybackSessionState` alone decides playback.
- **Checked by:** hand only: play, then close or leave each screen (`docs/NAVIGATION.md`, "✕ =
  modal + swipe-down": "Closing never stops audio").
- **Falls short:** nothing stops a new close path from calling `SpeechController` directly.

## An article plays in one voice

- **Kept by:** the audio cache keys audio by voice; audio rendered in another voice never counts
  as prepared or plays.
- **Checked by:** `Tests/PrepareOverviewTests.swift`.

## Playback never changes the voice on its own

- **Kept by:** an article plays in its own voice (`LocalTTSCoordinator.selection(for:)`) or not
  at all; when that voice's engine can't go on, playback waits or pauses and says why
  (`SpeechController.tell`, shown as the shell's toast; a stopped engine's carries Retry). Prepared
  audio renders in that voice too. Only the user changes a voice (Settings › Voice, an article's
  or book's *Voice*); a launch migration may rewrite a stored voice that no longer exists.
- **Checked by:** the render queue refuses a plan that puts work on another engine's route
  (`RenderPlan.violation`, an `assertionFailure` in `GlobalSynthQueue+Render.swift`, so Debug
  only); `docs/LISTEN_PLAYBACK.md`, "One voice, never swapped".
- **Falls short:** Release builds don't assert; a fallback added outside the render queue
  wouldn't be caught.

## Saved text and on-device voices work with no network

- **Kept by:** Phonon's model bundle ships in the app (`Resources/PhononBundle/`); Kokoro's model
  downloads once and stays; saved articles keep their text in the library.
- **Checked by:** hand only: an airplane-mode run of a saved article.

## A navigation gesture does exactly what its button does

- **Kept by:** ‹ screens are real `NavigationStack` pushes with the system back button; sheets are
  `.sheet` or the design system's `Sheet`, whose pull and close button call one close action, and
  every pull-to-dismiss commits by one rule (`SwipeGesturePolicy.shouldCommitDownwardDismiss`).
  Leaving side effects go in `onDisappear`.
- **Checked by:** hand only (`docs/NAVIGATION.md`, "Navigation rule").

## No system tab bar

- **Kept by:** compact width draws its own chrome (`Features/Shell/Chrome/ChromeHost.swift`).
- **Checked by:** `rg "TabView|UITabBar" Features App` finds nothing; nothing runs it
  automatically.

> [!FLAG] **Needs human review**: should any of these current choices be an invariant? Each is
> kept with its reason where it lives: one owner of the playhead, persisted ids change only with a
> migration, voice libraries stay behind the registry, no real people's content in the repo (root
> `AGENTS.md`); every chunk fits its engine's limit and engine prep never drops words
> (`docs/TTS_ENGINES.md`); Kokoro on ONNX only; no silent large download on cellular; iPad layout
> gated on regular width; CloudKit-shaped models; nothing collected. Also: is "no system tab bar"
> the whole rule, or should it name the destinations? Flagged 2026-11-10.
