#!/bin/sh
# Crashlytics dSYM upload, guarded so fork/CI builds without a real Firebase project
# still build. Mirrors FirebaseConfiguration.isValid() in SmartTubeIOSCore — keep the two
# predicates in sync.
#
# Invoked by the "ShellScript" phases of the SmartTube (iOS/macOS) and Smart Tube (tvOS)
# targets. Always exits 0 on a skip: a missing or mismatched GoogleService-Info.plist is
# the expected state for forks, and the app disables Firebase at runtime for the same
# reason, so failing the build here would only punish contributors.
set -e

firebase_plist="${1:-${SRCROOT}/SmartTubeApp/GoogleService-Info.plist}"

if [ ! -f "$firebase_plist" ]; then
    echo "warning: No GoogleService-Info.plist at ${firebase_plist}; skipping Crashlytics dSYM upload. Firebase is disabled at runtime for this build."
    exit 0
fi

firebase_app_id=$(/usr/libexec/PlistBuddy -c 'Print :GOOGLE_APP_ID' "$firebase_plist" 2>/dev/null || true)
firebase_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$firebase_plist" 2>/dev/null || true)

if [ "$firebase_bundle_id" != "${PRODUCT_BUNDLE_IDENTIFIER:-}" ]; then
    echo "warning: GoogleService-Info.plist belongs to ${firebase_bundle_id:-<unknown>}, not ${PRODUCT_BUNDLE_IDENTIFIER:-<unknown>}; skipping Crashlytics dSYM upload. Regenerate it for this bundle ID (see Config/Base.xcconfig SMARTTUBE_BUNDLE_PREFIX)."
    exit 0
fi

if ! printf '%s' "$firebase_app_id" | /usr/bin/grep -Eq '^[0-9]+:[0-9]+:ios:[A-Za-z0-9_-]+$'; then
    echo "warning: GoogleService-Info.plist has an invalid GOOGLE_APP_ID; skipping Crashlytics dSYM upload."
    exit 0
fi

"${BUILD_DIR%Build/*}SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run" -gsp "$firebase_plist"
