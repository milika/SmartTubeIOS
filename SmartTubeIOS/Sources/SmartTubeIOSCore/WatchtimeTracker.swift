import Foundation
import os

private let trackerLog = Logger(subsystem: appSubsystem, category: "WatchtimeTracker")

// MARK: - WatchtimeTracker
//
// Owns all watch-history state for a single video session:
// position saving (VideoStateStore), playback-started ping, and
// watchtime segment reporting (InnerTubeAPI).
//
// Mirrors Android's TrackingService in MediaServiceCore.
//
// Lifecycle per video:
//   transition(to:cpn:flushPosition:flushDuration:)
//     → called from load() to flush the previous session and begin a new one.
//       Returns a @Sendable async closure; fire it in a detached Task.
//
//   checkpoint(position:duration:)
//     → called periodically while playing and from suspend(), stop().
//       The first call resolves the account-bound tracking URLs (an authenticated
//       TV /player request carrying this session's cpn — Android's
//       syncWithAuthInfoIfNeeded), records the segment start and fires
//       reportPlaybackStarted.
//
//   setTrackingURLs(nil)
//     → called on sign-in/out and token refresh so the next checkpoint resolves again.

@MainActor
public final class WatchtimeTracker {

    /// Android marks a video fully watched once less than 5% remains.
    private nonisolated static let endThresholdFraction = 0.05
    /// Android starts the watch record at 0 for anything below this position.
    private nonisolated static let startThreshold: TimeInterval = 180
    /// Android opens a fresh watch record when the previous one is older than this.
    private static let recordRenewInterval: TimeInterval = 30 * 60
    /// Minimum spacing between periodic checkpoints driven by the players' time observers.
    public static let checkpointInterval: TimeInterval = 30
    /// How long to wait after a failed tracking-URL resolution before trying again, so a
    /// failure doesn't re-fire the authenticated player requests on every checkpoint.
    static let trackingResolveRetryInterval: TimeInterval = 300

    // MARK: - Private state

    private let api: InnerTubeAPI

    private var videoId: String = ""
    private var cpn: String = ""
    private var trackingURLs: PlaybackTrackingURLs?
    /// Nil until the first checkpoint() — the lazy segment start.
    /// First checkpoint sets this and fires reportPlaybackStarted.
    private var segmentStart: TimeInterval?
    /// When the playback record for the current video was last opened.
    private var recordOpenedAt: Date?
    /// Set once the final=1 pings have been sent, so they fire only once per session.
    private var didReportFinal = false
    /// Throttle state for `checkpointIfDue`.
    private var lastCheckpointAt: Date?
    /// Single in-flight tracking-URL resolution; overlapping checkpoints await it.
    private var resolveTask: Task<Void, Never>?
    /// Last time resolution came back empty; gates retries (`trackingResolveRetryInterval`).
    private var lastResolveFailureAt: Date?
    /// Bumped by `transition` and `setTrackingURLs`. An in-flight resolution stores its
    /// result only if this is unchanged, so URLs minted for the previous account (or session)
    /// never land after an account reset.
    private var trackingGeneration = 0

    // MARK: - Init

    public init(api: InnerTubeAPI) {
        self.api = api
    }

    // MARK: - Transition (load → new video)

    /// Atomically captures the current session for async flushing and resets state
    /// for the new video. Call from `load()`:
    ///
    /// ```swift
    /// let flush = tracker.transition(to: video.id, cpn: ..., flushPosition: pos, flushDuration: dur)
    /// Task { await flush() }
    /// ```
    ///
    /// The returned closure owns its own copy of the old session state, so calling
    /// `begin()` / `setTrackingURLs()` for the new video immediately after is safe.
    @discardableResult
    public func transition(
        to newVideoId: String,
        cpn newCPN: String,
        flushPosition: TimeInterval,
        flushDuration: TimeInterval
    ) -> @Sendable () async -> Void {
        // Capture old session synchronously.
        let oldVideoId = videoId
        let oldCPN = cpn
        let oldURLs = trackingURLs
        let oldSegStart = segmentStart
        let oldDidReportFinal = didReportFinal
        let api = self.api

        // Reset to new session synchronously — no race with the returned closure.
        videoId = newVideoId
        cpn = newCPN
        trackingURLs = nil
        segmentStart = nil
        recordOpenedAt = nil
        didReportFinal = false
        lastCheckpointAt = nil
        resolveTask = nil
        lastResolveFailureAt = nil
        trackingGeneration += 1

        trackerLog.notice(
            "transition:\(oldVideoId, privacy: .public) → \(newVideoId, privacy: .public) cpn=\(newCPN.prefix(8), privacy: .public)…"
        )

        return {
            guard !oldVideoId.isEmpty, flushDuration > 0, !oldDidReportFinal else { return }
            let segStart = oldSegStart ?? Self.initialSegmentStart(for: flushPosition)
            let isFinal = Self.isNearEnd(position: flushPosition, duration: flushDuration)
            trackerLog.notice(
                "transition flush: videoId=\(oldVideoId, privacy: .public) st=\(Int(segStart))s et=\(Int(flushPosition))s final=\(isFinal, privacy: .public)"
            )
            await VideoStateStore.shared.save(videoId: oldVideoId, position: flushPosition, duration: flushDuration)
            // A session closed before its first checkpoint never resolved its URLs.
            var oldURLs = oldURLs
            if InnerTubeAPI.trackingSession(from: oldURLs) == nil {
                oldURLs = await api.fetchHistoryTrackingURLs(videoId: oldVideoId, cpn: oldCPN)
            }
            // The playback ping must precede the watchtime ping — YouTube ignores
            // standalone watchtime pings.
            await api.reportPlaybackStarted(
                videoId: oldVideoId, cpn: oldCPN, trackingURLs: oldURLs,
                lengthSeconds: flushDuration, startPosition: isFinal ? flushDuration : segStart, final: isFinal)
            await api.reportWatchtime(
                videoId: oldVideoId, cpn: oldCPN, trackingURLs: oldURLs,
                lengthSeconds: flushDuration,
                segmentStart: isFinal ? flushDuration : segStart,
                segmentEnd: isFinal ? flushDuration : flushPosition,
                final: isFinal)
        }
    }

