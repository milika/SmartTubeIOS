import Foundation
import Observation
import OSLog
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
                settingsLog.notice("hideShorts \(oldValue.hideShorts ? "ON" : "OFF", privacy: .public) → \(self.settings.hideShorts ? "ON" : "OFF", privacy: .public)")
            }
            self.save()
        }
    }

    /// Non-persisted UI-test override. Production routing uses the user's persisted
    /// player selection; existing test suites can still force either pipeline.
    private var iOSPlayerOverride: AppSettings.IOSPlayer?

    public var effectiveIOSPlayer: AppSettings.IOSPlayer {
        iOSPlayerOverride ?? settings.iOSPlayer
    }

    private static let key = "smarttube_app_settings"

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
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
            self.iOSPlayerOverride = .youtubeEmbed
        }
        // Suites that exercise the AVPlayer pipeline can opt into it independently
        // of the player selection persisted by a previous simulator run.
        if ProcessInfo.processInfo.arguments.contains("--uitesting-disable-tos-player-on-ios") {
            self.iOSPlayerOverride = .native
        }
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
