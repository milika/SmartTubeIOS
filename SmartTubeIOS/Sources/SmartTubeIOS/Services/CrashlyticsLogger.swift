import FirebaseCrashlytics
import Foundation
import SmartTubeIOSCore
import os

/// Logs to `os.Logger` and forwards `.notice` and `.error` entries to Firebase
/// Crashlytics as breadcrumbs so they appear in crash reports.
/// `.debug` entries are only written to `os.log` — too verbose for crash reports.
public struct CrashlyticsLogger: Sendable {

    /// #92: set once from AppEntry.swift's init() (a different module, hence `public`),
    /// before any logging can happen, from `AppSettings.disableAnalytics` AND whether the
    /// bundled `GoogleService-Info.plist` is usable (`FirebaseConfiguration.isValid`).
    /// When `false`, the entry points skip `FirebaseApp.configure()` entirely (so the SDK
    /// makes no network calls at all, fixing the startup delay some users saw when
    /// analytics domains are DNS-blocked) — which means every method below must skip
    /// touching `Crashlytics.crashlytics()` too, since calling it without a configured
    /// FirebaseApp is a fatal error, not a silent no-op.
    public nonisolated(unsafe) static var isEnabled = true

    /// Short identifier (8 hex chars) generated once per app session, independent of
    /// `isEnabled` — it's shown in the Stats for Nerds debug overlay purely as a local
    /// reference number even when analytics reporting is off.
    static let sessionReportID: String = {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return String(raw.prefix(8)).uppercased()
    }()
    private let logger: Logger
    private let category: String

    init(subsystem: String = appSubsystem, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func notice(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.notice("\(msg, privacy: .public)")
        guard Self.isEnabled else { return }
        Crashlytics.crashlytics().log("[\(category)] \(msg)")
    }

    func error(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.error("\(msg, privacy: .public)")
        guard Self.isEnabled else { return }
        Crashlytics.crashlytics().log("[ERR][\(category)] \(msg)")
    }

    func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.debug("\(msg, privacy: .public)")
        // Not forwarded — too verbose for crash reports
    }

    /// Records a non-fatal error in Crashlytics with additional key-value context.
    /// Use this for surfaced errors the user sees (e.g. player errors) so they
    /// appear as non-fatal issues in the Firebase console.
    func recordNonFatal(_ error: Error, userInfo: [String: String] = [:]) {
        let nsError = error as NSError
        let msg = "[\(category)] \(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
        logger.error("\(msg, privacy: .public)")
        guard Self.isEnabled else { return }
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.log(msg)
        for (key, value) in userInfo {
            crashlytics.setCustomValue(value, forKey: key)
        }
        crashlytics.record(error: error)
    }

    /// Stamps the video currently being loaded onto Crashlytics' persistent custom keys.
    /// Called once per `load(video:)` so that both crashes and non-fatals show which
    /// video was active at the time of the failure.
    static func setVideoContext(id: String, title: String) {
        guard isEnabled else { return }
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(id, forKey: "active_video_id")
        crashlytics.setCustomValue(title.prefix(120).description, forKey: "active_video_title")
    }

    /// Stamps the video the user *intended* to play onto Crashlytics' persistent custom keys.
    /// Called from `PlayerStateStore.play(video:)` — the earliest user-intent signal —
    /// so it is set BEFORE `load(video:)` runs and before the breadcrumb buffer can fill.
    /// Comparing `intended_video_id` with `active_video_id` in a report reveals whether
    /// the wrong video was loaded (prefetch race / wrong-card tap / id mismatch).
    static func setIntendedVideo(id: String, title: String) {
        guard isEnabled else { return }
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(id, forKey: "intended_video_id")
        crashlytics.setCustomValue(title.prefix(120).description, forKey: "intended_video_title")
        crashlytics.setCustomValue(ISO8601DateFormatter().string(from: Date()), forKey: "intended_video_tap_time")
    }

