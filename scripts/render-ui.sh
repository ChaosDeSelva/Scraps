#!/bin/bash
set -euo pipefail
SCRAPS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$SCRAPS_ROOT/build/qa" "$SCRAPS_ROOT/build/module-cache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$SCRAPS_ROOT/build/module-cache" \
  "$SCRAPS_ROOT/Sources/Models.swift" "$SCRAPS_ROOT/Sources/Database.swift" \
  "$SCRAPS_ROOT/Sources/Store.swift" "$SCRAPS_ROOT/Sources/Theme.swift" \
  "$SCRAPS_ROOT/Sources/CaptureView.swift" "$SCRAPS_ROOT/Sources/LibraryView.swift" \
  "$SCRAPS_ROOT/Tests/RenderUI.swift" -framework AppKit -framework SwiftUI -lsqlite3 \
  -o "$SCRAPS_ROOT/build/RenderUI"
"$SCRAPS_ROOT/build/RenderUI" "$SCRAPS_ROOT/build/qa"