    // MARK: - Tracking URLs

    /// Replaces the session's tracking URLs. Pass nil when the account changes (sign-in,
    /// sign-out, token refresh) so the next checkpoint resolves them again for that account.
    public func setTrackingURLs(_ urls: PlaybackTrackingURLs?) {
        trackingURLs = urls
        resolveTask = nil
        lastResolveFailureAt = nil
        trackingGeneration += 1
        let hasSession = InnerTubeAPI.trackingSession(from: urls) != nil
        trackerLog.notice(
            "setTrackingURLs: \(urls != nil ? "received" : "nil", privacy: .public) accountBound=\(hasSession, privacy: .public)"
        )
    }

    /// Indicates whether the tracker has the session parameters required by YouTube.
    public var hasTrackingSession: Bool {
        InnerTubeAPI.trackingSession(from: trackingURLs) != nil
    }

    /// Resolves the account-bound tracking URLs for the current session if they are missing.
    /// Overlapping callers share one request; a failure backs off for
    /// `trackingResolveRetryInterval`. A result that arrives after the session or the account
    /// changed (`trackingGeneration`) is dropped.
    private func ensureTrackingSession() async {
        guard !videoId.isEmpty, !hasTrackingSession else { return }
        if let resolveTask {
            await resolveTask.value
            return
        }
        if let failedAt = lastResolveFailureAt,
            Date().timeIntervalSince(failedAt) < Self.trackingResolveRetryInterval
        {
            return
        }
        let vid = videoId
        let sessionCPN = cpn
        let generation = trackingGeneration
        let api = self.api
        let task = Task { @MainActor in
            let urls = await api.fetchHistoryTrackingURLs(videoId: vid, cpn: sessionCPN)
            guard self.trackingGeneration == generation else { return }
            self.trackingURLs = urls
            self.lastResolveFailureAt = urls == nil ? Date() : nil
            trackerLog.notice(
                "resolved tracking URLs for \(vid, privacy: .public): accountBound=\(urls != nil, privacy: .public)")
        }
        resolveTask = task
        await task.value
        if resolveTask == task { resolveTask = nil }
    }

    // MARK: - Checkpoint (periodic / suspend / stop)

    /// Throttled entry point for the players' time observers: forwards to `checkpoint`
    /// at most once per `checkpointInterval`, so a tick can be wired up directly.
    /// The near-end final ping is not throttled while a tracking session exists. Without one
    /// (signed out, or resolution failed) a final checkpoint only saves local progress and
    /// leaves `didReportFinal` unset, so it is throttled like any other to avoid a save per tick.
    public func checkpointIfDue(position: TimeInterval, duration: TimeInterval) async {
        guard !didReportFinal else {
            return
        }
        guard duration > 0 else {
            return
        }
        let isFinal = Self.isNearEnd(position: position, duration: duration)
        guard isFinal || position > 0 else {
            return
        }
        let bypassesThrottle = isFinal && hasTrackingSession
        if !bypassesThrottle, let last = lastCheckpointAt, Date().timeIntervalSince(last) < Self.checkpointInterval {
            return
        }
        // Stamped before the await: ticks arrive several times a second, and stamping after
        // would let every tick during an in-flight checkpoint pass the throttle.
        lastCheckpointAt = Date()
        await checkpoint(position: position, duration: duration)
    }

