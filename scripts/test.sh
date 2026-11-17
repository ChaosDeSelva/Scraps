#!/bin/bash
set -euo pipefail
SCRAPS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$SCRAPS_ROOT/build/module-cache"
swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$SCRAPS_ROOT/build/module-cache" \
  "$SCRAPS_ROOT/Sources/Models.swift" "$SCRAPS_ROOT/Sources/Database.swift" \
  "$SCRAPS_ROOT/Sources/Store.swift" "$SCRAPS_ROOT/Tests/StoreTests.swift" \
  -lsqlite3 -o "$SCRAPS_ROOT/build/StoreTests"
"$SCRAPS_ROOT/build/StoreTests"
swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$SCRAPS_ROOT/build/module-cache" \
  "$SCRAPS_ROOT/Sources/Theme.swift" "$SCRAPS_ROOT/Tests/AppearanceTests.swift" \
  -framework AppKit -framework SwiftUI -o "$SCRAPS_ROOT/build/AppearanceTests"
"$SCRAPS_ROOT/build/AppearanceTests"
swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$SCRAPS_ROOT/build/module-cache" \
  "$SCRAPS_ROOT/Sources/Shortcut.swift" "$SCRAPS_ROOT/Tests/ShortcutTests.swift" \
  -framework AppKit -framework Carbon -o "$SCRAPS_ROOT/build/ShortcutTests"
"$SCRAPS_ROOT/build/ShortcutTests"
