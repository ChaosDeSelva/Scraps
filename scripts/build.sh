#!/bin/bash
set -euo pipefail
SCRAPS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRAPS_BUILD="$SCRAPS_ROOT/build"
SCRAPS_APP="$SCRAPS_BUILD/Scraps.app"
mkdir -p "$SCRAPS_APP/Contents/MacOS" "$SCRAPS_APP/Contents/Resources" "$SCRAPS_BUILD/module-cache"
swiftc -swift-version 5 -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$SCRAPS_BUILD/module-cache" \
  "$SCRAPS_ROOT"/Sources/*.swift -o "$SCRAPS_APP/Contents/MacOS/Scraps" \
  -framework AppKit -framework SwiftUI -framework Carbon -lsqlite3
cp "$SCRAPS_ROOT/Resources/Info.plist" "$SCRAPS_APP/Contents/Info.plist"
if [ -f "$SCRAPS_ROOT/Resources/AppIcon.icns" ]; then
  cp "$SCRAPS_ROOT/Resources/AppIcon.icns" "$SCRAPS_APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$SCRAPS_APP"
printf 'Built %s\n' "$SCRAPS_APP"
