# Meridian Reader

iOS offline article listening: browse → extract → save → speak (Apple TTS + on-device voices).

## Open / run

```bash
cd ~/Developer/repos/meridian-reader
xcodegen generate
open Reader.xcodeproj
```

Pick an iOS Simulator and Run. (Xcode target / bundle id remain `Reader` / `com.jimmyyao.Reader` for now.)

## What’s in here

- Browse + Reader chrome (Safari-style ⋯ morph menu, five-slot toolbar)
- SwiftData library (Saved), bookmarks, history
- Live-DOM Readability extraction behind `ArticleExtracting`
- Listen: paragraph / sentence scrubbing, speed in place, mini player, lock screen
- On-device TTS (Kokoro via vendored FluidAudio) with Apple fallback

See `docs/` (especially `NAVIGATION.md`) for behavior notes.

## Extraction

Default extractor is `ReadabilityArticleExtractor`:
1. Snapshot live page HTML from `WKWebView`
2. Parse with bundled Mozilla `Readability.js` in an off-screen WebView
3. Still behind `ArticleExtracting` (Fake extractor available via developer Debug menu)

See `docs/EXTRACTION_SPIKE.md` for the test matrix.

### Manual check
1. Run on Simulator
2. Browse → open a real article URL (news/blog)
3. Tap **Reader** / **Save** — expect clean text
4. Try a homepage — expect failure, nothing saved

## Requirements

- Xcode with iOS 17+ SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
