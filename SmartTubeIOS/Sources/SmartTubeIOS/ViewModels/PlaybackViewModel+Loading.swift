import AVFoundation
import os
#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif
import SmartTubeIOSCore

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - Load Video Lifecycle

extension PlaybackViewModel {

    public func load(video: Video) {
        playerLog.notice("[load] load() called — id=\(video.id) currentVideo=\(self.currentVideo?.id ?? "nil") isLoading=\(self.isLoading) player.item=\(self.player.currentItem != nil)")
        playerLog.notice("[benchmark] load started — videoId=\(video.id) title=\(video.title)")
        videoLoadStartedAt = Date()
        lastSuccessfulStreamType = "unknown"
        timeToPlayMs = 0
        timeToHighQualityMs = 0
        cacheStatusSummary = ""
        if currentVideo?.id == video.id, !isLoading {
            playerLog.notice("[load] re-opening same video \(video.id) — stop() may have deactivated AVAudioSession")
        } else if let prev = currentVideo, prev.id != video.id, !isLoading {
            playerLog.notice("[load] switching from \(prev.id) to \(video.id) after stop()")
        }
        // If the exact same video is already being loaded, ignore the duplicate call.
        // SwiftUI can trigger load() multiple times during a single navigation (e.g.
        // selectedVideo binding re-evaluated while a queue autoplay is in flight).
        // Each duplicate spawns its own loadAsync → its own Crashlytics event storm.
        if currentVideo?.id == video.id, isLoading {
            playerLog.notice("[load] already loading \(video.id) — ignoring duplicate call")
            return
        }
        CrashlyticsLogger.setVideoContext(id: video.id, title: video.title)
        // Cancel any previous in-flight load so we never have two concurrent API
        // fetches for the same (or different) video running at the same time.
        loadTask?.cancel()
        itemStartupWatchdogTask?.cancel()
        itemStartupWatchdogTask = nil
        loadDeadlineTask?.cancel()
        loadDeadlineTask = nil
        #if canImport(WebKit)
        // fix10: preserve the pre-warm task when the same video is re-tapped after stop().
        // racePathB will await earlyTask.value and get the result when extraction completes
        // (~0.75s after tap if stop() started it 0.5s earlier) instead of ~1.25s from scratch.
        // For different-video navigation, cancel as before.
        if wkHLSEarlyTaskVideoId != video.id {
            wkHLSEarlyTask?.cancel()
            wkHLSEarlyTask = nil
            wkHLSEarlyTaskVideoId = nil
            wkHLSPermissionDenied = false
        }
        #endif

        // fix12: Same-video re-open fast path — if stop() parked the AVPlayerItem and it is
        // still .readyToPlay, bypass the entire exhaustiveRetry race (~1.27s saved per hot
        // cycle). Re-activates AVAudioSession, wires end/stall observers, and resumes.
        // Expected: <0.1s in-app → ~0.5s reported (XCTest polling overhead only).
        if let parked = parkedVideoId,
           parked == video.id,
           let parkedItem = player.currentItem,
           parkedItem.status == .readyToPlay {
            playerLog.notice("[fix12] same-video re-open — reusing parked AVPlayerItem for \(video.id)")
            parkedVideoId = nil
            // Cancel the now-useless wkHLS serialExtract started by stop().
            #if canImport(WebKit)
            wkHLSEarlyTask?.cancel()
            wkHLSEarlyTask = nil
            wkHLSEarlyTaskVideoId = nil
            #endif
            currentVideo = video
            isLoading = false
            isPlaying = false
            videoEnded = false
            error = nil
            wasPlayingBeforeSuspend = false
            // Re-wire end-of-playback and stall observers on the still-alive item.
            endObserverTask?.cancel()
            endObserverTask = Task { [weak self, parkedItem] in
                let notifications = NotificationCenter.default.notifications(
                    named: AVPlayerItem.didPlayToEndTimeNotification, object: parkedItem
                )
                for await _ in notifications {
                    guard let self, !Task.isCancelled else { return }
                    self.handlePlaybackEnd()
                }
            }
            stallObserverTask?.cancel()
            stallObserverTask = Task { @MainActor [weak self, parkedItem] in
                let notifications = NotificationCenter.default.notifications(
                    named: AVPlayerItem.playbackStalledNotification, object: parkedItem
                )
                for await _ in notifications {
                    guard let self, !Task.isCancelled else { return }
                    self.stallCount += 1
                    playerLog.notice("[fix12/stall] playbackStalled at t=\(Int(self.currentTime))s #\(self.stallCount)")
                }
            }
            #if canImport(UIKit)
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                playerLog.error("[fix12] AVAudioSession setActive failed: \(error.localizedDescription)")
            }
            setupRemoteCommandCenter()
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            player.rate = Float(settings.playbackSpeed)
            isPlaying = true
            return
        }
        // Different video or parked item expired — clear parked state and tear down old item.
        if parkedVideoId != nil {
            player.replaceCurrentItem(with: nil)
            parkedVideoId = nil
        }

        // Report watchtime for the video being replaced before tearing it down.
        // This is the only opportunity when switching via load() directly (e.g. autoplay),
        // since stop()/suspend() are not called in that path.
        if settings.historyState == .enabled, duration > 0 {
            let pos = self.currentTime
            let dur = self.duration
            let flush = tracker.transition(to: video.id, cpn: InnerTubeAPI.generateCPN(),
                                           flushPosition: pos, flushDuration: dur)
            Task { await flush() }
        } else {
            tracker.transition(to: video.id, cpn: InnerTubeAPI.generateCPN(),
                               flushPosition: 0, flushDuration: 0)
        }

        // Stop and clear the current item immediately so the previous frame
        // is not visible while the next video is loading.
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        videoEnded = false
        wasPlayingBeforeSuspend = false
        currentTime = 0
        duration = 0
        error = nil
        playerInfo = nil
        controlsVisible = false
        controlsTimer?.cancel()
        seekDebounceTask?.cancel()
        isScrubbing = false
        chapters = []
        captionsManager.reset()
        audioManager.reset()
        endCards = []

        // Push the currently playing video onto the history stack before switching
        if let prev = currentVideo {
            history.append(prev)
        }
        currentVideo = video
        // fix236: Record the intended video at load() time so checkWrongVideoOnFirstPlay()
        // can detect if a stale task swaps currentVideo before readyToPlay fires.
        intendedVideoId = video.id
        intendedVideoTitle = video.title
        pendingWrongVideoCheck = true
        hasPrevious = !history.isEmpty
        retryAttempts = 0
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        #if os(tvOS)
        tvEmbeddedEarlyTask?.cancel()
        tvEmbeddedEarlyTask = nil
        #endif
        qualityManager.reset()
        phase2Task?.cancel()
        phase2Task = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        AVAssetTrackCache.shared.clear()

