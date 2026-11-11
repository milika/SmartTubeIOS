#if !os(tvOS)
import Foundation
import CoreFoundation
import os
import SmartTubeIOSCore

private let shortsLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsPlayer")

// MARK: - SponsorBlock
//
// Cache-first segment loading + tick-driven skip/toast logic for the Shorts embed
// player. Direct port of TOSPlayerViewModel+SponsorBlock.swift (see
// docs/tos-sponsorskip.md), reusing the same `PendingSkipLog` struct (declared in
// that file — internal, so visible here within the SmartTubeIOS module) and the
// same `SponsorBlockDecisionEngine.decide(...)` pure function.

/// The settings that decide which SponsorBlock segments a Short gets.
struct SponsorBlockConfig: Equatable {
    let isEnabled: Bool
    let categories: Set<SponsorSegment.Category>
    let minSegmentDuration: Double
    let excludedChannelIds: Set<String>

    init(_ settings: AppSettings) {
        isEnabled = settings.sponsorBlockEnabled && settings.shortsSponsorBlock
        categories = settings.activeSponsorCategories
        minSegmentDuration = settings.sponsorBlockMinSegmentDuration
        excludedChannelIds = Set(settings.sponsorBlockExcludedChannels.keys)
    }
}

extension ShortsEmbedPlayerViewModel {

    /// Drops the current Short's segments and, if it is already playing, loads them
    /// again under the current settings and channel. Before "ready" there is nothing
    /// to do — the "ready" message starts the load.
    func reloadSponsorSegments() {
        sponsorTask?.cancel()
        sponsorTask = nil
        sponsorSegments = []
        currentToastSegment = nil
        activeSkipEnd = nil
        pendingSkipLog = nil
        guard isReady else { return }
        sponsorTask = Task { await self.fetchSponsorSegments() }
    }

