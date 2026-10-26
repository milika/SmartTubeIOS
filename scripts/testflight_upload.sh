#!/bin/bash
# testflight_upload.sh - archive the iOS app and upload it to App Store Connect for
# TestFlight. Only on the owner's request for that upload.
#
#   scripts/testflight_upload.sh <build>   # higher than any build uploaded for this version
#
# Archives Release for generic iOS, then exports with method app-store-connect /
# destination upload and automatic signing, through the Apple account signed in to Xcode
# (Settings > Accounts). Output under ~/DevTemp/smarttube.
#
# Identity comes from SmartTubeApp/Config/Base.xcconfig (team) and Config/Secrets.xcconfig
# (local overrides). The build number is passed on the xcodebuild command line, which
# applies it to the app and every embedded extension at once, so nothing in the repo has
# to be rewritten (and no "commit the project file after" step).
set -uo pipefail
BUILD="${1:?usage: scripts/testflight_upload.sh <build number>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$HOME/DevTemp/smarttube"
OUT="$D/scratch/testflight"
CONFIG="$ROOT/SmartTubeApp/Config/Base.xcconfig"
EXPORT_PLIST="$OUT/export_options.plist"
mkdir -p "$OUT" "$D/logs"

VERSION=$(grep -m1 -E '^MARKETING_VERSION = ' "$CONFIG" | awk '{print $3}')
[ -n "$VERSION" ] || { echo "could not read MARKETING_VERSION from $CONFIG" >&2; exit 1; }

# The effective team (Secrets.xcconfig may override Base.xcconfig).
TEAM=$(/usr/bin/xcodebuild -project "$ROOT/SmartTubeApp/SmartTubeApp.xcodeproj" -target SmartTube \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^ *DEVELOPMENT_TEAM = / {print $2; exit}')
[ -n "$TEAM" ] || { echo "could not resolve DEVELOPMENT_TEAM; check Config/Secrets.xcconfig" >&2; exit 1; }

ARCHIVE="$OUT/SmartTube-$VERSION-$BUILD.xcarchive"
rm -rf "$ARCHIVE" "$OUT/export-$BUILD"
echo "archiving $VERSION ($BUILD) for team $TEAM..."
/usr/bin/xcodebuild -workspace "$ROOT/SmartTube.xcworkspace" -scheme SmartTube -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$D/derived-data/archive" \
    -archivePath "$ARCHIVE" -allowProvisioningUpdates \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive >"$D/logs/archive-$BUILD.log" 2>&1 \
    || { grep -E 'error:' "$D/logs/archive-$BUILD.log" | head -8; echo "archive failed: $D/logs/archive-$BUILD.log" >&2; exit 1; }
got=$(/usr/libexec/PlistBuddy -c 'Print ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")
[ "$got" = "$BUILD" ] || { echo "the archive is build $got, not $BUILD" >&2; exit 1; }

cat >"$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "uploading $VERSION ($BUILD) to App Store Connect..."
/usr/bin/xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$OUT/export-$BUILD" -allowProvisioningUpdates >"$D/logs/upload-$BUILD.log" 2>&1
rc=$?
grep -E 'Upload succeeded|error|Error' "$D/logs/upload-$BUILD.log" | head -8
[ $rc -eq 0 ] && grep -q 'Upload succeeded' "$D/logs/upload-$BUILD.log" || { echo "upload failed: $D/logs/upload-$BUILD.log" >&2; exit 1; }
echo "$VERSION ($BUILD) uploaded."
