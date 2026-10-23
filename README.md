# Meridian Reader

A personal iOS app for listening to web articles. Browse in the app, extract a clean copy with
Readability, save it, and listen offline with Apple's voices, Kokoro, or Phonon (on-device, selectable) running on the device.

## Open and run

```bash
cd ~/repos/meridian-reader
xcodegen generate
open MeridianReader.xcodeproj
```

Pick an iOS Simulator or a device and run the `MeridianReader` scheme. The home-screen name is
**Meridian Reader**. The app target and product are `MeridianReader`; its bundle id stays
`com.jimmyyao.Reader` so existing installs keep their data. Measure speech timing on a device with
a Release build; FluidAudio is about 3× slower in Debug.

Requirements: Xcode with the iOS 17+ SDK and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

## What's in it

- Browser with a five-slot bottom toolbar and the ⋯ morph menu
- Reader view extracted from the live article with Mozilla Readability
- Library of saved articles (SwiftData), bookmarks and history
- Listening: sentence and paragraph scrubbing, speed changes in place, mini player, lock screen
- On-device Kokoro (vendored FluidAudio and ONNX Runtime) and Phonon 31m English (ptts / Core ML, not default), with Apple speech as the fallback

The app icon source is `Resources/Brand/meridian-reader-icon-g1.svg`, exported into
`Resources/Assets.xcassets/AppIcon.appiconset`.

## Where to read next

- `AGENTS.md`: build commands, how changes are verified, layout, cross-cutting rules
- `docs/TECHNICAL_SPEC.md`: architecture, extraction, persistence
- `docs/NAVIGATION.md`: browser, reader and library navigation
- `docs/LISTEN_PLAYBACK.md` and `docs/TTS_ENGINES.md`: playback and voice engines
