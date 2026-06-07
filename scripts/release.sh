#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# iOS release helper for the PharosVPN client (Caravel).
#
# There is NO GitHub-release artifact for iOS: the app ships via TestFlight /
# the App Store, not as a downloadable binary. This script does NOT run
# `gh release create`. It reads ./VERSION, validates the signing
# prerequisites, and prints (and can run) the archive + export-IPA steps that
# put a build on TestFlight.
#
#   scripts/release.sh             # validate prerequisites + print the steps
#   scripts/release.sh --archive   # also run xcodebuild archive + export IPA
#
# Prereqs (one-time, human, via Xcode GUI — see BUILD.md / NOTES.md):
#   * DEVELOPMENT_TEAM set (NJV3R6ZFF6) for both targets.
#   * App Group  group.org.pharosvpn.caravel  REGISTERED on the Apple account.
#     xcodebuild auto-provisioning can create App IDs but NOT App Groups, so a
#     device/TestFlight signing build fails until this is registered once in
#     Xcode → Signing & Capabilities.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="${DEVELOPMENT_TEAM:-NJV3R6ZFF6}"
SCHEME="Caravel"
APP_GROUP="group.org.pharosvpn.caravel"
PROJ="app/Caravel.xcodeproj"
BUILD_DIR="app/build"
ARCHIVE="${BUILD_DIR}/Caravel.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_PLIST="${BUILD_DIR}/ExportOptions.plist"

# 1. Validate VERSION.
if [ ! -f VERSION ]; then
  echo "ERROR: VERSION file missing." >&2; exit 1
fi
VERSION="$(tr -d '[:space:]' < VERSION)"
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
  echo "ERROR: VERSION '$VERSION' is not a valid semver." >&2; exit 1
fi
echo "PharosVPN iOS — marketing version $VERSION (from ./VERSION)"
echo

# 2. Validate signing prerequisites (best-effort, non-fatal warnings).
warn=0
echo "Signing prerequisites:"
if [ -n "$TEAM" ]; then
  echo "  [ok]   DEVELOPMENT_TEAM = $TEAM"
else
  echo "  [WARN] DEVELOPMENT_TEAM is empty — set it in Xcode or export DEVELOPMENT_TEAM."; warn=1
fi
# The App Group cannot be auto-created by xcodebuild; flag that the human must
# have registered it. We can only check that the entitlement still declares it.
if grep -Rq "$APP_GROUP" app/Caravel/Caravel.entitlements app/Tunnel/Tunnel.entitlements 2>/dev/null; then
  echo "  [..]   App Group '$APP_GROUP' declared in entitlements."
  echo "         It MUST also be registered on the Apple account (Xcode →"
  echo "         Signing & Capabilities). xcodebuild cannot create App Groups;"
  echo "         a signing/device/TestFlight build fails until it is registered once."
else
  echo "  [WARN] App Group '$APP_GROUP' not found in entitlements."; warn=1
fi
echo

# 3. Print the TestFlight release path.
cat <<EOF
TestFlight release path (NOT a GitHub release):

  # archive a signed, App-Store-bound build
  xcodebuild archive \\
    -project ${PROJ} \\
    -scheme ${SCHEME} \\
    -destination 'generic/platform=iOS' \\
    -archivePath ${ARCHIVE} \\
    -allowProvisioningUpdates \\
    DEVELOPMENT_TEAM=${TEAM} \\
    MARKETING_VERSION=${VERSION}

  # export an .ipa from the archive (app-store-connect method)
  xcodebuild -exportArchive \\
    -archivePath ${ARCHIVE} \\
    -exportOptionsPlist ${EXPORT_PLIST} \\
    -exportPath ${EXPORT_DIR} \\
    -allowProvisioningUpdates

  # upload to TestFlight (then promote in App Store Connect):
  xcrun altool --upload-app -f ${EXPORT_DIR}/${SCHEME}.ipa -t ios \\
    --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
  # …or drag the .ipa into Xcode's Organizer / Transporter.app.

Reminder: register the App Group '${APP_GROUP}' once (Xcode → Signing &
Capabilities) before any of the above will sign. See BUILD.md / NOTES.md.
EOF

# 4. Optionally run the archive + export.
if [ "${1:-}" = "--archive" ]; then
  if [ -z "$TEAM" ]; then
    echo "ERROR: cannot archive with an empty DEVELOPMENT_TEAM." >&2; exit 1
  fi
  echo
  echo ">> running xcodebuild archive…"
  mkdir -p "$BUILD_DIR"
  # A minimal app-store export options plist.
  cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>${TEAM}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
  xcodebuild archive \
    -project "$PROJ" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    MARKETING_VERSION="$VERSION"
  echo ">> exporting .ipa…"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates
  echo ">> done: ${EXPORT_DIR}/${SCHEME}.ipa"
fi

[ "$warn" = 1 ] && echo && echo "(one or more prerequisites need attention — see [WARN] above)"
exit 0
