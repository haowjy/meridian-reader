#!/bin/sh
# Records the welcome article's audio (Resources/Welcome/audio/) in the app's built-in default
# voice: builds a Debug app, launches it on the Simulator with -resetLibrary -recordWelcome (the
# article is added without bundled audio and prepared by Phonon), waits until the prepare is done,
# and copies the article's cache directory (index.json and the CAFs, converted to AAC) out of the app's container.
# Re-run it when the article's text, the audio cache's format or Phonon's model revision changes
# (a recording from another revision is ignored at install and the article renders live).
#
#   tools/record-welcome-audio.sh            # DEVICE=<simulator udid> to pick another
#
# The key is WelcomeArticle.key. Slow: Debug builds run the model about 3x slower than Release.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
device="${DEVICE:-C9977111-F5F5-43E4-9B8B-5117C5539378}"
dd="${DERIVED:-/tmp/dd-welcome-record}"
bundle=com.jimmyyao.Reader
key=5E1C0DE0-0000-4000-8000-4D52444E5244
dest="$repo/Resources/Welcome/audio"

cd "$repo"
xcodegen generate >/dev/null
gtimeout 1500 xcodebuild build -project MeridianReader.xcodeproj -scheme MeridianReader -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$dd" -quiet

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl uninstall "$device" "$bundle" 2>/dev/null || true
xcrun simctl install "$device" "$dd/Build/Products/Debug-iphonesimulator/MeridianReader.app"
xcrun simctl launch "$device" "$bundle" -uiTesting -resetLibrary -recordWelcome >/dev/null

data="$(xcrun simctl get_app_container "$device" "$bundle" data)/Library/Application Support"
echo "waiting for the prepare to finish…"
for _ in $(seq 1 360); do
    if [ -f "$data/Downloads.json" ] && grep -q '"done"' "$data/Downloads.json" && ! grep -q '"queued"' "$data/Downloads.json"; then
        break
    fi
    sleep 5
done
grep -q '"done"' "$data/Downloads.json" || { echo "the prepare did not finish" >&2; exit 1; }
xcrun simctl terminate "$device" "$bundle"

rm -rf "$dest"
mkdir -p "$dest"
cp "$data/TTSCache/$key/index.json" "$dest/"
# AAC in CAF (64 kb/s mono): a seventh of the PCM's size, the same durations; AVAudioPlayer plays it.
for caf in "$data/TTSCache/$key"/p-*.caf; do
    afconvert -f caff -d aac -b 64000 -s 3 "$caf" "$dest/$(basename "$caf")"
done
echo "recorded $(ls "$dest"/p-*.caf | wc -l | tr -d ' ') paragraphs, $(du -sh "$dest" | cut -f1)"