        // UI-testing synchronous inject for related videos.
        // Checked here (before the Task is created) so that hasNext = true is set
        // before the first XCTest accessibility-tree snapshot.  The async path in
        // loadAsync contains the same check and is kept as a belt-and-suspenders
        // guard in case load() is ever called without going through this entry point.
        if let relArg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--uitesting-inject-related-video-ids=")
        }) {
            let raw = String(relArg.dropFirst("--uitesting-inject-related-video-ids=".count))
            let ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            if !ids.isEmpty {
                relatedVideos = ids.map { Video(id: $0, title: $0, channelTitle: "Test Channel") }
                hasNext = true
                playerLog.notice("UI-testing sync inject: set \(ids.count) related videos before Task")
            }
        }

        // Show the loading spinner synchronously — set before the Task starts so the
        // first frame of PlayerView already has isLoading=true. Without this, there is a
        // one-frame gap (one run-loop cycle) where the PlayerView renders with isLoading=false,
        // making the spinner invisible until the Task runs and sets it inside loadAsync().
        isLoading = true
        scheduleLoadDeadline(for: video)
        // UI-testing: re-show controls after load() resets controlsVisible=false.
        // Mirrors the onAppear --uitesting-show-controls handling so controls remain
        // visible across queue advances without relying on a second onAppear trigger.
        #if !os(iOS)
        if ProcessInfo.processInfo.arguments.contains("--uitesting-show-controls") {
            showControls()
            cancelControlsHide()
        }
        #endif
        loadTask = Task { await loadAsync(video: video) }

        // Kick off a background prefetch for the next video in the queue
        // so its PlayerInfo is warm in VideoPreloadCache before it is needed.
        // This fires immediately on load() so the full video duration is
        // available as warm-up time, rather than waiting until playback ends.
        if video.playlistId == CurrentQueueStore.playlistID,
           let nextIndex = video.playlistIndex.map({ $0 + 1 }) {
            prefetchQueueVideo(at: nextIndex)
            // The queue has a next item — enable the next button immediately so
            // the user can advance before related videos finish loading.
            hasNext = true
        }
    }

    /// User-initiated retry after all automatic fallbacks have been exhausted.
    /// Resets the retry guard and reloads the current video from scratch.
    public func retryLoad() {
        guard let video = currentVideo else { return }
        error = nil
        retryAttempts = 0
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        loadTask?.cancel()
        isLoading = true
        scheduleLoadDeadline(for: video)
        loadTask = Task { [weak self] in
            guard let self else { return }
            await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
            await self.loadAsync(video: video)
        }
    }

    /// Prevents the complete native fallback chain from keeping the loading UI alive
    /// forever. This is deliberately longer than the per-item timeout so at least one
    /// fallback can be attempted before the user is offered Retry.
    private func scheduleLoadDeadline(for video: Video) {
        loadDeadlineTask?.cancel()
        loadDeadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled,
                  let self,
                  self.isLoading,
                  self.currentVideo?.id == video.id else { return }

            playerLog.error("❌ Native playback load timed out after 30s — videoId=\(video.id)")
            self.loadTask?.cancel()
            self.exhaustiveRetryTask?.cancel()
            self.exhaustiveRetryTask = nil
            self.itemObserverTask?.cancel()
            self.itemObserverTask = nil
            self.itemStartupWatchdogTask?.cancel()
            self.itemStartupWatchdogTask = nil
            self.player.pause()
            self.player.replaceCurrentItem(with: nil)
            self.isPlaying = false
            self.isLoading = false
            self.error = APIError.unavailable("Stream loading timed out. Please retry.")
        }
    }

    /// Call when the app returns to the foreground and this PlayerView is the visible one.
    /// Reactivates the AVAudioSession and resumes the player if it was playing
    /// before the interruption/background transition.
    public func handleForeground() {
        guard player.currentItem != nil else { return }
        #if canImport(UIKit)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playerLog.error("AVAudioSession reactivation failed: \(error.localizedDescription)")
        }
        #endif
        // Resume only if we consider ourselves to be in playing state.
        // isPlaying is kept in sync with player.rate via KVO, so this only fires
        // when the player was paused while still intending to play (e.g. background transition).
        if isPlaying && player.rate == 0 {
            player.rate = Float(settings.playbackSpeed)
            playerLog.notice("[handleForeground] resumed player after foreground transition")
        }
    }

    /// Call when the app enters the background.
    /// Pauses playback when the user has disabled background audio.
    public func handleBackground() {
        guard !settings.backgroundPlaybackEnabled else { return }
        guard isPlaying else { return }
        player.pause()
        // isPlaying is synced to false by the rate KVO observer.
        playerLog.notice("[handleBackground] background playback disabled — paused")
    }

    /// Pauses playback and saves the watch position without tearing down the AVPlayerItem.
    /// Called when the PlayerView temporarily disappears (e.g. a sheet slides over it).
    /// Use `resume()` to restart playback, or `load(video:)` to switch videos.
    public func suspend() {
        playerLog.notice("[suspend] suspend() called — currentVideo=\(self.currentVideo?.id ?? "nil") currentTime=\(Int(self.currentTime))s")
        if settings.historyState == .enabled, duration > 0 {
            let pos = self.currentTime
            let dur = self.duration
            Task {
                await self.tracker.checkpoint(position: pos, duration: dur)
                playerLog.notice("Saved position \(Int(pos))s for suspend")
            }
        }
        wasPlayingBeforeSuspend = isPlaying
        player.pause()
        isPlaying = false
        controlsTimer?.cancel()
        // Cancel in-flight load tasks so their @Observable state mutations do not
        // fire after the PlayerView has been removed from the SwiftUI hierarchy.
        // Without this, exhaustiveRetry callbacks crash with "No Observable object of
        // type SettingsStore found" when a sub-view rebuilds after dismiss.
        // Firebase: a013be1c (EXC_BREAKPOINT in EnvironmentValues.subscript.getter).
        loadTask?.cancel()
        loadTask = nil
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        // rateObserver's KVO closure can independently re-spawn a brand-new
        // exhaustiveRetryTask (see setupRateObserver()'s "rapid stall loop"
        // escalation) — it was never invalidated outside deinit, so it kept firing
        // after suspend() and undoing the cancellation above, recreating the same
        // crash task-190 was supposed to have fixed. Re-established in resume().
        // Firebase: a013be1c, regressed June 8 in 4.4(2) — still happening in 4.6.
        rateObserver?.invalidate()
        rateObserver = nil
        #if canImport(WebKit)
        wkHLSEarlyTask?.cancel()
        wkHLSEarlyTask = nil
        wkHLSEarlyTaskVideoId = nil
        #endif
        isLoading = false
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        updateNowPlayingPlayback()
        // Deregister from the global command center so a suspended VM never
        // handles lock screen Play while another VM is the active player.
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        #endif
    }

    /// Resumes playback after a `suspend()`. If the player has no current item
    /// (e.g. `stop()` was called), this is a no-op — use `load(video:)` instead.
    public func resume() {
        guard player.currentItem != nil else {
            playerLog.notice("[resume] no item — skipping resume")
            return
        }
        playerLog.notice("[resume] resume() called — currentVideo=\(self.currentVideo?.id ?? "nil")")
        wasPlayingBeforeSuspend = false
        #if canImport(UIKit)
        // Re-register lock screen commands (removed in suspend()).
        setupRemoteCommandCenter()
        #endif
        // Re-establish the rate KVO observer (invalidated in suspend()) so isPlaying
        // stays in sync with the player again for this resumed session.
        setupRateObserver()
        player.rate = Float(settings.playbackSpeed)
        isPlaying = true
        showControls()
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        updateNowPlayingPlayback()
        #endif
    }

    func loadAsync(video: Video) async {
        // Defensive re-establish: guarantees rateObserver is live for every load,
        // even if this view model instance went through suspend() (which
        // invalidates it) and is now loading a different video directly via
        // load()/loadAsync() rather than resume(). Idempotent — safe to call even
        // when already set up.
        setupRateObserver()
        isLoading = true
        stallCount = 0
        firstRapidStallTime = nil
        needsQuickStartup = true
        // Note: isLoading = false is set in the AVPlayerItem .readyToPlay observer so the
        // spinner stays visible until the first frame is actually ready. It was previously
        // cleared after player.rate was set, which dismissed the spinner before buffering
        // completed on slow networks (GitHub issue #53).
        playerLog.notice("[loadAsync] start id=\(video.id) title=\(video.title) player.rate=\(self.player.rate) timeControlStatus=\(self.player.timeControlStatus.rawValue)")

        #if canImport(UIKit)
        // Seed the lock-screen Now Playing widget BEFORE the ~10 s network phase so
        // the user sees the title/channel on the lock screen immediately.
        // stop() calls setActive(false) which tears down the MediaRemote XPC connection;
        // re-activating here (rather than waiting until readyToPlay) closes the gap
        // during which PlayerRemoteXPC reports err=-12860/-12785 and the widget is absent.
        setupRemoteCommandCenter()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            playerLog.notice("[loadAsync] AVAudioSession activated early (lock-screen pre-seed)")
        } catch {
            playerLog.error("[loadAsync] early setActive failed: \(error.localizedDescription)")
        }
        updateNowPlayingInfo()
        #endif

        // Fetch the BotGuard PO token before the primary stream attempt.
        // Awaited (with a 2 s safety timeout) so api.hasPoToken(for:) returns true during
        // the rqh=1 adaptive stream check in tryAllStreams — preventing an unnecessary
        // WKWebView fallback on every cold start.
        // BotGuardClient completes in <500 ms on first run; cached result returns in <1 ms
        // thereafter (TTL ~12 h). The 2 s timeout is a safety net for slow networks only.
        let capturedAPI = api
        let capturedVideoId = video.id
        if !(await api.hasPoToken(for: video.id)) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await capturedAPI.prefetchPoToken(for: capturedVideoId) }
                group.addTask { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                _ = await group.next()
                group.cancelAll()
            }
        }
        #if canImport(WebKit)
        // Fire-and-forget: start WKWebView BotGuard pipeline in the background.
        // Takes 3–8 s; by the time the primary attempt fails and exhaustiveRetry runs,
        // it may be ready to provide a full getMinter-minted token (CDN-accepted for rqh=1).
        // Zero impact on primary path timing — runs concurrently.
        if !BotGuardWebViewRunner.shared.isReady {
            let capturedVideoIdForWV = video.id
            Task { @MainActor in
                await BotGuardWebViewRunner.shared.prepare(for: capturedVideoIdForWV)
            }
        }
        // Fire-and-forget: start WKWebView HLS extraction concurrently with the primary path.
        // For rqh=1 videos the ~2 s extraction overlaps the primary iOS attempt so the URL
        // is ready (or nearly ready) by the time exhaustiveRetry reaches Phase -2, saving
        // the serial 2–4 s wait. For non-rqh=1 videos the task completes silently unused.
        // Use priorityExtract() (not serialExtract) so earlyTask starts wv.load() IMMEDIATELY
        // without waiting for any in-flight VideoCardView second-serialExtract. A background
        // card extraction (e.g. POTUARPb1CU) may have captured pendingSerialTask just before
        // the tap; chaining onto it (serialExtract's behaviour) delays wv.load() by ~2.3 s,
        // making CDN trust too stale (~0.5 s) for AndroidVR loadTracks (R12 regression).
        // priorityExtract registers itself in pendingSerialTask so race-failed handlers still
        // chain onto it correctly via serialExtract.
        let capturedVideoIdForHLS = video.id
        // Reuse an in-flight pre-warm started by stop() for the same video (fix10).
        // If stop() already started serialExtract for this videoId, wkHLSEarlyTask is
        // non-nil and for the same video — just let it run; racePathB awaits its value.
        if wkHLSEarlyTask == nil {
            wkHLSEarlyTaskVideoId = capturedVideoIdForHLS
            wkHLSEarlyTask = Task { @MainActor in
                // priorityExtract bypasses pendingSerialTask chaining → wv.load() starts
                // immediately at tap time. For pfa/1 rqh=1 videos like _DY9cTWakcM, this
                // refreshes CDN IP-level trust so it is only ~2.5 s old when AndroidVR
                // loadTracks runs — within the ~2.5 s trust window.
                return await YouTubeWebViewHLSExtractor.shared.priorityExtract(videoId: capturedVideoIdForHLS)
            }
        }
        #endif

        // Local-file fast path — bypass all network fetches for downloaded videos.
        // The path must be inside Documents/SmartTubeDownloads/ to prevent path-traversal
        // from a crafted Video object.
        if let localURL = video.localFileURL {
            let downloadsDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SmartTubeDownloads").path
            if localURL.path.hasPrefix(downloadsDir),
               FileManager.default.fileExists(atPath: localURL.path) {
                let item = AVPlayerItem(url: localURL)
                item.audioTimePitchAlgorithm = .spectral
                // Wire up observers BEFORE replaceCurrentItem (task-80 rule).
                itemObserverTask?.cancel()
                itemObserverTask = Task { [weak self] in
                    for await status in item.statusStream {
                        guard let self, !Task.isCancelled else { return }
                        switch status {
                        case .readyToPlay:
                            playerLog.notice("[benchmark] readyToPlay — local-file — videoId=\(video.id) title=\(video.title)")
                            self.loadAudioTracks(from: item)
                            self.isLoading = false
                        case .failed:
                            playerLog.error("❌ local-file AVPlayerItem failed: \(String(describing: item.error))")
                            self.error = item.error
                        case .unknown:
                            break
                        @unknown default:
                            break
                        }
                    }
                }
                player.replaceCurrentItem(with: item)
                endObserverTask?.cancel()
                endObserverTask = Task { [weak self] in
                    let notifications = NotificationCenter.default.notifications(
                        named: AVPlayerItem.didPlayToEndTimeNotification,
                        object: item
                    )
                    for await _ in notifications {
                        guard let self, !Task.isCancelled else { return }
                        self.handlePlaybackEnd()
                    }
                }
                stallObserverTask?.cancel()
                stallObserverTask = Task { @MainActor [weak self] in
                    let notifications = NotificationCenter.default.notifications(
                        named: AVPlayerItem.playbackStalledNotification,
                        object: item
                    )
                    for await _ in notifications {
                        guard let self, !Task.isCancelled else { return }
                        self.stallCount += 1
                        let t = Int(self.currentTime)
                        playerLog.notice("[stall] AVPlayerItemPlaybackStalled at t=\(t)s stall#\(self.stallCount) video=\(self.currentVideo?.id ?? "unknown")")
                        let stallError = NSError(
                            domain: "SmartTube.PlaybackStall",
                            code: 0,
                            userInfo: [NSLocalizedDescriptionKey: "AVPlayerItemPlaybackStalled at t=\(t)s (stall #\(self.stallCount))"]
                        )
                        playerLog.recordNonFatal(stallError, userInfo: [
                            "video_id":       self.currentVideo?.id ?? "unknown",
                            "stall_at_time":  String(t),
                            "stall_count":    String(self.stallCount),
                            "video_duration": String(Int(self.duration)),
                            "stall_trigger":  "AVPlayerItemPlaybackStalled"
                        ])
                        // Stall recovery (#193): wait 2 s for AVPlayer to self-heal;
                        // if still stalled, nudge the pipeline with a near-zero seek
                        // + explicit rate restore. Capped at 3 attempts per item.
                        let recoveryCount = self.stallCount
                        if recoveryCount <= 3 {
                            Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                guard let self, self.isPlaying, self.player.rate == 0,
                                      !self.isQualityChangePending else { return }
                                let seekT = self.currentTime
                                playerLog.notice("[stall] recovery#\(recoveryCount): seeking to \(seekT)s to flush pipeline")
                                self.player.seek(
                                    to: CMTime(seconds: seekT, preferredTimescale: 600),
                                    toleranceBefore: .zero,
                                    toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
                                ) { [weak self] _ in
                                    Task { @MainActor [weak self] in
                                        guard let self, self.isPlaying else { return }
                                        self.player.rate = Float(self.settings.playbackSpeed)
                                        playerLog.notice("[stall] recovery#\(recoveryCount): rate restored")
                                    }
                                }
                            }
                        }
                    }
                }
                #if canImport(UIKit)
                setupRemoteCommandCenter()
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    playerLog.error("[loadAsync] local: AVAudioSession setActive failed: \(error.localizedDescription)")
                }
                #endif
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                // Downloaded videos have no related videos — clear any stale state from a
                // previous YouTube session so autoplay does not fire a YouTube video when
                // the download ends. (Bug #224: wrong video played after local file ends.)
                relatedVideos = []
                hasNext = false
                #if canImport(UIKit)
                UIApplication.shared.isIdleTimerDisabled = true
                updateNowPlayingInfo()
                #endif
                playerLog.notice("[loadAsync] local-file fast path: playing \(localURL.lastPathComponent)")
                return
            }
            // File missing or path invalid — fall through to network re-stream.
            playerLog.notice("[loadAsync] localFileURL set but file not accessible, falling through: \(localURL.path)")
        }

        do {
            // --- Cache-first load ---
            // Check VideoPreloadCache for all data types. Fresh hits skip the network
            // call entirely; partial hits fill only the missing pieces in parallel.
            let cached = await VideoPreloadCache.shared.consume(videoId: video.id)
            // Log the full cache verdict as a single breadcrumb so wrong-video / prefetch-race
            // scenarios are immediately visible in Firebase reports.
            let cacheVerdict = "playerInfo=\(cached.playerInfo != nil) nextInfo=\(cached.nextInfo != nil) sponsor=\(cached.sponsorSegments != nil) endCards=\(cached.endCards != nil) tracking=\(cached.trackingURLs != nil) complete=\(cached.isComplete)"
            if cached.playerInfo != nil {
                playerLog.notice("PREFETCH_HIT: \(video.id) — \(cacheVerdict)")
            } else {
                playerLog.notice("PREFETCH_MISS: \(video.id) — \(cacheVerdict)")
            }
            let wkHLSCacheHit = await VideoPreloadCache.shared.cachedWKHLSURL(for: video.id) != nil
            self.cacheStatusSummary = "pi:\(cached.playerInfo != nil ? "HIT" : "MISS") wkHLS:\(wkHLSCacheHit ? "HIT" : "MISS")"

            // Apply cached DeArrow overrides (community title / thumbnail timestamp).
            // Done immediately after consume() so VideoCardView can show the override
            // as soon as the player screen appears, before Phase 2 completes.
            if settings.deArrowEnabled, let deArrow = cached.deArrowBranding {
                currentVideo?.deArrowTitle = deArrow.title
                currentVideo?.deArrowThumbnailTimestamp = deArrow.thumbnailTimestamp
            }

            // --- Player info (stream URLs + metadata) ---
            // Kick off an authenticated TV-client player request in parallel with the
            // primary iOS player fetch when the cache doesn't already have tracking URLs.
            // cached.trackingURLs is PlaybackTrackingURLs?? — .some(nil) means the prefetch
            // ran before auth was ready; treat that as a miss so we still get live URLs.
            let cachedTrackingURLs: PlaybackTrackingURLs? = cached.trackingURLs.flatMap { $0 }
            let authTrackingTask: Task<PlaybackTrackingURLs?, Never>?
            if cachedTrackingURLs != nil {
                // Tracking URLs came from the cache; no need for a parallel TV-client call.
                authTrackingTask = nil
            } else {
                authTrackingTask = Task<PlaybackTrackingURLs?, Never> { [api = self.api] in
                    await api.fetchAuthenticatedTrackingURLs(videoId: video.id)
                }
            }

            // Fetch player info using the iOS client (unauthenticated).
            // If YouTube returns UNPLAYABLE/LOGIN_REQUIRED and the user is signed in,
            // automatically retry with the authenticated TV client before showing an error.
            let info: PlayerInfo
            if let cachedInfo = cached.playerInfo {
                playerLog.notice("PREFETCH_HIT: playerInfo for \(video.id) — skipping network (hls=\(cachedInfo.hlsURL != nil) dash=\(cachedInfo.dashURL != nil) formats=\(cachedInfo.formats.count))")
                info = cachedInfo
            } else if let inFlight = await VideoPreloadCache.shared.inFlightPlayerFetch(videoId: video.id),
                      let coalescedInfo = await inFlight.value {
                playerLog.notice("PREFETCH_COALESCE: playerInfo for \(video.id) — joined in-flight prefetch task")
                info = coalescedInfo
            } else {
                do {
                    info = try await api.fetchPlayerInfo(videoId: video.id)
                } catch {
                    if case APIError.ipBlocked(let reason) = error {
                        // NW-6-FIX: IP-block short-circuit. Every extra /player call from a
                        // blocked IP can extend the block duration — skip ALL retries,
                        // including the TV-authenticated path (an authenticated request
                        // carries the same blocked IP and will fail too). Throw immediately
                        // so the error banner appears with the specific VPN message and
                        // without a "Try Again" button. Suppress Crashlytics recording —
                        // this is a user-side network condition, not an app bug.
                        playerLog.error("⚠️ iOS client detected IP block — reason: \(reason)")
                        throw error
                    } else if case APIError.unavailable = error, hasAuthToken {
                        playerLog.notice("⚠️ iOS client returned unavailable — retrying with authenticated TV client")
                        do {
                            var tvInfo = try await api.fetchPlayerInfoAuthenticated(videoId: video.id)
                            // NW-3-FIX: TV client may return no HLS manifest and no adaptive
                            // streams for DRM/protected or region-locked content
                            // (hlsURL=nil, bestAdaptiveVideoURL=nil). Attempting to play the
                            // TV muxed direct URL (itag=18, c=TVHTML5) fails with
                            // AVFoundationErrorDomain -11828 / NSOSStatusErrorDomain -12847.
                            // Skip the unnecessary AVPlayer attempt and go straight to the
                            // Android client.
                            if tvInfo.hlsURL == nil,
                               tvInfo.bestAdaptiveVideoURL == nil || tvInfo.bestAdaptiveAudioURL == nil {
                                playerLog.notice("⚠️ TV client returned no HLS/adaptive streams — falling through to Android client")
                                tvInfo = try await api.fetchPlayerInfoAndroid(videoId: video.id)
                            }
                            info = tvInfo
                        } catch {
                            if case APIError.unavailable = error {
                                // TV client also returned unavailable / cipher-protected formats.
                                // Fall through to the Android client as a last resort.
                                playerLog.notice("⚠️ TV client also unavailable — retrying with Android client")
                                info = try await api.fetchPlayerInfoAndroid(videoId: video.id)
                            } else {
                                throw error
                            }
                        }
                    } else {
                        throw error
                    }
                }
                await VideoPreloadCache.shared.store(playerInfo: info, for: video.id)
            }
            // BUG-005 fix: guard against rapid navigation — if the user navigated away while we
            // were awaiting the player info, discard this result rather than overwrite ViewModel state.
            guard currentVideo?.id == video.id else {
                playerLog.notice("[loadAsync] superseded: discarding playerInfo for \(video.id)")
                return
            }
            playerInfo = info
            availableFormats = Self.deduplicatedVideoFormats(info.formats)
            playerLog.notice("[loadAsync] availableFormats after initial dedup: raw=\(info.formats.count) deduped=\(availableFormats.count) maxH=\(availableFormats.map(\.height).max() ?? 0)")
            availableCaptions = info.captionTracks
            autoApplyCaptionPreference(tracks: info.captionTracks)
            selectedFormat = nil

            playerLog.notice("playerInfo: formats=\(info.formats.count) hlsURL=\(info.hlsURL?.absoluteString ?? "nil") dashURL=\(info.dashURL?.absoluteString ?? "nil")")
            for (i, fmt) in info.formats.enumerated() {
                playerLog.notice("  format[\(i)] mimeType=\(fmt.mimeType) quality=\(fmt.label) url=\(fmt.url?.absoluteString.prefix(80) ?? "nil")")
            }

            let prefURL = info.preferredStreamURL
            playerLog.notice("preferredStreamURL=\(prefURL?.absoluteString.prefix(120) ?? "nil")")

            // --- SponsorBlock ---
            // Segments from the cache are applied inline (fast path, zero network cost).
            // Stale segments are applied immediately and revalidated in Phase 2.
            // When not cached, the fetch is deferred to Phase 2 (runs concurrently with
            // AVPlayer buffering) so it does not block the spinner.
            sponsorSegments = []
            let channelIsExcluded = video.channelId.map {
                settings.sponsorBlockExcludedChannels.keys.contains($0)
            } ?? false
            playerLog.notice("[sponsorBlock] enabled=\(settings.sponsorBlockEnabled) channelExcluded=\(channelIsExcluded) categories=\(settings.activeSponsorCategories.count)")
            var sponsorCached = false
            if settings.sponsorBlockEnabled, !channelIsExcluded {
                if let cachedSegments = cached.sponsorSegments {
                    // Cache hit (fresh or stale) — apply immediately.
                    let isStaleSponsor = cached.staleFields.contains(.sponsorSegments)
                    let minDur = settings.sponsorBlockMinSegmentDuration
                    let filtered = minDur > 0
                        ? cachedSegments.filter { ($0.end - $0.start) >= minDur }
                        : cachedSegments
                    sponsorSegments = filtered
                    let sbCacheLabel = isStaleSponsor ? "STALE" : "HIT"
                    playerLog.notice("[sponsorBlock] cache \(sbCacheLabel): \(cachedSegments.count) raw -> \(filtered.count) applied")
                    // Mark as "not fully cached" only when stale so Phase 2 revalidates.
                    sponsorCached = !isStaleSponsor
                } else {
                    playerLog.notice("[sponsorBlock] cache MISS — will fetch in phase2")
                }
                // Full miss or stale: Phase 2 will fetch or revalidate.
            } else {
                playerLog.notice("[sponsorBlock] skipped (disabled or channel excluded)")
                sponsorCached = true  // disabled/excluded — no fetch needed in Phase 2
            }

            // Restore saved watch position (mirrors VideoStateController)
            let savedState = await VideoStateStore.shared.state(for: video.id)
            if let pos = savedState?.position, pos > 5 {
                savedPositionToRestore = pos
                playerLog.notice("Restoring position \(Int(pos))s for \(video.id)")
            }
            // Filter the quality picker to only heights that the HLS manifest actually
            // offers. The iOS player response lists all adaptive CDN formats at every
            // quality, but the HLS variant playlist may omit qualities the CDN has not
            // encoded for this video. Parsing the manifest prevents the user from
            // selecting a quality tier that AVPlayer's ABR would silently ignore.
            // HLS variant fetch is NOT on the critical path: we use the master URL for
            // initial playback, so AVPlayer does not need variant URLs to show the first
            // frame. Fetch in a background Task and update the quality picker when done.
            if let hlsURL = info.hlsURL {
                Task { [weak self] in
                    let variantURLs = await self?.fetchHLSVariantURLs(url: hlsURL) ?? [:]
                    guard let self, !Task.isCancelled, !variantURLs.isEmpty else { return }
                    self.hlsVariantURLs = variantURLs
                    let beforeCount = self.availableFormats.count
                    self.availableFormats = self.availableFormats.filter { variantURLs.keys.contains($0.height) }
                    playerLog.notice("HLS variants (bg): \(variantURLs.keys.sorted().reversed()) — filtered quality picker \(beforeCount) → \(self.availableFormats.count) options")
                    if let sel = self.selectedFormat, !variantURLs.keys.contains(sel.height) { self.selectedFormat = nil }
                }
            }
            // Build player item — preferredStreamURL is guaranteed non-nil here because
            // parsePlayerInfo throws APIError.unavailable when streamingData is absent.
            guard let masterStreamURL = info.preferredStreamURL else {
                // iOS client returned adaptive-only formats (no HLS, no muxed stream).
                // Try adaptive composition first — iOS adaptive streams (c=IOS) may be rqh=0.
                // attemptComposition has a rqh=1 guard and returns false immediately if blocked;
                // in that case (or if AVPlayer 403s) we fall through to exhaustiveRetry.
                if !info.formats.isEmpty {
                    playerLog.notice("⚠️ adaptive-only iOS response — trying adaptive composition (c=IOS may be rqh=0)")
                    if await tryAllStreams(video: video, info: info, label: "iOS", skipMuxed: true) { return }
                    playerLog.notice("⚠️ iOS adaptive composition failed — retrying exhaustively")
                    await exhaustiveRetry(video: video, originalError: nil, playerInfo: info, cached: cached)
                    return
                }
                playerLog.error("❌ No stream URL after successful parse (should not happen)")
                throw APIError.decodingError("No stream URL")
            }
            // When the iOS client has no HLS URL (non-embeddable videos return only muxed
            // 360p), playing masterStreamURL directly would settle for 360p without ever
            // trying AndroidVR adaptive (which works for these videos via visitorData).
            // Route through exhaustiveRetry first; it will try all adaptive paths and fall
            // back to muxed 360p as Phase 2 if all adaptive attempts fail.
            if info.hlsURL == nil {
                playerLog.notice("⚠️ iOS response: no HLS — routing to exhaustiveRetry for adaptive quality before muxed fallback")
                await exhaustiveRetry(video: video, originalError: nil, playerInfo: info, cached: cached)
                return
            }
            // For initial load always use the master HLS manifest so that AVPlayer
            // receives EXT-X-MEDIA alternate audio renditions (dubbed tracks, etc.).
            // Variant playlists omit EXT-X-MEDIA entries, which causes AudioTrackManager
            // to exit early and produce silent audio when a non-auto quality is preferred.
            // Quality is steered via AVPlayerItem hints (preferredMaximumResolution /
            // preferredPeakBitRate) which AVPlayer honours during ABR adaptation.
            let initialStreamURL = masterStreamURL
            // Compute effective quality cap: explicit setting only.
            // Auto quality leaves hints unconstrained (zero) so AVPlayer's ABR can freely
            // select the highest variant the network supports.
            let initialMaxH: Int
            if settings.preferredQuality != .auto, let h = settings.preferredQuality.maxHeight {
                initialMaxH = h
                let matchingFormat = availableFormats.first { $0.height <= h }
                selectedFormat = matchingFormat
                playerLog.notice("Initial quality \(h)p — using master URL with ABR hints")
            } else {
                initialMaxH = 0  // unconstrained — resolved to .zero / 0 below
                playerLog.notice("Initial quality Auto — unconstrained (no resolution/bitrate cap)")
            }
            playerLog.notice("Starting AVPlayer with: \(initialStreamURL.absoluteString.prefix(120))")
            lastAttemptedStreamURL = initialStreamURL
            // HLS manifests are signed by WEB_EMBEDDED_PLAYER (web client) — use browser UA
            // plus Origin + Referer matching the embed context to unlock higher-quality variants.
            // Muxed/adaptive direct URLs are signed by the iOS client — use iOS UA.
            let isHLS = (info.hlsURL != nil && initialStreamURL == info.hlsURL)
            let initialUA = isHLS ? InnerTubeClients.Web.userAgent : InnerTubeClients.iOS.userAgent
            var initialHeaders: [String: String] = ["User-Agent": initialUA]
            if isHLS {
                initialHeaders["Origin"] = "https://www.youtube.com"
                initialHeaders["Referer"] = "https://www.youtube.com/"
            }
            let playerAsset = AVURLAsset(
                url: initialStreamURL,
                options: ["AVURLAssetHTTPHeaderFieldsKey": initialHeaders]
            )
            let item = AVPlayerItem(asset: playerAsset)
            // .spectral gives the highest-quality pitch-preserving time-stretch at
            // non-1× speeds, reducing the tinny/phase artefacts audible on AirPods
            // compared to the default .timeDomain algorithm.
            item.audioTimePitchAlgorithm = .spectral
            // Fast-start: require only 0.5 s of buffered content before the first frame
            // fires (readyToPlay). At 360p / 1.5 Mbps this is ~94 KB — well under a
            // single CDN segment. The forward buffer is reset to system default (0) in
            // the quality ramp task after readyToPlay so scrubbing has enough lookahead.
            item.preferredForwardBufferDuration = 0.5
            // Apply quality hints when a non-auto preference is set. These steer AVPlayer's
            // ABR algorithm toward the user's preferred resolution without bypassing audio
            // metadata (which variant URLs would lose). Hints are applied unconditionally
            // to the master URL for all HLS streams.
            // Apply ABR hints so AVPlayer selects the right variant immediately.
            // Consistent with the quality-switch path in PlaybackQualityManager.
            if info.hlsURL != nil {
                // Fast-start: cap initial ABR at 360p so AVPlayer picks a low-bitrate
                // variant for the first segment → first frame on screen as quickly as
                // possible. After .readyToPlay the hint is upgraded to the user's
                // preferred quality (see itemObserverTask ramp below).
                item.preferredMaximumResolution = CGSize(width: 640, height: 360)
                item.preferredPeakBitRate = peakBitRate(for: 360)
                let target = initialMaxH > 0 ? "\(initialMaxH)p" : "Auto"
                playerLog.notice("[fast-start] initial ABR hint → 360p (preferred target: \(target))")
            }
            // Observe item status using async/await (withCheckedContinuation is not needed
            // here since we only need to react to status changes, not await them).
            // BUG-009 fix: replaceCurrentItem BEFORE wiring the observer to avoid a race
            // where statusStream fires with stale state before the item is installed.
            // This matches the already-correct ordering in all fallback/audio-only paths.
            player.replaceCurrentItem(with: item)
            duration = info.video.duration ?? 0
            itemObserverTask?.cancel()
            itemObserverTask = Task { [weak self] in
                for await status in item.statusStream {
                    guard let self, !Task.isCancelled else { return }
                    switch status {
                    case .readyToPlay:
                        self.itemStartupWatchdogTask?.cancel()
                        self.itemStartupWatchdogTask = nil
                        self.loadDeadlineTask?.cancel()
                        self.loadDeadlineTask = nil
                        let elapsedMs = Int(Date().timeIntervalSince(self.videoLoadStartedAt) * 1000)
                        self.timeToPlayMs = elapsedMs
                        playerLog.notice("✅ AVPlayerItem readyToPlay — video=\(self.currentVideo?.id ?? "nil") rate=\(self.player.rate) timeControlStatus=\(self.player.timeControlStatus.rawValue) isAudioOnlyMode=\(self.isAudioOnlyMode)")
                        playerLog.notice("[benchmark] readyToPlay in \(elapsedMs) ms since load() — videoId=\(self.currentVideo?.id ?? "nil") title=\(self.currentVideo?.title ?? "nil")")
                        // Only set the stream type here if a fallback path hasn't already set it
                        // (fallback paths set it in attemptURL/tryWebViewHLS readyToPlay handlers).
                        if self.lastSuccessfulStreamType == "unknown" {
                            self.lastSuccessfulStreamType = isHLS ? "primaryHLS" : "primaryDirect"
                        }
                        if elapsedMs > 4_000 {
                            CrashlyticsLogger.recordSlowVideoLoad(
                                videoId: self.currentVideo?.id ?? "unknown",
                                elapsedMs: elapsedMs,
                                streamType: self.lastSuccessfulStreamType,
                                hasError: item.error != nil,
                                errorDescription: item.error?.localizedDescription
                            )
                        }
                        // Refresh duration from the AVPlayerItem now that it is
                        // ready — the API metadata may have been absent (nil) or
                        // inaccurate, which would leave duration=0 and break scrubbing
                        // (every seekBar drag computes fraction*0 = 0).
                        let itemDur = item.duration.seconds
                        if itemDur.isFinite && itemDur > 0 {
                            let prevDur = self.duration
                            self.duration = itemDur
                            playerLog.notice("[duration] updated from AVPlayerItem: \(String(format: "%.1f", itemDur))s (was \(String(format: "%.1f", prevDur))s from metadata)")
                        } else if self.duration == 0 {
                            // Some HLS streams report .invalid duration at readyToPlay and
                            // deliver it later via KVO once playlist segments are parsed.
                            // Watch for the first valid value so the scrubber is not
                            // permanently greyed out (#183).
                            self.durationObserverTask?.cancel()
                            self.durationObserverTask = Task { [weak self, weak item] in
                                guard let self, let item else { return }
                                for await seconds in item.firstValidDurationStream {
                                    guard !Task.isCancelled else { return }
                                    let prev = self.duration
                                    self.duration = seconds
                                    playerLog.notice("[duration] deferred KVO update: \(String(format: "%.1f", seconds))s (was \(String(format: "%.1f", prev))s)")
                                    break
                                }
                            }
                        }
                        if let pos = self.savedPositionToRestore, pos > 0 {
                            self.savedPositionToRestore = nil
                            self.seek(to: pos)
                        }
                        // Load alternate audio renditions (dubbed / translated tracks).
                        self.loadAudioTracks(from: item)                        // Dismiss the spinner: the first frame is ready to display.
                        // Previously this was done after player.rate was set, which
                        // dismissed the spinner before buffering completed on slow
                        // networks (GitHub issue #53).
                        self.isLoading = false
                        // Fast-start quality ramp: first frame is visible now. Upgrade
                        // ABR hints to the user's preferred quality so AVPlayer switches
                        // to a higher-quality variant during continued playback. This is
                        // a hint update only — no item replacement, no stutter.
                        if info.hlsURL != nil {
                            let targetMaxH = self.settings.preferredQuality.maxHeight
                            Task { [weak self, weak item] in
                                try? await Task.sleep(for: .milliseconds(800))
                                guard let self, !Task.isCancelled else { return }
                                self.timeToHighQualityMs = Int(Date().timeIntervalSince(self.videoLoadStartedAt) * 1000)
                                // Reset to system default so scrubbing has a comfortable
                                // forward buffer after the first frame is on screen.
                                item?.preferredForwardBufferDuration = 0
                                if let h = targetMaxH {
                                    let hf = CGFloat(h)
                                    item?.preferredMaximumResolution = CGSize(width: hf * 4, height: hf)
                                    item?.preferredPeakBitRate = self.peakBitRate(for: h)
                                    playerLog.notice("[fast-start] ABR ramp → \(h)p + buffer unconstrained")
                                } else {
                                    item?.preferredMaximumResolution = .zero
                                    item?.preferredPeakBitRate = 0
                                    playerLog.notice("[fast-start] ABR ramp → Auto (unconstrained) + buffer unconstrained")
                                }
                            }
                        }
                    case .failed:
                        self.itemStartupWatchdogTask?.cancel()
                        self.itemStartupWatchdogTask = nil
                        let err = item.error.map { "\($0)" } ?? "nil"
                        playerLog.error("❌ AVPlayerItem failed: \(err)")
                        if let video = self.currentVideo {
                            self.exhaustiveRetryTask?.cancel()
                            self.exhaustiveRetryTask = Task { await self.exhaustiveRetry(video: video, originalError: item.error) }
                        } else {
                            self.error = item.error
                        }
                    case .unknown:
                        playerLog.notice("AVPlayerItem status: unknown (loading)")
                    @unknown default:
                        break
                    }
                }
            }
            // iOS 26 may leave an unreachable HLS item in `.unknown` forever instead
            // of reporting `.failed`. Advance to the existing fallback chain after a
            // bounded startup window so the spinner can never wait on this item forever.
            let startupItem = item
            itemStartupWatchdogTask?.cancel()
            itemStartupWatchdogTask = Task { @MainActor [weak self, weak startupItem] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled,
                      let self,
                      let startupItem,
                      self.player.currentItem === startupItem,
                      startupItem.status == .unknown,
                      self.isLoading,
                      self.currentVideo?.id == video.id else { return }
                playerLog.error("❌ AVPlayerItem startup timed out after 12s — routing to exhaustiveRetry")
                self.itemObserverTask?.cancel()
                self.exhaustiveRetryTask?.cancel()
                self.exhaustiveRetryTask = Task {
                    await self.exhaustiveRetry(
                        video: video,
                        originalError: APIError.unavailable("Stream startup timed out")
                    )
                }
            }

            // Observe end-of-item using NotificationCenter async sequence
            endObserverTask?.cancel()
            endObserverTask = Task { [weak self] in
                let notifications = NotificationCenter.default.notifications(
                    named: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item
                )
                for await _ in notifications {
                    guard let self, !Task.isCancelled else { return }
                    self.handlePlaybackEnd()
                }
            }

            // Observe playback stalls and record them as Crashlytics non-fatals (bug #193).
            stallObserverTask?.cancel()
            stallObserverTask = Task { @MainActor [weak self] in
                let notifications = NotificationCenter.default.notifications(
                    named: AVPlayerItem.playbackStalledNotification,
                    object: item
                )
                for await _ in notifications {
                    guard let self, !Task.isCancelled else { return }
                    self.stallCount += 1
                    let t = Int(self.currentTime)
                    playerLog.notice("[stall] AVPlayerItemPlaybackStalled at t=\(t)s stall#\(self.stallCount) video=\(self.currentVideo?.id ?? "unknown")")
                    let stallError = NSError(
                        domain: "SmartTube.PlaybackStall",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "AVPlayerItemPlaybackStalled at t=\(t)s (stall #\(self.stallCount))"]
                    )
                    playerLog.recordNonFatal(stallError, userInfo: [
                        "video_id":       self.currentVideo?.id ?? "unknown",
                        "stall_at_time":  String(t),
                        "stall_count":    String(self.stallCount),
                        "video_duration": String(Int(self.duration)),
                        "stall_trigger":  "AVPlayerItemPlaybackStalled"
                    ])
                    // Stall recovery (#193): wait 2 s for AVPlayer to self-heal;
                    // if still stalled, nudge the pipeline with a near-zero seek
                    // + explicit rate restore. Capped at 3 attempts per item.
                    let recoveryCount = self.stallCount
                    if recoveryCount <= 3 {
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            guard let self, self.isPlaying, self.player.rate == 0,
                                  !self.isQualityChangePending else { return }
                            let seekT = self.currentTime
                            playerLog.notice("[stall] recovery#\(recoveryCount): seeking to \(seekT)s to flush pipeline")
                            self.player.seek(
                                to: CMTime(seconds: seekT, preferredTimescale: 600),
                                toleranceBefore: .zero,
                                toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
                            ) { [weak self] _ in
                                Task { @MainActor [weak self] in
                                    guard let self, self.isPlaying else { return }
                                    self.player.rate = Float(self.settings.playbackSpeed)
                                    playerLog.notice("[stall] recovery#\(recoveryCount): rate restored")
                                }
                            }
                        }
                    }
                }
            }

            // Audio-only mode: if enabled, replace the HLS item with an audio-only asset.
            // Falls back to HLS (already in player) on any failure. No-op when disabled.
            await loadAudioOnlyItemIfEnabled()

            #if canImport(UIKit)
            // Re-register lock screen commands before starting playback.
            // Commands are removed in suspend()/stop(); re-registering here
            // ensures they work when load() is called after a stop().
            setupRemoteCommandCenter()
            // Re-activate the audio session. stop() calls setActive(false) to release
            // the session to other apps; without this call on the next load() the player
            // starts silently because AVFoundation cannot acquire the inactive session.
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                playerLog.notice("[loadAsync] AVAudioSession activated before playback")
            } catch {
                playerLog.error("[loadAsync] AVAudioSession setActive(true) failed: \(error.localizedDescription)")
            }
            #endif
            playerLog.notice("[loadAsync] setting rate=\(self.settings.playbackSpeed) — player.timeControlStatus=\(self.player.timeControlStatus.rawValue) isAudioOnlyMode=\(self.isAudioOnlyMode)")
            player.rate = Float(settings.playbackSpeed)
            isPlaying = true
            playerLog.notice("[loadAsync] rate set — player.rate=\(self.player.rate) timeControlStatus=\(self.player.timeControlStatus.rawValue)")
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            updateNowPlayingInfo()
            #endif
            // Only reschedule the auto-hide timer when controls are already visible.
            // Calling scheduleControlsHide() unconditionally cancels any timer that
            // was started by a user tap during loading, extending the visible window
            // unexpectedly and breaking UI tests that wait for the auto-hide.
            if controlsVisible { scheduleControlsHide() }

            // Phase 2 as a cancellable utility Task. Cancelled on the next load()
            // or stop() so stale network callbacks never write to a new video's state.
            let p2Cached = cached
            let p2Info = info
            let p2CachedTracking = cachedTrackingURLs
            let p2AuthTask = authTrackingTask
            let p2SponsorCached = sponsorCached
            let p2Video = video
            phase2Task = Task(priority: .utility) { [weak self] in
                await self?.loadAsyncPhase2(
                    video: p2Video,
                    cached: p2Cached,
                    info: p2Info,
                    cachedTrackingURLs: p2CachedTracking,
                    authTrackingTask: p2AuthTask,
                    sponsorCached: p2SponsorCached
                )
            }
        } catch {
            isLoading = false
            // Ignore CancellationError — it is expected when stop() or a new load()
            // cancels an in-flight loadTask. Surfacing it would show a spurious error
            // banner on the next video open.
            guard !(error is CancellationError) else { return }
            playerLog.error("❌ loadAsync error: \(String(describing: error))")
            // signInRequired from the primary iOS client can be a false-positive when
            // the user's auth session is broken (Multilogin INVALID_TOKENS): YouTube
            // returns LOGIN_REQUIRED even for public content. Route to exhaustiveRetry
            // so fallback clients (WKWebView, TVEmbedded, WebSafari) can try without
            // the broken auth token. Only applies when signed-in — unsigned users
            // hitting truly age-restricted content get the error immediately.
            // Firebase: 0edf6a2f (AutoDiagnostic(1)) + db9e0581 (APIError(6)).
            //
            // httpError(403) from the authenticated TV client is the same class of failure:
            // a stale/expired auth token causes YouTube to return a raw HTTP 403 (no JSON
            // body) instead of a LOGIN_REQUIRED playabilityStatus. Since signInRequired
            // detection requires a parseable body, these arrive here as httpError(403).
            // Route them to exhaustiveRetry too — unauthenticated fallback clients may
            // succeed without the broken token. Firebase: 5f445659 (APIError(0) HTTP 403).
            let shouldRetryWithFallback: Bool
            if let apiErr = error as? APIError {
                switch apiErr {
                case .signInRequired:
                    shouldRetryWithFallback = hasAuthToken
                case .httpError(403):
                    shouldRetryWithFallback = hasAuthToken
                default:
                    shouldRetryWithFallback = false
                }
            } else {
                shouldRetryWithFallback = false
            }
            if shouldRetryWithFallback {
                playerLog.notice("⚠️ \(error.localizedDescription) from primary client (signed-in user) — routing to exhaustiveRetry for fallback clients")
                exhaustiveRetryTask?.cancel()
                exhaustiveRetryTask = Task { [weak self] in
                    await self?.exhaustiveRetry(video: video, originalError: error)
                }
            } else {
                self.error = error
            }
        }
    }

    // MARK: - Cleanup

    public func stop() {
        playerLog.notice("[stop] stop() called — currentVideo=\(self.currentVideo?.id ?? "nil") currentTime=\(Int(self.currentTime))s isLoading=\(self.isLoading)")
        // Save watch position before stopping (mirrors VideoStateController)
        if settings.historyState == .enabled, duration > 0 {
            let pos = self.currentTime
            let dur = self.duration
            Task {
                await self.tracker.checkpoint(position: pos, duration: dur)
                playerLog.notice("Saved position \(Int(pos))s for stop")
            }
        }
        player.pause()
        // fix12: Do NOT call player.replaceCurrentItem(with: nil) — keep the AVPlayerItem
        // alive so load() can detect and reuse it if the same video is re-opened within
        // a short window. Saves the ~1.27s exhaustiveRetry race for hot same-video replays.
        // load() calls replaceCurrentItem(nil) when a different video is requested.
        parkedVideoId = currentVideo?.id
        isPlaying = false
        #if canImport(UIKit)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            playerLog.error("AVAudioSession deactivation failed: \(error.localizedDescription)")
        }
        #endif
        loadTask?.cancel()
        loadTask = nil
        // fix235: Cancel any in-flight exhaustiveRetry so it cannot call replaceCurrentItem
        // with a stale video after stop() returns. stop() does not spawn a new load so
        // exhaustiveRetryTask is left dangling otherwise.
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        // Reset isLoading immediately so a same-video re-open via play() does not hit
        // the early-return guard in load() before the cancelled task cleans up.
        isLoading = false
        phase2Task?.cancel()
        phase2Task = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        AVAssetTrackCache.shared.clear()
        // Evict the cached WKWebView HLS URL for the video that just stopped.
        // CDN stream sessions are single-use: re-using the same manifest URL with a
        // new AVPlayerItem on a subsequent tap resumes from the previous position or
        // serves recycled session content, which the user sees as a wrong / different
        // video for ~1s before the 403 fires. Evicting here forces a fresh extraction
        // on re-tap while still allowing neighbour pre-warms to populate the cache.
        //
        // fix10: after evicting the stale CDN URL, start a fresh wkHLS extraction via
        // serialExtract. When extraction completes (~1.25s), the URL is stored in cache
        // so Phase -1a finds it on the next load() for this video (bypassing the full
        // exhaustiveRetry race entirely → ~0.5s faster). The task is also assigned to
        // wkHLSEarlyTask so racePathB can use it if the re-tap happens before extraction
        // completes (< 1.25s after stop).
        if let stoppedVideoId = currentVideo?.id {
            Task { await VideoPreloadCache.shared.invalidateWKHLSURL(for: stoppedVideoId) }
            #if canImport(WebKit)
            wkHLSEarlyTaskVideoId = stoppedVideoId
            let capturedId = stoppedVideoId
            wkHLSEarlyTask = Task { @MainActor in
                guard let url = await YouTubeWebViewHLSExtractor.shared.serialExtract(videoId: capturedId) else { return nil }
                // Defense-in-depth: if load() for a different video cancelled this task
                // between serialExtract's return and the store, bail rather than write
                // a potentially stale URL into the cache under the wrong key.
                guard !Task.isCancelled else {
                    playerLog.notice("[fix10] pre-warm task was cancelled — not caching URL for \(capturedId)")
                    return nil
                }
                // Store the fresh URL so Phase -1a serves from cache on re-tap.
                await VideoPreloadCache.shared.store(wkHLSManifestURL: url, for: capturedId)
                playerLog.notice("[fix10] wkHLS pre-warm complete — cached for \(capturedId)")
                return url
            }
            #endif
        }
        itemObserverTask?.cancel()
        itemObserverTask = nil
        itemStartupWatchdogTask?.cancel()
        itemStartupWatchdogTask = nil
        loadDeadlineTask?.cancel()
        loadDeadlineTask = nil
        endObserverTask?.cancel()
        endObserverTask = nil
        stallObserverTask?.cancel()
        stallObserverTask = nil
        durationObserverTask?.cancel()
        durationObserverTask = nil
        // Defense-in-depth, same reasoning as suspend(): a live rateObserver's KVO
        // closure can independently spawn a new exhaustiveRetryTask after this
        // function returns. stop()'s synchronous pause()/isPlaying=false ordering
        // happens to make that unreachable today, but invalidating here removes the
        // dependency on that ordering. Re-established defensively in loadAsync().
        rateObserver?.invalidate()
        rateObserver = nil
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        clearNowPlayingInfo()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        #endif
        if let obs = audioSessionObserver {
            NotificationCenter.default.removeObserver(obs)
            audioSessionObserver = nil
        }
    }

    // MARK: - Phase 2: Background enrichment

    /// Runs concurrently with playback after Phase 1 completes.
    /// Fetches data that is not needed to start AVPlayer: related videos, end cards,
    /// SponsorBlock segments (cache miss only), tracking URLs, and neighbour prefetch.
    /// All property assignments happen on @MainActor because PlaybackViewModel is @MainActor.
    func loadAsyncPhase2(
        video: Video,
        cached: CachedVideoData,
        info: PlayerInfo,
        cachedTrackingURLs: PlaybackTrackingURLs?,
        authTrackingTask: Task<PlaybackTrackingURLs?, Never>?,
        sponsorCached: Bool
    ) async {
        guard !Task.isCancelled else { return }

        // --- SponsorBlock cache miss or stale ---
        if !sponsorCached, settings.sponsorBlockEnabled {
            let channelIsExcluded = video.channelId.map {
                settings.sponsorBlockExcludedChannels.keys.contains($0)
            } ?? false
            if !channelIsExcluded {
                let videoId = video.id
                let cats = settings.activeSponsorCategories
                let minDur = settings.sponsorBlockMinSegmentDuration
                if cached.staleFields.contains(.sponsorSegments) {
                    // Stale data was already applied in Phase 1 — revalidate silently.
                    Task(priority: .background) { [weak self] in
                        guard let self else { return }
                        let segments = await self.sponsorBlock.fetchSegments(videoId: videoId, categories: cats)
                        await VideoPreloadCache.shared.store(sponsorSegments: segments, for: videoId)
                    }
                } else {
                    // Full miss — fetch now and apply.
                    var segments = await sponsorBlock.fetchSegments(videoId: videoId, categories: cats)
                    await VideoPreloadCache.shared.store(sponsorSegments: segments, for: videoId)
                    guard !Task.isCancelled else { return }
                    if minDur > 0 { segments = segments.filter { ($0.end - $0.start) >= minDur } }
                    sponsorSegments = segments
                    playerLog.notice("[sponsorBlock] phase2 applied \(segments.count) segments for \(videoId)")
                }
            }
        }

        guard !Task.isCancelled else { return }

        // --- Related videos + like status ---
        // UI testing inject: bypass all network fetches for related videos.
        // Used by testPlayerSwipeRightWorksWhenControlsAreVisible which runs on
        // clone simulators that may lack network access for playerInfo.
        if let relArg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--uitesting-inject-related-video-ids=")
        }) {
            let raw = String(relArg.dropFirst("--uitesting-inject-related-video-ids=".count))
            let ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            if !ids.isEmpty {
                relatedVideos = ids.map { Video(id: $0, title: $0, channelTitle: "Test Channel") }
                hasNext = true
                playerLog.notice("UI-testing inject: set \(ids.count) related videos synchronously")
                // fall through to remainder of loading (chapters, endCards, etc.)
            }
        } else {

        // Fresh cache hit: use immediately (no network).
        // Stale cache hit: stale data was already returned by consume() — revalidate silently in background.
        // Full miss: live blocking fetch so relatedVideos is populated before the panel opens.
        let nextInfo: NextInfo?
        if let cachedNext = cached.nextInfo, !cached.staleFields.contains(.nextInfo) {
            playerLog.notice("cache HIT: nextInfo chapters=\(cachedNext.chapters.count) (skipping network)")
            nextInfo = cachedNext
        } else if let staleNext = cached.nextInfo, cached.staleFields.contains(.nextInfo) {
            playerLog.notice("SWR: nextInfo stale chapters=\(staleNext.chapters.count) — using cached, revalidating in background")
            nextInfo = staleNext
            let videoId = video.id
            Task(priority: .background) { [api = self.api] in
                if let fresh = try? await api.fetchNextInfo(videoId: videoId) {
                    await VideoPreloadCache.shared.store(nextInfo: fresh, for: videoId)
                }
            }
        } else {
            nextInfo = try? await api.fetchNextInfo(videoId: video.id)
            if let nextInfo { await VideoPreloadCache.shared.store(nextInfo: nextInfo, for: video.id) }
        }

        guard !Task.isCancelled else { return }

        if let nextInfo, !nextInfo.relatedVideos.isEmpty {
            relatedVideos = nextInfo.relatedVideos.filter { $0.id != video.id }
            hasNext = !relatedVideos.isEmpty
        } else {
            let fallbackQuery = video.title.isEmpty ? nil : video.title
            if let query = fallbackQuery {
                let searched = try? await api.search(query: query)
                relatedVideos = searched?.videos.filter { $0.id != video.id }.prefix(InnerTubeClients.maxVideoResults).map { $0 } ?? []
                hasNext = !relatedVideos.isEmpty
            }
        }
        // If the related-videos fetch resolved hasNext=false but this is a queue
        // video that still has a subsequent item, restore hasNext=true so the
        // next button stays enabled for queue playback.
        if !hasNext,
           video.playlistId == CurrentQueueStore.playlistID,
           let idx = video.playlistIndex {
            hasNext = await CurrentQueueStore.shared.videoAt(index: idx + 1) != nil
        }
        if let status = nextInfo?.likeStatus { likeDislike.setLikeStatus(status) }
        if let ch = nextInfo?.chapters, !ch.isEmpty {
            chapters = ch
            playerLog.notice("[chapters] applied \(ch.count) chapters for \(video.id)")
        } else {
            playerLog.notice("[chapters] none for \(video.id) (nextInfo chapters=\(nextInfo?.chapters.count ?? -1))")
        }

        // hasNext is now fully resolved (related videos + queue fallback). Update the
        // lock-screen now-playing info so nextTrackCommand.isEnabled reflects the real
        // state. Without this call the next/prev buttons only appear if hasNext was
        // already true during phase-1 (playlist videos); for home-feed autoplay the
        // buttons are permanently missing.
        #if canImport(UIKit)
        updateNowPlayingInfo()
        #endif

        } // end of non-inject related-videos branch

        guard !Task.isCancelled else { return }

        // Launch WKWebView pre-extraction as soon as relatedVideos is populated.
        // Starting here (before endCards/trackingURLs) gives ~0.6–3 s more lead
        // time for the warm extraction to complete before the user swipes.
        #if canImport(WebKit)
        if let firstNeighbour = relatedVideos.first?.id {
            Task(priority: .background) { [weak self] in
                await self?.preExtractWKHLSForVideo(firstNeighbour)
            }
        }
        #endif

        // --- End cards ---
        if let cachedCards = cached.endCards, !cached.staleFields.contains(.endCards) {
            playerLog.notice("cache HIT: endCards (skipping network)")
            endCards = cachedCards
        } else if let staleCards = cached.endCards, cached.staleFields.contains(.endCards) {
            playerLog.notice("SWR: endCards stale — using cached, revalidating in background")
            endCards = staleCards
            let videoId = video.id
            Task(priority: .background) { [api = self.api] in
                if let fresh = try? await api.fetchEndCards(videoId: videoId) {
                    await VideoPreloadCache.shared.store(endCards: fresh, for: videoId)
                }
            }
        } else if !info.endCards.isEmpty {
            endCards = info.endCards
            playerLog.notice("endCards: \(info.endCards.count) from primary response")
            await VideoPreloadCache.shared.store(endCards: info.endCards, for: video.id)
        } else {
            do {
                let webCards = try await api.fetchEndCards(videoId: video.id)
                guard !Task.isCancelled else { return }
                endCards = webCards
                playerLog.notice("endCards: \(webCards.count) from web client fallback")
                await VideoPreloadCache.shared.store(endCards: webCards, for: video.id)
            } catch {
                playerLog.error("endCards fetch failed: \(error.localizedDescription)")
                endCards = []
            }
        }

        guard !Task.isCancelled else { return }

        // --- Tracking URLs ---
        let resolvedTrackingURLs: PlaybackTrackingURLs?
        if let cachedTracking = cachedTrackingURLs {
            resolvedTrackingURLs = cachedTracking
            playerLog.notice("cache HIT: trackingURLs")
        } else {
            resolvedTrackingURLs = await authTrackingTask?.value ?? info.trackingURLs
            await VideoPreloadCache.shared.store(trackingURLs: resolvedTrackingURLs, for: video.id)
        }
        guard !Task.isCancelled else { return }
        tracker.setTrackingURLs(resolvedTrackingURLs)
        playerLog.notice("activeTrackingURLs resolved: \(resolvedTrackingURLs != nil ? "account-bound" : "none")")

        // BUG-015 fix: read currentAuthToken per-prefetch-call so a token refresh mid-loop
        // uses the fresh token rather than a stale snapshot captured before the loop starts.
        let neighbourIds = Array(relatedVideos.prefix(3).map(\.id))
        let sponsorCats = settings.activeSponsorCategories
        playerLog.notice("[prefetch] scheduling \(neighbourIds.count) neighbours")
        Task(priority: .background) { [weak self] in
            for videoId in neighbourIds {
                let token = await MainActor.run { self?.currentAuthToken }
                await VideoPreloadCache.shared.prefetch(
                    videoId: videoId,
                    sponsorCategories: sponsorCats,
                    authToken: token,
                    priority: .speculative
                )
            }
        }

    }
}
