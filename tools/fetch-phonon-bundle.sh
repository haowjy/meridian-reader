#!/bin/sh
# Puts the Phonon model bundle the app ships at Resources/PhononBundle/ (git-ignored: ~170 MB).
# Downloads the ptts release zip (or takes one you already have), checks its size and SHA-256
# against the constants in PhononModelStore.swift, and extracts it. Run once per checkout, and
# again when the release changes; the app build fails without it.
#
#   tools/fetch-phonon-bundle.sh            # download
#   tools/fetch-phonon-bundle.sh <zip>      # use a zip already on disk
set -eu

URL="https://github.com/gradium-ai/xn-ptts/releases/download/v0.4.0/phonon-31m-en-coreml.zip"
SHA256="10f3a99fd39256db44f826267ef21d78cca959b16c0554926344c09fde27b436"
BYTES=137096081
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
