import Foundation

/// The App Group shared by the app, the download widget and the share extension.
///
/// The identifier is injected by the build (`SMARTTUBE_APP_GROUP_ID` in
/// `SmartTubeApp/Config/Base.xcconfig`, copied into each product's Info.plist), so this
/// is the only place in Swift that knows how to read it. Never hardcode a group
/// identifier in a view, view model or extension.
public enum AppGroup {

    /// `SmartTubeAppGroupIdentifier` from the host bundle's Info.plist.
    ///
    /// `nil` when the key is missing — SwiftPM test bundles and tools do not carry it.
    /// Callers must degrade (skip the shared write, log) instead of falling back to a
    /// hardcoded group: a container the build has no entitlement for would silently
    /// swallow every write.
    public static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SmartTubeAppGroupIdentifier") as? String,
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    /// `UserDefaults` for the shared container, or `nil` when the group is unavailable.
    public static var userDefaults: UserDefaults? {
        identifier.flatMap { UserDefaults(suiteName: $0) }
    }
}
