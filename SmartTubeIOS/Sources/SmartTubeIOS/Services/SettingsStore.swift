import Foundation
import OSLog
import Observation
import SmartTubeIOSCore

private let settingsLog = Logger(subsystem: appSubsystem, category: "Settings")

// MARK: - SettingsStore
//
// Persists `AppSettings` in `UserDefaults` and notifies observers via
// `@Observable`.  Used as an `@Environment` value throughout the app.

@MainActor
@Observable
public final class SettingsStore {

    public var settings: AppSettings {
        didSet {
            if self.settings.language != oldValue.language {
                L10n.language = self.settings.language
            }
            if self.settings.hideShorts != oldValue.hideShorts {
                settingsLog.notice(
                    "hideShorts \(oldValue.hideShorts ? "ON" : "OFF", privacy: .public) → \(self.settings.hideShorts ? "ON" : "OFF", privacy: .public)"
                )
            }
            self.save()
        }
    }

    /// Whether the YouTube IFrame-based TOS-compliant player is used instead of the
    /// AVPlayer-based pipeline on iOS. Always `true` — there is no user-facing
    /// setting for this and it is never persisted. Existing iOS UI tests that
    /// exercise the AVPlayer-based pipeline (quality picker, captions, SponsorBlock,
    /// mini player, PIP, DASH switching, etc.) opt out via
    /// `--uitesting-disable-tos-player-on-ios`. Has no effect on macOS or tvOS —
    /// PlayerRouter (the only reader) is `#if os(iOS)`.
    public var useTOSPlayerOnIOS: Bool = true

    private static let key = "smarttube_app_settings"

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
        // Reset settings to defaults when launched for UI testing so each test
        // suite starts from a clean, known state and prior runs cannot bleed in.
        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset-settings") {
            self.settings = AppSettings()
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-disable-sponsorblock") {
            self.settings.sponsorBlockEnabled = false
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-audio-only-mode") {
            self.settings.audioOnlyMode = true
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-hide-shorts") {
            self.settings.hideShorts = true
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-enable-tos-player-on-ios") {
            self.useTOSPlayerOnIOS = true
        }
        // useTOSPlayerOnIOS is true by default on iOS, so suites that exercise the
        // AVPlayer-based pipeline (quality picker, captions, SponsorBlock, mini player,
        // PIP, DASH switching, etc.) opt back into it with this flag.
        if ProcessInfo.processInfo.arguments.contains("--uitesting-disable-tos-player-on-ios") {
            self.useTOSPlayerOnIOS = false
        }
        // Apply the stored interface language before the first view renders.
        L10n.language = settings.language
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        iCloudSyncManager.shared.syncEnabled = settings.iCloudSyncEnabled
    }

    public func reset() {
        settings = AppSettings()
    }
}
