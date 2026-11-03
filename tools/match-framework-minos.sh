#!/bin/sh
# Xcode build phase (app target, after the frameworks are embedded).
# Some prebuilt frameworks (onnxruntime) ship an Info.plist whose MinimumOSVersion is older
# than the minos the linker writes into their binary when Xcode re-links them for this app.
# App Store Connect rejects that mismatch (ITMS-90208). This sets each embedded framework's
# MinimumOSVersion to its binary's minos and re-signs the framework.
set -eu

FRAMEWORKS="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
[ -d "$FRAMEWORKS" ] || exit 0

for fw in "$FRAMEWORKS"/*.framework; do
  [ -d "$fw" ] || continue
  plist="$fw/Info.plist"
  exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null || basename "$fw" .framework)
  bin="$fw/$exe"
  [ -f "$bin" ] || continue
  minos=$(xcrun vtool -show-build "$bin" 2>/dev/null | awk '/minos/ {print $2; exit}')
  [ -n "$minos" ] || continue
  current=$(/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$plist" 2>/dev/null || echo "")
  [ "$current" = "$minos" ] && continue
  echo "$(basename "$fw"): MinimumOSVersion ${current:-unset} -> $minos (binary minos)"
  /usr/libexec/PlistBuddy -c "Delete :MinimumOSVersion" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $minos" "$plist"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --preserve-metadata=identifier,flags --timestamp=none "$fw"
  fi
done