    /// Records the current watch position and reports the watched interval.
    ///
    /// The first call is the lazy playback-start: it resolves the account-bound tracking
    /// URLs, fires `reportPlaybackStarted` and records the segment start. Subsequent calls save the position and
    /// report the interval [segmentStart, position]. Once less than 5% of the
    /// video remains, the final=1 pings mark it fully watched.
    public func checkpoint(position: TimeInterval, duration: TimeInterval) async {
        guard !videoId.isEmpty, duration > 0, !didReportFinal else {
            return
        }
        let vid = videoId
        let localCPN = cpn

        // The local resume position never waits for the network: the first checkpoint's
        // tracking resolution can be slow or fail offline, and the app may exit meanwhile.
        await VideoStateStore.shared.save(videoId: vid, position: position, duration: duration)

        await ensureTrackingSession()
        // The session may have changed during the awaits; reopening the same video starts a
        // new session with a new cpn, which this checkpoint must not report into or finish.
        guard videoId == vid, cpn == localCPN, !didReportFinal else {
            return
        }
        // Without account-bound URLs both pings would be skipped. Leave the reporting state
        // (segment start, open record, final flag) untouched so that once URLs resolve, the
        // next checkpoint opens the record with a playback ping before any watchtime ping,
        // and a final checkpoint can still report final=1.
        guard let localURLs = trackingURLs, InnerTubeAPI.trackingSession(from: localURLs) != nil else {
            trackerLog.notice(
                "checkpoint: videoId=\(vid, privacy: .public) no tracking session — saved local progress only")
            return
        }
        let isFinal = Self.isNearEnd(position: position, duration: duration)
        let needsNewRecord =
            segmentStart == nil
            || recordOpenedAt.map { Date().timeIntervalSince($0) > Self.recordRenewInterval } ?? true

        if segmentStart == nil {
            segmentStart = Self.initialSegmentStart(for: position)
        }
        let segStart = segmentStart ?? 0

        // A zero-length segment (st == et) is discarded by YouTube, which would leave
        // cmt unrecorded and the watch-progress bar stale.
        guard isFinal || segStart < position else {
            trackerLog.notice("checkpoint skipped: videoId=\(vid, privacy: .public) empty segment at \(Int(position))s")
            return
        }

        // Claim this segment before any await. Checkpoints can overlap (player ticks, pause()
        // followed by saveProgress() on close); updating state only after the network calls
        // let a second call read the same segmentStart and re-send the same interval, or send
        // the final ping twice. With the claim up front, an overlapping call sees an empty
        // segment (or didReportFinal) and skips.
        if isFinal {
            didReportFinal = true
        } else {
            segmentStart = position
        }
        if needsNewRecord || isFinal {
            recordOpenedAt = Date()
        }

        if needsNewRecord || isFinal {
            trackerLog.notice(
                "checkpoint: opening watch record videoId=\(vid, privacy: .public) cmt=\(Int(position))s final=\(isFinal, privacy: .public)"
            )
            await api.reportPlaybackStarted(
                videoId: vid, cpn: localCPN, trackingURLs: localURLs,
                lengthSeconds: duration, startPosition: isFinal ? duration : segStart, final: isFinal)
        }

        trackerLog.notice(
            "checkpoint: videoId=\(vid, privacy: .public) st=\(Int(segStart))s et=\(Int(position))s dur=\(Int(duration))s final=\(isFinal, privacy: .public)"
        )
        await api.reportWatchtime(
            videoId: vid, cpn: localCPN, trackingURLs: localURLs,
            lengthSeconds: duration,
            segmentStart: isFinal ? duration : segStart,
            segmentEnd: isFinal ? duration : position,
            final: isFinal)
    }

    /// Flushes the segment before a seek and starts the next segment at the target.
    /// This mirrors Android SmartTube's onSeekPositionChanged history update.
    public func recordSeek(
        to targetPosition: TimeInterval, from currentPosition: TimeInterval, duration: TimeInterval
    ) async {
        guard !videoId.isEmpty, duration > 0 else { return }
        if didReportFinal {
            // Rewatching after the final ping (Loop replays via seekTo(0), or a seek back out of
            // the last 5%): open a fresh record so the new progress is saved and reported again,
            // instead of leaving the stored position stuck at the end.
            guard !Self.isNearEnd(position: targetPosition, duration: duration) else { return }
            didReportFinal = false
            recordOpenedAt = nil
            segmentStart = max(0, min(duration, targetPosition))
            lastCheckpointAt = nil
            return
        }
        guard currentPosition > 0 else {
            segmentStart = max(0, min(duration, targetPosition))
            return
        }

        await checkpoint(position: currentPosition, duration: duration)
        segmentStart = max(0, min(duration, targetPosition))
        lastCheckpointAt = nil
    }

    // MARK: - Android parity helpers

    private nonisolated static func isNearEnd(position: TimeInterval, duration: TimeInterval) -> Bool {
        duration > 0 && duration - position < duration * endThresholdFraction
    }

    private nonisolated static func initialSegmentStart(for position: TimeInterval) -> TimeInterval {
        position < startThreshold ? 0 : position
    }
}
