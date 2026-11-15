import Foundation

// MARK: - AppLanguage

/// A language the interface can be displayed in — one case per
/// `Localizable.xcstrings` localization, plus ``system`` for "follow the device".
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    /// Follow the device's preferred languages, falling back to English when none of
    /// the supported languages is among them.
    case system = "system"
    case arabic = "ar"
    case german = "de"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case hindi = "hi"
    case croatian = "hr"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case portugueseBrazil = "pt-BR"
    case russian = "ru"
    case serbian = "sr"
    case turkish = "tr"
    case chineseSimplified = "zh-Hans"

    /// Every language that can be picked explicitly (``system`` excluded), in the order
    /// shown by the Settings picker.
    public static let selectable: [AppLanguage] = allCases.filter { $0 != .system }

    /// BCP-47 code of the matching catalog localization; `nil` for ``system``.
    public var catalogCode: String? { self == .system ? nil : rawValue }

    /// The language's name in its own language, shown untranslated in the picker the way
    /// iOS lists languages. ``system`` uses the localized "System Default" label instead.
    public var displayName: String {
        switch self {
        case .system: return L10n.string("System Default")
        case .arabic: return "العربية"
        case .german: return "Deutsch"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .hindi: return "हिन्दी"
        case .croatian: return "Hrvatski"
        case .indonesian: return "Bahasa Indonesia"
        case .italian: return "Italiano"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .portugueseBrazil: return "Português (Brasil)"
        case .russian: return "Русский"
        case .serbian: return "Српски"
        case .turkish: return "Türkçe"
        case .chineseSimplified: return "简体中文"
        }
    }

    /// The supported language that best matches the first entry of `systemLanguages`
    /// (i.e. `Locale.preferredLanguages`), or ``english`` when nothing matches.
    public static func resolved(systemLanguages: [String]) -> AppLanguage {
        for tag in systemLanguages {
            if let match = selectable.first(where: { $0.matches(tag) }) { return match }
        }
        return .english
    }

    /// Whether this language's catalog localization is a sensible match for the BCP-47
    /// `tag`: same language, and no conflict where both sides name a script or region —
    /// so "de-AT" matches "de" while "zh-Hant" does not match "zh-Hans".
    private func matches(_ tag: String) -> Bool {
        guard let code = catalogCode else { return false }
        let wanted = Locale.Language(identifier: tag)
        let candidate = Locale.Language(identifier: code)
        guard wanted.languageCode == candidate.languageCode else { return false }
        if let script = wanted.script, let candidateScript = candidate.script, script != candidateScript {
            return false
        }
        if let region = wanted.region, let candidateRegion = candidate.region, region != candidateRegion {
            return false
        }
        return true
    }
}

// MARK: - L10n

/// Localized string resolution for every SmartTube target.
///
/// The shared string catalog lives in this module's resource bundle
/// (`Localizable.xcstrings`) rather than in the UI module so the app, its
/// extensions and the widget can all resolve the same keys. SwiftUI string
/// initializers default to `Bundle.main`, which contains no catalog, so every
/// user-visible string must be resolved through ``bundle``/``string(_:)``
/// explicitly.
public enum L10n {
    /// Interface language chosen in Settings › Interface (default: follow the device).
    ///
    /// Written on the main actor by `SettingsStore` — at launch and whenever the setting
    /// changes — and read from any thread by ``string(_:)``, hence `nonisolated(unsafe)`.
    /// Updates replace the whole resolution at once; a reader therefore sees either the
    /// old or the new language, never a mixture.
    public nonisolated(unsafe) static var language: AppLanguage = .system {
        didSet { active = Resolution(preference: language) }
    }

    /// Resource bundle holding the localization for ``language``.
    public static var bundle: Bundle { active.bundle }

    /// Locale matching ``language``, for SwiftUI's own formatting.
    public static var locale: Locale { active.locale }

    /// Resolves `key` against the shared string catalog in ``language``.
    public static func string(_ key: String.LocalizationValue) -> String {
        let resolution = active
        return String(localized: key, bundle: resolution.bundle, locale: resolution.locale)
    }

    // MARK: - Resolution

    /// Effective language (never ``AppLanguage/system``) and the bundle that renders it.
    private struct Resolution {
        let language: AppLanguage
        /// Device locale while following the system — the user's regional and calendar
        /// preferences stay in charge. A picked language brings its own locale instead.
        let locale: Locale
        let bundle: Bundle

        init(preference: AppLanguage) {
            let followsDevice = preference == .system
            language =
                followsDevice
                ? AppLanguage.resolved(systemLanguages: Locale.preferredLanguages)
                : preference
            locale = followsDevice ? .current : Locale(identifier: language.rawValue)
            bundle = Self.bundle(for: language)
        }

        /// The catalog's `<code>.lproj` sub-bundle, so strings come from `language`
        /// regardless of the device language. Falls back to the shared bundle when the
        /// localization is missing from the built resources.
        private static func bundle(for language: AppLanguage) -> Bundle {
            guard let code = language.catalogCode,
                let path = Bundle.module.path(forResource: code, ofType: "lproj"),
                let localized = Bundle(path: path)
            else { return .module }
            return localized
        }
    }

    /// Current resolution. Static state is initialized lazily before first use.
    private nonisolated(unsafe) static var active = Resolution(preference: .system)
}