    /// Cache-first load — see TOSPlayerViewModel+SponsorBlock.swift's
    /// `fetchSponsorSegments()` for the full cache-hit/stale/miss rationale. Called
    /// from the "ready" case in ShortsEmbedPlayerViewModel+WebBridge.swift (Step 5
    /// below) for every loaded Short.
    func fetchSponsorSegments() async {
        guard settings.sponsorBlockEnabled, settings.shortsSponsorBlock,
            !settings.activeSponsorCategories.isEmpty
        else { return }

        // UI-testing deterministic injection — same seam as
        // TOSPlayerViewModel+SponsorBlock.swift's `--uitesting-inject-sponsor-segments=`.
        // Format: "<start>-<end>:<category>[,<start>-<end>:<category>...]"
        //   e.g. "--uitesting-inject-sponsor-segments=2-6:sponsor"
        if let injectArg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--uitesting-inject-sponsor-segments=")
        }) {
            let raw = String(injectArg.dropFirst("--uitesting-inject-sponsor-segments=".count))
            let injected: [SponsorSegment] = raw.split(separator: ",").compactMap { spec in
                let parts = spec.split(separator: ":")
                guard parts.count == 2 else { return nil }
                let range = parts[0].split(separator: "-")
                guard range.count == 2,
                    let start = Double(range[0]),
                    let end = Double(range[1]),
                    let category = SponsorSegment.Category(rawValue: String(parts[1]))
                else { return nil }
                return SponsorSegment(start: start, end: end, category: category)
            }
            guard !injected.isEmpty else { return }
            sponsorSegments = injected
            let summary =
                injected
                .map { seg -> String in
                    let start = String(format: "%.1f", seg.start)
                    let end = String(format: "%.1f", seg.end)
                    return "\(seg.category.rawValue)[\(start)–\(end)s]"
                }
                .joined(separator: ", ")
            shortsLog.notice(
                "[SponsorBlock] UI-TEST INJECT — bypassing cache/network, applied \(injected.count) synthetic segment(s): \(summary)"
            )
            return
        }

        let channelIsExcluded =
            channelId.map {
                settings.sponsorBlockExcludedChannels.keys.contains($0)
            } ?? false
        guard !channelIsExcluded else {
            shortsLog.notice("[SponsorBlock] channel excluded — skipping for \(self.videoId)")
            return
        }

        let videoId = videoId
        let categories = settings.activeSponsorCategories
        let minDuration = settings.sponsorBlockMinSegmentDuration
        func filtered(_ segments: [SponsorSegment]) -> [SponsorSegment] {
            minDuration > 0 ? segments.filter { ($0.end - $0.start) >= minDuration } : segments
        }

        // Every `await` below re-checks cancellation: `loadShort(video:)` and
        // `reloadSponsorSegments()` cancel this task, and its late result must not
        // overwrite the next Short's (or the new settings') segments.
        let cached = await VideoPreloadCache.shared.consume(videoId: videoId)
        guard !Task.isCancelled else { return }
        if let cachedSegments = cached.sponsorSegments {
            let isStale = cached.staleFields.contains(.sponsorSegments)
            sponsorSegments = filtered(cachedSegments)
            shortsLog.notice(
                "[SponsorBlock] cache \(isStale ? "STALE" : "HIT") — applied \(self.sponsorSegments.count) segment(s) for \(videoId)"
            )
            guard isStale else { return }
            // Revalidate silently — re-apply when it lands.
            let fresh = await sponsorService.fetchSegments(videoId: videoId, categories: categories)
            await VideoPreloadCache.shared.store(sponsorSegments: fresh, for: videoId)
            guard !Task.isCancelled else { return }
            sponsorSegments = filtered(fresh)
            shortsLog.notice("[SponsorBlock] revalidated — \(self.sponsorSegments.count) segment(s) for \(videoId)")
            return
        }

        // Full miss — fetch live, store for reuse, then apply.
        let segments = await sponsorService.fetchSegments(videoId: videoId, categories: categories)
        await VideoPreloadCache.shared.store(sponsorSegments: segments, for: videoId)
        guard !Task.isCancelled else { return }
        sponsorSegments = filtered(segments)
        shortsLog.notice(
            "[SponsorBlock] cache MISS — fetched & applied \(self.sponsorSegments.count) of \(segments.count) loaded segment(s) for \(videoId)"
        )
    }

    /// Evaluates the current playback time against loaded segments and either
    /// auto-skips, shows a toast, or clears any active toast — driven by every
    /// "tick" message (see Step 6's edit to the "tick" case below).
    func checkSponsorSkip(at time: Double) {
        if let end = activeSkipEnd, time >= end { activeSkipEnd = nil }

        let decision = SponsorBlockDecisionEngine.decide(
            at: time,
            segments: sponsorSegments,
            settings: settings,
            isSkipInProgress: activeSkipEnd != nil,
            duration: duration
        )

        switch decision {
        case .clearToast:
            currentToastSegment = nil

        case .skip(let target, let seg):
            activeSkipEnd = seg.end
            currentToastSegment = nil

            // Full payload up front, "before" time included — this is the line to grep
            // for to correlate a skip with the segment that caused it. The "AFTER"/landing
            // line (logged from logSkipLanding once the seek is confirmed) carries the
            // matching beforeTime so the pair can be joined without timestamps.
            shortsLog.notice(
                "[SponsorBlock] skip TRIGGER category=\(seg.category.rawValue) action=skip segment=[\(seg.start, format: .fixed(precision: 1))s–\(seg.end, format: .fixed(precision: 1))s] (duration=\(seg.end - seg.start, format: .fixed(precision: 1))s) before=\(time, format: .fixed(precision: 2))s target=\(target, format: .fixed(precision: 2))s"
            )
            pendingSkipLog = PendingSkipLog(
                category: seg.category,
                segmentStart: seg.start,
                segmentEnd: seg.end,
                beforeTime: time,
                targetTime: target
            )
            seekTo(target)
            // Cross-process signal for XCTest — lets a UI test wait(for:) the skip
            // deterministically instead of guessing a sleep duration.
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.shortsplayer.sponsorskip" as CFString),
                nil, nil, true
            )

        case .skipToPlaybackEnd(let seg):
            // Shorts route end-of-video through ShortsEndOfVideoDecision (Task 3),
            // triggered by the "stateChange" → .ended case wired up in
            // ShortsPlayerView (Task 9) — not by seeking past the end here. Let
            // playback continue through this last ~2s to its natural "ended".
            currentToastSegment = nil
            if lastLoggedNearEndSegment?.start != seg.start || lastLoggedNearEndSegment?.category != seg.category {
                lastLoggedNearEndSegment = seg
                shortsLog.notice(
                    "[SponsorBlock] near-end segment — letting playback continue to natural end category=\(seg.category.rawValue) segment=[\(seg.start, format: .fixed(precision: 1))s–\(seg.end, format: .fixed(precision: 1))s]"
                )
            }

        case .showToast(let seg):
            // Log only on the transition into a new segment — checkSponsorSkip runs on
            // every ~250ms tick while inside the segment, and logging here unconditionally
            // would spam ~4 identical lines/second for the toast's entire visible window.
            if lastLoggedToastSegment?.start != seg.start || lastLoggedToastSegment?.category != seg.category {
                lastLoggedToastSegment = seg
                shortsLog.notice(
                    "[SponsorBlock] toast SHOW category=\(seg.category.rawValue) action=showToast segment=[\(seg.start, format: .fixed(precision: 1))s–\(seg.end, format: .fixed(precision: 1))s] at t=\(time, format: .fixed(precision: 2))s"
                )
            }
            currentToastSegment = seg

        case .none:
            break
        }
    }

    /// Watches for the landing of an in-flight auto-skip seek and logs the "after" side
    /// of the before/after pair once confirmed (or a timeout if it never lands). See
    /// `PendingSkipLog` (TOSPlayerViewModel+SponsorBlock.swift) for why this async
    /// confirmation is necessary — called from every "tick" (Step 6 below).
    func logSkipLanding(at time: Double) {
        guard var pending = pendingSkipLog else { return }

        if time >= pending.targetTime - 0.5 {
            let skippedSeconds = time - pending.beforeTime
            shortsLog.notice(
                "[SponsorBlock] skip LANDED category=\(pending.category.rawValue) before=\(pending.beforeTime, format: .fixed(precision: 2))s after=\(time, format: .fixed(precision: 2))s skipped≈\(skippedSeconds, format: .fixed(precision: 2))s (target was \(pending.targetTime, format: .fixed(precision: 2))s, Δtarget=\(time - pending.targetTime, format: .fixed(precision: 2))s) ticksWaited=\(pending.ticksWaited)"
            )
            pendingSkipLog = nil
            return
        }

        pending.ticksWaited += 1
        if pending.ticksWaited > 16 {
            shortsLog.notice(
                "[SponsorBlock] skip TIMEOUT category=\(pending.category.rawValue) before=\(pending.beforeTime, format: .fixed(precision: 2))s target=\(pending.targetTime, format: .fixed(precision: 2))s — still at \(time, format: .fixed(precision: 2))s after \(pending.ticksWaited) ticks; seek may not have taken effect"
            )
            pendingSkipLog = nil
        } else {
            pendingSkipLog = pending
        }
    }
}
#endif  // !os(tvOS)
