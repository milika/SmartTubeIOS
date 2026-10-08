#if !os(tvOS)
import Foundation
import os
import SmartTubeIOSCore

private let shortsLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsPlayer")

// MARK: - View State
//
// Controls visibility, isPlaying/togglePlayPause, errorMessage, and
// background/foreground lifecycle — gives ShortsEmbedPlayerViewModel the same
// name-matching surface PlaybackViewModel already exposes, so ShortsPlayerView's
// shared (non-#if) call sites (onAppear, onDisappear, .onChange(of: scenePhase),
// the controls overlay) work unchanged for either view model.

extension ShortsEmbedPlayerViewModel {

    var isPlaying: Bool {
        playerState == .playing || playerState == .buffering
    }

    var currentVideoId: String { videoId }

    var errorMessage: String? {
        guard let playerError else { return nil }
        switch playerError {
        case .notFound:
            return "This video isn't available."
        case .embeddingDisabled:
            return "This video can't be played here."
        case .iframeError:
            return "This video can't be played right now."
        case .webViewLoadFailed:
            return "Couldn't load this video."
        case .signInRequired:
            return "YouTube asked to sign in before playing this video."
        }
    }

    func showControls() {
        controlsVisible = true
        scheduleControlsHide()
    }

    func cancelControlsHide() {
        controlsTimer?.cancel()
        controlsTimer = nil
    }

    func toggleControls() {
        if controlsVisible {
            controlsVisible = false
            cancelControlsHide()
        } else {
            showControls()
        }
    }

    private func scheduleControlsHide() {
        controlsTimer?.cancel()
        controlsTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            self.controlsVisible = false
        }
    }

    func togglePlayPause() {
        shortsLog.notice(
            "[togglePlayPause] called — videoEnded=\(self.videoEnded, privacy: .public) playerState=\(self.playerState.rawValue, privacy: .public) isPlaying=\(self.isPlaying, privacy: .public) t=\(Date().timeIntervalSinceReferenceDate, format: .fixed(precision: 3), privacy: .public)"
        )
        if videoEnded {
            videoEnded = false
            seekTo(0)
            play()
        } else if isPlaying {
            pause()
        } else {
            play()
        }
        showControls()
    }

    func handleBackground() {
        guard !settings.backgroundPlaybackEnabled else { return }
        guard isPlaying else { return }
        wasPlayingBeforeSuspend = true
        pause()
    }

    func handleForeground() {
        guard wasPlayingBeforeSuspend else { return }
        wasPlayingBeforeSuspend = false
        play()
    }

    func resume() {
        wasPlayingBeforeSuspend = false
        play()
    }

    func stop() {
        pause()
        cancelControlsHide()
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil
        sponsorTask?.cancel()
        sponsorTask = nil
        saveProgress()
    }
}
#endif  // !os(tvOS)
