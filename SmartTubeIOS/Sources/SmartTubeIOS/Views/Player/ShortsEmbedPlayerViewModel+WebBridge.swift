#if !os(tvOS)
import Foundation
import CoreFoundation
import WebKit
import os
import SmartTubeIOSCore

private let shortsLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsPlayer")

// MARK: - JS Message Handling
//
// Receives every message posted by `stateDetectionJS` (ShortsEmbedJS.swift) via
// window.__nativeYTCallback.postMessage, relayed through
// `ShortsScriptMessageProxy.userContentController(_:didReceive:)`. Mirrors
// TOSPlayerViewModel+WebBridge.swift — see that file's doc comments for why this
// poll-and-relay channel is the only way playback state reaches Swift.
//
// SponsorBlock calls (fetchSponsorSegments in "ready"; checkSponsorSkip/
// logSkipLanding in "tick") are added by Task 6's edits to this file. Watch-history
// (Task 7) lives in ShortsEmbedPlayerViewModel.swift's loadShort/onDisappear, not here.

extension ShortsEmbedPlayerViewModel {

    /// Called from `ShortsScriptMessageProxy` (main thread guaranteed by WKWebView).
    /// - Parameter frameInfo: the originating frame, threaded through from
    ///   `WKScriptMessage.frameInfo` — see `embedFrameInfo`'s doc comment for why
    ///   this is the missing link that fixes `play/seekTo/setPlaybackRate`.
    func handleScriptMessage(_ body: String, frameInfo: WKFrameInfo) {
        guard let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            shortsLog.debug("[\(self.logTag, privacy: .public)] [ytCallback] unparseable message: \(body)")
            return
        }

        // Messages from a frame still showing a Short this VM has since moved away
        // from (two loads within one JS round trip, #275) must not touch its state.
        let frameVideoId = frameInfo.request.url.flatMap(ShortsEmbedURL.videoId(fromEmbedURL:))
        let isStaleFrame = frameVideoId.map { $0 != videoId } ?? false

