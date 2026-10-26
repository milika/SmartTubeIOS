#!/usr/bin/env bash
# Fails when signing/bundle identity is duplicated outside SmartTubeApp/Config/Base.xcconfig.
#
# Xcode's Signing & Capabilities pane happily writes DEVELOPMENT_TEAM and
# PRODUCT_BUNDLE_IDENTIFIER back into project.pbxproj, which shadows the xcconfig and
# silently un-centralizes the identity. `just ci` runs this so that drift is caught.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pbx="$root/SmartTubeApp/SmartTubeApp.xcodeproj/project.pbxproj"
status=0

fail() {
    echo "ERROR: $1" >&2
    shift
    printf '    %s\n' "$@" >&2
    status=1
}

matches=$(grep -nE '(^|[[:space:]])DEVELOPMENT_TEAM(\[[^]]*\])? = ' "$pbx" || true)
if [ -n "$matches" ]; then
    fail "DEVELOPMENT_TEAM must come from Config/Base.xcconfig (SMARTTUBE_TEAM_ID), not project.pbxproj." "$matches"
fi

owned='(MARKETING_VERSION|CURRENT_PROJECT_VERSION|SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY|IPHONEOS_DEPLOYMENT_TARGET|MACOSX_DEPLOYMENT_TARGET|TVOS_DEPLOYMENT_TARGET)'
matches=$(grep -nE "(^|[[:space:]])${owned} = " "$pbx" || true)
if [ -n "$matches" ]; then
    fail "Project-level build settings shadow Config/Base.xcconfig. Delete these from the build settings UI:" "$matches"
fi

matches=$(grep -nE 'ENABLE_USER_SCRIPT_SANDBOXING = YES;' "$pbx" || true)
if [ -n "$matches" ]; then
    fail "Base.xcconfig already sets ENABLE_USER_SCRIPT_SANDBOXING = YES; only the exceptions (= NO, the targets with a Firebase dSYM phase) belong here." "$matches"
fi

matches=$(grep -nE 'PRODUCT_BUNDLE_IDENTIFIER = ' "$pbx" | grep -v 'SMARTTUBE_BUNDLE_BASE' || true)
if [ -n "$matches" ]; then
    fail "PRODUCT_BUNDLE_IDENTIFIER must be derived from \$(SMARTTUBE_BUNDLE_BASE), not hardcoded." "$matches"
fi

# Entitlements and Info.plists take the App Group / KV store from the build, never literals.
matches=$(grep -rnE 'group\.(com|org|io|net)\.' --include='*.entitlements' --include='*.plist' \
    "$root/SmartTubeApp" 2>/dev/null || true)
if [ -n "$matches" ]; then
    fail "App Group identifiers must come from \$(SMARTTUBE_APP_GROUP_ID), not literals." "$matches"
fi

# Swift reads the group through AppGroup.identifier (SmartTubeIOSCore) only.
matches=$(grep -rnE '"group\.(com|org|io|net)\.' --include='*.swift' \
    "$root/SmartTubeIOS/Sources" "$root/SmartTubeApp/Sources" "$root/SmartTubeApp/ShareExtension" 2>/dev/null || true)
if [ -n "$matches" ]; then
    fail "Swift must use AppGroup.identifier instead of a hardcoded App Group string." "$matches"
fi

if [ "$status" -ne 0 ]; then
    exit 1
fi
echo "ok: signing and bundle identity come from Config/Base.xcconfig"
