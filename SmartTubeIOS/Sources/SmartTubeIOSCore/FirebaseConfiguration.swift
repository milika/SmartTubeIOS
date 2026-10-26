import Foundation

/// Validates the bundled `GoogleService-Info.plist` before anything touches Firebase.
///
/// `FirebaseApp.configure()` raises when the plist is missing or belongs to another
/// bundle, and `Crashlytics.crashlytics()` raises when no app has been configured. Both
/// entry points (`AppEntry` for iOS/macOS, `SmartTubeTVApp` for tvOS) therefore gate
/// `FirebaseApp.configure()` and `CrashlyticsLogger.isEnabled` on this check.
///
/// `scripts/run-crashlytics.sh` mirrors the same predicate for the dSYM upload phase;
/// keep the two in sync.
public enum FirebaseConfiguration {

    /// `true` when the bundle ships a plist whose `BUNDLE_ID` matches this bundle and
    /// whose `GOOGLE_APP_ID` looks like a real Firebase iOS app ID.
    ///
    /// A placeholder plist (`com.your.bundle.id`) fails both parts, which is exactly the
    /// fork/CI case where Firebase must be skipped instead of crashing at launch.
    public static func isValid(in bundle: Bundle = .main) -> Bool {
        guard
            let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
            let values = NSDictionary(contentsOfFile: path) as? [String: Any],
            let appID = values["GOOGLE_APP_ID"] as? String,
            let plistBundleID = values["BUNDLE_ID"] as? String,
            let bundleID = bundle.bundleIdentifier
        else {
            return false
        }
        return plistBundleID == bundleID
            && appID.range(of: appIDPattern, options: .regularExpression) != nil
    }

    /// Firebase iOS app IDs look like `1:1234567890:ios:abcdef1234567890`.
    static let appIDPattern = #"^\d+:\d+:ios:[A-Za-z0-9_-]+$"#
}
