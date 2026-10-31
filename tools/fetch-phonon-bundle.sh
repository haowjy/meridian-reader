#!/bin/sh
# Puts the Phonon model bundle the app ships at Resources/PhononBundle/ (git-ignored: ~170 MB).
# Downloads the bundle zip (or takes one you already have), checks its size and SHA-256 against
# the constants below, and extracts it. Run once per checkout, and again when the bundle changes;
# the app build fails without it. The bundle is Phonon 31m English exported by ptts 0.6.0 at a
# 200-token prefill, published as a release on haowjy/xn-ptts (docs/TTS_ENGINES.md, "Phonon").
#
#   tools/fetch-phonon-bundle.sh            # download
#   tools/fetch-phonon-bundle.sh <zip>      # use a zip already on disk
set -eu

URL="https://github.com/haowjy/xn-ptts/releases/download/phonon-31m-en-200-v0.6.0/phonon-31m-en-coreml.zip"
SHA256="6b06b2716f7abed64ebae60a45ef097a2e746010684568627aa61edddd50c8f4"
BYTES=137092920
ROOT_NAME="phonon-31m-en-coreml"

repo="$(cd "$(dirname "$0")/.." && pwd)"
dest="$repo/Resources/PhononBundle"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ $# -ge 1 ]; then
    zip="$1"
else
    zip="$work/bundle.zip"
    curl -fL --retry 3 -o "$zip" "$URL"
fi

size=$(stat -f %z "$zip" 2>/dev/null || stat -c %s "$zip")
[ "$size" = "$BYTES" ] || { echo "size $size, expected $BYTES" >&2; exit 1; }
sum=$(shasum -a 256 "$zip" | cut -d' ' -f1)
[ "$sum" = "$SHA256" ] || { echo "SHA-256 $sum, expected $SHA256" >&2; exit 1; }

mkdir "$work/x"
unzip -q "$zip" -d "$work/x"
[ -f "$work/x/$ROOT_NAME/bundle.json" ] || { echo "no $ROOT_NAME/bundle.json in the zip" >&2; exit 1; }
rm -rf "$dest"
mv "$work/x/$ROOT_NAME" "$dest"
echo "Phonon bundle at $dest"
