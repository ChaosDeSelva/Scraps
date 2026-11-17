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