    /// Records a user-triggered diagnostic non-fatal event in Crashlytics.
    /// All breadcrumbs accumulated during the session are attached to this event,
    /// giving a detailed picture of the app flow leading up to the user's report.
    /// The `report_id` custom key matches the ID shown in the Stats for Nerds
    /// debug overlay (two-finger tap in the player) so reports can be correlated
    /// with user-provided IDs from support conversations.
    static func sendDiagnosticReport() {
        guard isEnabled else { return }
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(sessionReportID, forKey: "report_id")
        crashlytics.log(
            "[Diagnostic] User-requested diagnostic report — report_id=\(sessionReportID). Tip: two-finger tap the player to open the debug overlay and confirm this ID before sending."
        )
        let error = NSError(
            domain: "SmartTube.UserDiagnostic",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "User-requested diagnostic report (ID: \(sessionReportID))"]
        )
        crashlytics.record(error: error)
    }

    /// Records a non-fatal Crashlytics event when time-to-first-frame exceeds 4 seconds.
    /// Surfaces in the Firebase console under domain `SmartTube.SlowLoad` (code 4001),
    /// tagged with the stream type and elapsed ms so we can correlate slow-load rate
    /// with fallback path and network conditions.
    static func recordSlowVideoLoad(
        videoId: String,
        elapsedMs: Int,
        streamType: String,
        hasError: Bool,
        errorDescription: String? = nil
    ) {
        guard isEnabled else { return }
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(videoId, forKey: "slow_load_video_id")
        crashlytics.setCustomValue(elapsedMs, forKey: "slow_load_ttff_ms")
        crashlytics.setCustomValue(streamType, forKey: "slow_load_stream_type")
        crashlytics.setCustomValue(hasError, forKey: "slow_load_has_error")
        if let desc = errorDescription {
            crashlytics.setCustomValue(desc, forKey: "slow_load_error_desc")
        }
        crashlytics.log("[SlowLoad] videoId=\(videoId) ttff=\(elapsedMs)ms stream=\(streamType) hasError=\(hasError)")
        crashlytics.record(
            error: NSError(
                domain: "SmartTube.SlowLoad",
                code: 4001,
                userInfo: [NSLocalizedDescriptionKey: "Slow video load: \(elapsedMs)ms (\(streamType))"]
            ))
    }

    /// Automatically records a diagnostic report when playback fails and the error is
    /// shown to the user. Uses domain `SmartTube.AutoDiagnostic` (code 1) so it appears
    /// as a distinct Firebase issue from user-triggered reports, making it easy to query
    /// "all sessions where a user couldn't play a video" without manual intervention.
    /// Custom keys set by `recordNonFatal` (stream_url, has_retried, etc.) are already
    /// stamped on the Crashlytics instance and are automatically attached to this event.
    static func sendAutoPlaybackDiagnostic() {
        guard isEnabled else { return }
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.log("[AutoDiagnostic] Playback failure — see custom keys and session breadcrumbs.")
        crashlytics.setCustomValue("auto", forKey: "trigger")
        crashlytics.record(
            error: NSError(
                domain: "SmartTube.AutoDiagnostic",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Playback failure — see session breadcrumbs"]
            ))
    }

    /// Records a non-fatal Crashlytics event when the video that reached readyToPlay
    /// (`activeId`) does not match the video the user intended to play (`intendedId`).
    /// Surfaces in Firebase under domain `SmartTube.WrongVideo` (code 2) so
    /// wrong-video regressions can be queried independently of user-triggered reports.
    /// Custom keys `wv_intended_id` / `wv_active_id` make it easy to see both IDs
    /// in the Firebase console without opening the full breadcrumb log.
    static func sendWrongVideoReport(
        intendedId: String,
        intendedTitle: String,
        activeId: String,
        activeTitle: String
    ) {
        guard isEnabled else { return }
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(intendedId, forKey: "wv_intended_id")
        crashlytics.setCustomValue(intendedTitle, forKey: "wv_intended_title")
        crashlytics.setCustomValue(activeId, forKey: "wv_active_id")
        crashlytics.setCustomValue(activeTitle, forKey: "wv_active_title")
        let msg =
            "[WrongVideo] intended=\(intendedId) (\(intendedTitle.prefix(60))) active=\(activeId) (\(activeTitle.prefix(60)))"
        crashlytics.log(msg)
        Logger(subsystem: appSubsystem, category: "WrongVideo").error("\(msg, privacy: .public)")
        crashlytics.record(
            error: NSError(
                domain: "SmartTube.WrongVideo",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Wrong video at readyToPlay: intended=\(intendedId) active=\(activeId)"
                ]
            ))
    }
}
