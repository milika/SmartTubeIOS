import Foundation

/// Localized string resolution for every SmartTube target.
///
/// The shared string catalog lives in this module's resource bundle
/// (`Localizable.xcstrings`) rather than in the UI module so the app, its
/// extensions and the widget can all resolve the same keys. SwiftUI string
/// initializers default to `Bundle.main`, which contains no catalog, so every
/// user-visible string must be resolved through ``bundle``/``string(_:)``
/// explicitly.
public enum L10n {
    /// Resource bundle that contains the shared string catalog.
    public static let bundle: Bundle = .module

    /// Resolves `key` against the shared string catalog.
    public static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle)
    }
}
