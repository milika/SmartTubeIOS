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
            if self.settings.hideShorts != oldValue.hideShorts {
                settingsLog.notice(
                    "hideShorts \(oldValue.hideShorts ? "ON" : "OFF", privacy: .public) → \(self.settings.hideShorts ? "ON" : "OFF", privacy: .public)"
                )
            }
            self.save()
        }
    }

    /// Process-local override for player-specific UI tests.
    private var useTOSPlayerOnIOSOverride: Bool?

    public var useTOSPlayerOnIOS: Bool {
        get { useTOSPlayerOnIOSOverride ?? (settings.iosPlayerMode == .youtube) }
        set { useTOSPlayerOnIOSOverride = newValue }
    }

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
        // The YouTube player is the default on iOS, so suites that exercise the
        // AVPlayer-based pipeline (quality picker, captions, SponsorBlock, mini player,
        // PIP, DASH switching, etc.) opt back into it with this flag.
        if ProcessInfo.processInfo.arguments.contains("--uitesting-disable-tos-player-on-ios") {
            self.useTOSPlayerOnIOS = false
        }
    }

    init(settings: AppSettings) {
        self.settings = settings
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
