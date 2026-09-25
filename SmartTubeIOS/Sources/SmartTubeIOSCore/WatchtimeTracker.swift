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
//   setTrackingURLs(_:)
//     → called once authenticated tracking URLs resolve in loadAsync.
//
//   checkpoint(position:duration:)
//     → called periodically while playing and from suspend(), stop().
//       The segment start is recorded lazily on the first call,
//       which also fires reportPlaybackStarted.

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

        trackerLog.notice(
            "transition: \(oldVideoId, privacy: .public) → \(newVideoId, privacy: .public) cpn=\(newCPN.prefix(8), privacy: .public)…"
        )

        return {
            guard !oldVideoId.isEmpty, flushDuration > 0, !oldDidReportFinal else { return }
            let segStart = oldSegStart ?? Self.initialSegmentStart(for: flushPosition)
            let isFinal = Self.isNearEnd(position: flushPosition, duration: flushDuration)
            trackerLog.notice(
                "transition flush: videoId=\(oldVideoId, privacy: .public) st=\(Int(segStart))s et=\(Int(flushPosition))s final=\(isFinal, privacy: .public)"
            )
            await VideoStateStore.shared.save(videoId: oldVideoId, position: flushPosition, duration: flushDuration)
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

    /// Store authenticated tracking URLs once they resolve in `loadAsync`.
    /// Safe to call any time between `transition` and the first `checkpoint`.
    public func setTrackingURLs(_ urls: PlaybackTrackingURLs?) {
        trackingURLs = urls
        let hasSession = InnerTubeAPI.trackingSession(from: urls) != nil
        trackerLog.notice(
            "setTrackingURLs: \(urls != nil ? "received" : "nil", privacy: .public) accountBound=\(hasSession, privacy: .public)"
        )
    }

    /// Indicates whether the tracker has the session parameters required by YouTube.
    public var hasTrackingSession: Bool {
        InnerTubeAPI.trackingSession(from: trackingURLs) != nil
    }

    // MARK: - Checkpoint (periodic / suspend / stop)

    /// Throttled entry point for the players' time observers: forwards to `checkpoint`
    /// at most once per `checkpointInterval`, so a tick can be wired up directly.
    /// The near-end final ping is never throttled.
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
        if !isFinal, let last = lastCheckpointAt, Date().timeIntervalSince(last) < Self.checkpointInterval {
            return
        }
        await checkpoint(position: position, duration: duration)
        lastCheckpointAt = Date()
    }

    /// Records the current watch position and reports the watched interval.
    ///
    /// The first call is the lazy playback-start: it fires `reportPlaybackStarted`
    /// and records the segment start. Subsequent calls save the position and
    /// report the interval [segmentStart, position]. Once less than 5% of the
    /// video remains, the final=1 pings mark it fully watched.
    public func checkpoint(position: TimeInterval, duration: TimeInterval) async {
        guard !videoId.isEmpty else {
            return
        }
        guard duration > 0 else {
            return
        }
        guard !didReportFinal else {
            return
        }

        let vid = videoId
        let localCPN = cpn
        let localURLs = trackingURLs
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

        await VideoStateStore.shared.save(videoId: vid, position: position, duration: duration)

        if needsNewRecord || isFinal {
            trackerLog.notice(
                "checkpoint: opening watch record videoId=\(vid, privacy: .public) cmt=\(Int(position))s final=\(isFinal, privacy: .public)"
            )
            await api.reportPlaybackStarted(
                videoId: vid, cpn: localCPN, trackingURLs: localURLs,
                lengthSeconds: duration, startPosition: isFinal ? duration : segStart, final: isFinal)
            recordOpenedAt = Date()
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

        if isFinal {
            didReportFinal = true
        } else {
            segmentStart = position
        }
    }

    // MARK: - Android parity helpers

    private nonisolated static func isNearEnd(position: TimeInterval, duration: TimeInterval) -> Bool {
        duration > 0 && duration - position < duration * endThresholdFraction
    }

    private nonisolated static func initialSegmentStart(for position: TimeInterval) -> TimeInterval {
        position < startThreshold ? 0 : position
    }
}
