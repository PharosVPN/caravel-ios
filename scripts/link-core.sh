#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Link the shared Go engine (Caravel.xcframework) into the iOS app.
#
# The engine is built in the caravel core repo:
#   cd ../caravel && ./build-bindings.sh ios   # → caravel/dist/Caravel.xcframework
#
# This script copies that framework into ./Frameworks and patches app/project.yml
# to link + embed it, then regenerates the Xcode project. Run it ONCE the engine
# exists. Until then the app builds against CaravelCore's no-engine fallback
# (#if canImport(Caravel) is false) — see NOTES.md.
#
#   ./scripts/link-core.sh [path/to/Caravel.xcframework]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_SRC="$ROOT/../caravel/dist/Caravel.xcframework"
SRC="${1:-$DEFAULT_SRC}"
DEST="$ROOT/Frameworks/Caravel.xcframework"

if [ ! -d "$SRC" ]; then
  echo "error: Caravel.xcframework not found at: $SRC" >&2
  echo "       build it first:  (cd ../caravel && ./build-bindings.sh ios)" >&2
  exit 1
fi

echo "→ copying $(basename "$SRC") → Frameworks/…"
mkdir -p "$ROOT/Frameworks"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

# Re-enable the framework dependency in project.yml (idempotent): uncomment the
# linker lines we leave as markers. If you keep your own project.yml edits, you
# can instead add the dependency by hand — see the commented block in project.yml.
PROJ="$ROOT/app/project.yml"
if grep -q "linked by scripts/link-core.sh once built" "$PROJ"; then
  echo "→ enabling the Caravel.xcframework dependency in project.yml…"
  python3 - "$PROJ" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
# App target: after the NetworkExtension sdk dep, add the framework (embed+sign).
s = s.replace(
"""      - sdk: NetworkExtension.framework
      # The gomobile engine (Caravel.xcframework) is linked by scripts/link-core.sh
      # AFTER it is built, because Xcode errors on a missing XCFramework file at
      # build time. Until then the app builds against CaravelCore's no-engine
      # fallback (#if canImport(Caravel) is false). See BUILD.md / NOTES.md.""",
"""      - sdk: NetworkExtension.framework
      - framework: ../Frameworks/Caravel.xcframework
        embed: true
        codeSign: true""")
# Tunnel target: link (no embed).
s = s.replace(
"""      - sdk: NetworkExtension.framework
      # Caravel.xcframework is linked by scripts/link-core.sh once built (the app
      # target embeds it; this target just links). See BUILD.md / NOTES.md.""",
"""      - sdk: NetworkExtension.framework
      - framework: ../Frameworks/Caravel.xcframework
        embed: false""")
open(p, "w").write(s)
print("  project.yml patched")
PY
fi

echo "→ regenerating the Xcode project…"
( cd "$ROOT/app" && xcodegen generate )

echo "✓ linked. Open app/Caravel.xcodeproj, set your Team, and build to a device."