        switch type {
        case "ping":
            if !frameInfo.isMainFrame, frameVideoId != nil, !isStaleFrame {
                captureEmbedFrame(frameInfo)
            }
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [ytCallback] JS<->Swift bridge ping received — videoId=\(self.videoId, privacy: .public)"
            )
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.shortsplayer.bridge" as CFString),
                nil, nil, true
            )

        case "ready":
            handleReady(json, frameInfo: frameInfo, frameVideoId: frameVideoId, isStaleFrame: isStaleFrame)

        case "stateChange":
            guard !isStaleFrame else { break }
            let raw = (json["state"] as? Int) ?? 999
            playerState = YTPlayerState(raw: raw)
            // Held neighbours suppress notifications and controls manipulation — the
            // live VM's observers must not fire for off-screen WKWebView events.
            if !isLive {
                shortsLog.debug(
                    "[\(self.logTag, privacy: .public)] [ytCallback] stateChange (held) → \(raw) videoId=\(self.videoId, privacy: .public)"
                )
                break
            }
            if playerState == .paused {
                showControls()
                cancelControlsHide()
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [ytCallback] stateChange → paused videoId=\(self.videoId, privacy: .public)"
                )
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.void.smarttube.shortsplayer.paused" as CFString),
                    nil, nil, true
                )
            } else {
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [ytCallback] stateChange → \(raw) videoId=\(self.videoId, privacy: .public)"
                )
            }
            if playerState == .playing {
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.void.smarttube.shortsplayer.playing" as CFString),
                    nil, nil, true
                )
            }

        case "frame":
            guard !isStaleFrame else { break }
            hasFrame = true
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [ytCallback] first frame on screen — videoId=\(self.videoId, privacy: .public)"
            )

        case "diag":
            // Raw <video> element diagnostics straight from the browser, fired
            // every ~2s by stateDetectionJS's pollVideo — see #275. networkState:
            // 0=EMPTY 1=IDLE 2=LOADING 3=NO_SOURCE. readyState: 0=NOTHING
            // 1=METADATA 2=CURRENT_DATA 3=FUTURE_DATA 4=ENOUGH_DATA.
            let networkState = (json["networkState"] as? Int) ?? -1
            let readyState = (json["readyState"] as? Int) ?? -1
            let errorCode = (json["errorCode"] as? Int) ?? -1
            let errorMsg = (json["errorMsg"] as? String) ?? ""
            let paused = (json["paused"] as? Bool) ?? false
            let muted = (json["muted"] as? Bool) ?? false
            let src = (json["src"] as? String) ?? ""
            let ranges = (json["buffered"] as? [[Double]]) ?? []
            let rangesDesc = ranges.map { "\($0.first ?? 0)-\($0.last ?? 0)" }.joined(separator: ",")
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [diag] videoId=\(self.videoId, privacy: .public) networkState=\(networkState, privacy: .public) readyState=\(readyState, privacy: .public) paused=\(paused, privacy: .public) muted=\(muted, privacy: .public) buffered=[\(rangesDesc, privacy: .public)] errorCode=\(errorCode, privacy: .public) errorMsg='\(errorMsg, privacy: .public)' src=\(src, privacy: .public)"
            )

        case "autoUnmuted":
            // One-shot trace from stateDetectionJS's pollVideo: confirms the
            // load-muted-then-unmute workaround dropped the mute once forward
            // playback was observed.
            let unmutedAt = (json["t"] as? Double) ?? -1
            let stillMuted = (json["muted"] as? Bool) ?? true
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [ytCallback] 🔊 auto-unmuted at t=\(unmutedAt, format: .fixed(precision: 2))s — video.muted now \(stillMuted, privacy: .public) videoId=\(self.videoId, privacy: .public)"
            )

        case "tick":
            guard !isStaleFrame else { break }
            let t = (json["t"] as? Double) ?? 0
            let s = (json["state"] as? Int) ?? 999
            currentTime = t
            // Held neighbours suppress tick processing — skip notifications and
            // SponsorBlock checks for the off-screen WKWebView.
            if !isLive { break }
            let newState = YTPlayerState(raw: s)
            if !hasReceivedFirstTick {
                hasReceivedFirstTick = true
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [ytCallback] first tick — state=\(s) t=\(t, format: .fixed(precision: 2))s videoId=\(self.videoId, privacy: .public)"
                )
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.void.smarttube.shortsplayer.tickstarted" as CFString),
                    nil, nil, true
                )
            }
            let wasActivelyPlaying = playerState == .playing || playerState == .buffering
            let isNowActivelyPlaying = newState == .playing || newState == .buffering
            if isNowActivelyPlaying && !wasActivelyPlaying {
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [ytCallback] tick detected active playback (state=\(s)) — firing playing notification videoId=\(self.videoId, privacy: .public)"
                )
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.void.smarttube.shortsplayer.playing" as CFString),
                    nil, nil, true
                )
            }
            if newState != playerState {
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [ytCallback] tick state: \(self.playerState.rawValue) → \(s) at t=\(t, format: .fixed(precision: 1))s videoId=\(self.videoId, privacy: .public)"
                )
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.void.smarttube.shortsplayer.state.\(s)" as CFString),
                    nil, nil, true
                )
            }
            playerState = newState
            checkSponsorSkip(at: t)
            // Confirm/observe the landing of any in-flight auto-skip seek (no-op when
            // none is pending — see PendingSkipLog for why this must happen here, on
            // the next observed tick, rather than synchronously after seekTo()).
            logSkipLanding(at: t)

        case "error":
            guard !isStaleFrame else { break }
            let code = (json["code"] as? Int) ?? -1
            let errText = (json["text"] as? String) ?? ""
            let errName: String
            switch code {
            case 2:
                errName = "invalid-param"
                playerError = .iframeError(code)
            case 5:
                errName = "html5-not-supported"
                playerError = .iframeError(code)
            case 100:
                errName = "video-not-found"
                playerError = .notFound
            case 101, 150:
                errName = "embedding-disabled"
                playerError = .embeddingDisabled
            case 153:
                errName = "player-config-error"
                playerError = .iframeError(code)
            default:
                errName = "unknown(\(code))"
                playerError = .iframeError(code)
            }
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [ytCallback] ❌ player error \(code) (\(errName)) text='\(errText)' isFatal=\(self.playerError?.isFatal ?? false) videoId=\(self.videoId, privacy: .public)"
            )
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.shortsplayer.error.\(code)" as CFString),
                nil, nil, true
            )

        default:
            break
        }
    }

    /// The `ready` message: the embed's player loaded its video.
    private func handleReady(
        _ json: [String: Any], frameInfo: WKFrameInfo, frameVideoId: String?, isStaleFrame: Bool
    ) {
        // STALE-LOAD GUARD: if loadShort(video:) was called again before this
        // frame's "ready" arrived (e.g. two swipes/auto-advances within the
        // same ~100-200ms JS round-trip window — confirmed happening via the
        // per-VM/videoId log tags added in #275), this message belongs to an
        // ABANDONED load, not the currently-intended video. Accepting it would
        // poison `embedFrameInfo` with a detached frame — every later eval()
        // (play/pause/setPlaybackRate) would then silently target dead content,
        // which is exactly the "JS bridge says ready but nothing ever plays"
        // symptom #275 was chasing. Detect by comparing the frame's own embed
        // URL (which encodes its videoId) against `self.videoId` (the video
        // loadShort(_:) most recently set) — they only match for the load this
        // VM is actually waiting on.
        if let frameVideoId, isStaleFrame {
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [ytCallback] ready DISCARDED — stale load for videoId=\(frameVideoId, privacy: .public), current videoId=\(self.videoId, privacy: .public)"
            )
            return
        }

        // Cancel the "ready" timeout started by loadShort() — see
        // startReadyTimeout(for:) (ShortsEmbedPlayerViewModel.swift).
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil

        // CAPTURE the embed iframe's frame info — `embedFrameInfo` is reset to
        // nil in loadShort(), so each iframe-src swap re-captures its own
        // frame here exactly once. See embedFrameInfo's doc comment
        // (ShortsEmbedPlayerViewModel.swift) for the full root-cause story.
        captureEmbedFrame(frameInfo)
        isReady = true
        duration = (json["duration"] as? Double) ?? 0
        shortsLog.notice(
            "[\(self.logTag, privacy: .public)] [ytCallback] ready — videoId=\(self.videoId, privacy: .public) duration=\(self.duration, format: .fixed(precision: 1))s"
        )
        // A held neighbour posts "ready" from activate() instead, so observers
        // only ever hear about the Short on screen.
        if isLive {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.shortsplayer.ready" as CFString),
                nil, nil, true
            )
        }
        // Kick off SponsorBlock segment loading for this Short — parity with
        // TOSPlayerViewModel+WebBridge.swift's "ready" case.
        sponsorTask?.cancel()
        sponsorTask = Task { await self.fetchSponsorSegments() }
        // Apply the user's saved playback-speed preference — parity with
        // TOSPlayerViewModel+WebBridge.swift's "ready" case.
        if settings.playbackSpeed != 1.0 {
            setPlaybackRate(settings.playbackSpeed)
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [ytCallback] applied saved playback speed \(self.settings.playbackSpeed, format: .fixed(precision: 2))×"
            )
        }
    }

    /// Records the embed iframe's frame (the target of every `eval`) the first time
    /// it reports in for the current Short, and tells it whether it is live or held —
    /// see `embedFrameInfo`'s doc comment (ShortsEmbedPlayerViewModel.swift).
    func captureEmbedFrame(_ frameInfo: WKFrameInfo) {
        guard embedFrameInfo == nil else { return }
        embedFrameInfo = frameInfo
        shortsLog.notice(
            "[\(self.logTag, privacy: .public)] [frame] captured embed iframe frameInfo — isMainFrame=\(frameInfo.isMainFrame, privacy: .public) url=\(frameInfo.request.url?.absoluteString ?? "nil", privacy: .public)"
        )
        applyPlaybackMode()
    }
}
#endif  // !os(tvOS)
