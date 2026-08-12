import Foundation
import AVFoundation
import Observation
import os
#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif
import SmartTubeIOSCore

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - PlaybackViewModel
//
// Manages video playback state and the AVPlayer instance.
// Mirrors the Android `PlaybackPresenter` + `PlayerUIController`.

@MainActor
@Observable
public final class PlaybackViewModel {

    // MARK: - Sub-module managers
    // Each manager owns a subset of playback state and exposes a narrow interface.
    // PlaybackViewModel is the coordinator that injects dependencies and forwards calls.

    let sponsorBlockManager: SponsorBlockSkipManager
    let captionsManager: CaptionsManager
    let audioManager: AudioTrackManager
    let qualityManager: PlaybackQualityManager

    // MARK: - State

    public internal(set) var playerInfo: PlayerInfo?
    public internal(set) var isLoading: Bool = false {
        didSet { if !isLoading { retryStatusMessage = nil } }
    }
    /// Short user-facing message shown under the loading spinner when the player
    /// enters the multi-phase stream-negotiation fallback chain. `nil` while the
    /// fast path is still in-flight or after loading completes.
    public internal(set) var retryStatusMessage: String? = nil
    /// Populated by `probeStreamMethod` after a successful single-method probe.
    /// Format: `"HLS 1080p"`, `"1080p"`, `"1080p rqh=1"`, `"muxed 720p"`, `"WKWebView-HLS"`, etc.
    /// `nil` in normal (non-probe) playback. Read by `player.probeStreamResult` accessibility element.
    var probeStreamResult: String? = nil
    /// True only during the initial load sequence (before first readyToPlay).
    /// The 8s loadTracks timeout in attemptComposition is applied only while this
    /// flag is set, giving fast startup (≤20 s) for the initial stream.
    /// After first playback begins the flag is cleared, so quality-switch
    /// reloads can wait the full CDN time without being cut short.
    var needsQuickStartup: Bool = false
    /// Timestamp set at the start of `load(video:)` — used to log total video-start latency.
    var videoLoadStartedAt: Date = .distantPast
    /// Video ID (and title) that `load(video:)` was last called with. Compared against
    /// `currentVideo.id` when `isPlaying` fires for the first time in each load cycle
    /// to detect a wrong-video outcome (fix236).
    var intendedVideoId: String? = nil
    var intendedVideoTitle: String? = nil
    /// Set to `true` at the start of each `load()` and cleared on the first
    /// `isPlaying = true` of that load cycle so the check fires exactly once.
    var pendingWrongVideoCheck: Bool = false
    public internal(set) var isPlaying: Bool = false {
        didSet {
            guard isPlaying, !oldValue else { return }
            // fix13: Cross-process Darwin notification for regression-test timing.
            // XCTDarwinNotificationExpectation in WKHLSReplayRegressionUITests receives
            // this within ~1 ms when readyToPlay fires, bypassing XCTest's ~1.2 s UIKit
            // modal accessibility-settle delay so hot cycles measure ~0.84 s (readyToPlay
            // time) instead of ~1.6 s (accessibility overhead).
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.player.ready" as CFString),
                nil, nil, true
            )
            checkWrongVideoOnFirstPlay()
        }
    }
    public internal(set) var videoEnded: Bool = false
    public internal(set) var currentTime: TimeInterval = 0
    public internal(set) var duration: TimeInterval = 0

    // MARK: - Forwarding computed properties (views unchanged)

    public internal(set) var availableFormats: [VideoFormat] {
        get { qualityManager.availableFormats }
        set { qualityManager.availableFormats = newValue }
    }
    public internal(set) var selectedFormat: VideoFormat? {
        get { qualityManager.selectedFormat }
        set { qualityManager.selectedFormat = newValue }
    }

    /// The quality label last chosen by the user — persists even after CDN failure
    /// clears `selectedFormat`. Use this for UI labels that should show user intent.
    public var pendingQualityLabel: String {
        qualityManager.pendingQualityLabel
    }
    public internal(set) var sponsorSegments: [SponsorSegment] {
        get { sponsorBlockManager.sponsorSegments }
        set { sponsorBlockManager.sponsorSegments = newValue }
    }
    public internal(set) var currentToastSegment: SponsorSegment? {
        get { sponsorBlockManager.currentToastSegment }
        set { sponsorBlockManager.currentToastSegment = newValue }
    }
    public internal(set) var availableCaptions: [CaptionTrack] {
        get { captionsManager.availableCaptions }
        set { captionsManager.availableCaptions = newValue }
    }
    public internal(set) var selectedCaption: CaptionTrack? {
        get { captionsManager.selectedCaption }
        set { captionsManager.selectedCaption = newValue }
    }
    public internal(set) var currentCaptionCue: CaptionCue? {
        get { captionsManager.currentCaptionCue }
        set { captionsManager.currentCaptionCue = newValue }
    }
    public internal(set) var availableAudioTracks: [AudioTrack] {
        get { audioManager.availableAudioTracks }
        set { audioManager.availableAudioTracks = newValue }
    }
    public internal(set) var selectedAudioTrack: AudioTrack? {
        get { audioManager.selectedAudioTrack }
        set { audioManager.selectedAudioTrack = newValue }
    }
    /// Short message displayed by `ToastModifier` in the player; cleared automatically after 2 s.
    public var toastMessage: String? = nil
    public internal(set) var relatedVideos: [Video] = []
    public internal(set) var chapters: [Chapter] = []
    public internal(set) var hasPrevious: Bool = false
    public internal(set) var hasNext: Bool = false
    /// The last stream URL handed to AVPlayer (primary or fallback). Stamped onto
    /// Crashlytics non-fatal reports so the exact URL that failed is visible.
    var lastAttemptedStreamURL: URL?
    public var error: Error? {
        didSet {
            guard let error else { return }
            let nsError = error as NSError
            // Transient connectivity errors are expected in poor-network conditions and are
            // not actionable via Crashlytics. Logging them caused a spike in non-fatal events
            // in v2.0 — skip them.
            //   -1    = unknown (generic network failure, same signal as below)
            //   -999  = request cancelled (AVPlayer or URLSession cancelled in-flight
            //           request — user navigated away or a superseded task was cancelled)
            //   -1001 = request timed out (slow server or poor connectivity)
            //   -1005 = network connection lost
            //   -1009 = device offline
            //   -1202 = invalid/untrusted certificate (SSL inspection proxy, user-side issue)
            let transientCodes = [-1, -999, -1001, -1005, -1009, -1202]
            guard !(nsError.domain == NSURLErrorDomain && transientCodes.contains(nsError.code)) else {
                return
            }
            // APIError.unavailable means YouTube's server returned a known-unplayable status
            // (bot-detection, rate-limit, private/members-only, region block, cipher-protected
            // URLs). These are never app bugs — log at notice level but don't inflate the
            // Crashlytics non-fatal list. Pattern-match directly on the type rather than
            // relying on NSError.code (which shifts when enum cases are reordered).
            // APIError.ipBlocked is handled with a dedicated non-fatal in the loading path
            // (vpn_ip_block=true) — skip double-logging here.
            if let apiError = error as? APIError {
                if case .unavailable = apiError { return }
                if case .ipBlocked = apiError { return }
            }
            playerLog.recordNonFatal(error, userInfo: [
                "video_id":          currentVideo?.id    ?? "unknown",
                "video_title":       currentVideo?.title ?? "unknown",
                "stream_url":        lastAttemptedStreamURL?.absoluteString ?? "none",
                "error_message":     error.localizedDescription,
                "error_domain":      nsError.domain,
                "error_code":        "\(nsError.code)",
                "retry_attempts":    "\(retryAttempts)",
                "current_time":      "\(Int(currentTime))s",
            ])
            CrashlyticsLogger.sendAutoPlaybackDiagnostic()
        }
    }
    public var controlsVisible: Bool = false
    /// True while the user is holding a long-press to temporarily boost speed to 2×.
    public internal(set) var isHoldingToSpeed: Bool = false
    /// True when the player is displaying in landscape orientation.
    /// Updated automatically when the device rotates or when the
    /// "Landscape Always Play" setting forces landscape mode.
    public var isLandscape: Bool = false
    let likeDislike: LikeDislikeController
    let comments: CommentsController
    public var likeStatus: LikeStatus { likeDislike.likeStatus }
    public func like() { likeDislike.like(videoId: currentVideo?.id) }
    public func dislike() { likeDislike.dislike(videoId: currentVideo?.id) }
    public internal(set) var statsForNerdsVisible: Bool = false
    public internal(set) var statsSnapshot: StatsForNerdsSnapshot = .empty
    /// End-screen cards to overlay during the final seconds of the video.
    public internal(set) var endCards: [EndCard] = []
    /// When `true`, the player loads only the audio-only adaptive stream and displays
    /// the video thumbnail in place of the player layer. Updated from `AppSettings.audioOnlyMode`.
    public var isAudioOnlyMode: Bool = false
    /// `true` when an actual audio-only AVPlayerItem (not HLS) is the current item.
    /// Used by `toggleAudioOnlyLive` to decide whether to reload HLS on turn-off.
    var audioOnlyItemActive: Bool = false

    // MARK: - Captions (forwarded to CaptionsManager)
    // MARK: - Audio tracks (forwarded to AudioTrackManager)

    /// True while the user is dragging the progress slider.
    /// The time observer skips `currentTime` updates while this is set so the
    /// slider thumb doesn't jump back to the real playhead mid-scrub.
    public internal(set) var isScrubbing: Bool = false
    /// True if playback was active when `suspend()` was last called.
    /// Used by `PlayerView.onAppear` to decide whether to resume after a
    /// sheet dismissal — prevents overriding an intentional user pause.
    public internal(set) var wasPlayingBeforeSuspend: Bool = false
    /// Position tracked during a scrub drag; committed to AVPlayer on release.
    public internal(set) var scrubTime: TimeInterval = 0

    /// The chapter whose start time is closest-but-not-greater-than `currentTime`.
    /// Nil when no chapters are available or the video hasn't started.
    public var currentChapter: Chapter? {
        guard !chapters.isEmpty else { return nil }
        return chapters.last(where: { $0.startTime <= currentTime })
    }

    /// True when there is a chapter ahead of the current playhead position.
    public var hasNextChapter: Bool {
        chapters.contains { $0.startTime > currentTime }
    }

    /// True when the playhead can be moved backward to a chapter boundary —
    /// either to the start of the current chapter (if >3 s in) or to the previous one.
    public var hasPreviousChapter: Bool {
        guard let current = currentChapter else { return false }
        if currentTime - current.startTime > 3 { return true }
        return chapters.contains { $0.startTime < current.startTime }
    }

    /// True when at least one VIDEO end card is within its display window at the current playhead.
    /// Used by `PlayerView` to suppress swipe-overlay tap-to-toggle-controls so taps land on cards.
    public var hasVisibleEndCards: Bool {
        let ms = Int(currentTime * 1000)
        return endCards.contains { $0.style == .video && $0.videoId != nil && ms >= $0.startMs && ms <= $0.endMs }
    }

    // MARK: - History

    /// Videos played before the current one (oldest first).
    var history: [Video] = []
    /// The video currently loaded (nil before first load).
    var currentVideo: Video? = nil

    // MARK: - AVPlayer

    public let player = AVPlayer()
    @ObservationIgnored nonisolated(unsafe) var timeObserver: Any?
    @ObservationIgnored nonisolated(unsafe) var audioSessionObserver: Any?
    @ObservationIgnored nonisolated(unsafe) var rateObserver: NSKeyValueObservation?
    /// True while the video is being routed to an external display via AirPlay.
    public internal(set) var isAirPlaying: Bool = false
    @ObservationIgnored nonisolated(unsafe) var airPlayObserver: NSKeyValueObservation?
    /// Counts exhaustive retry cycles (0 = no retry yet). Set by exhaustiveRetry(video:originalError:).
    var retryAttempts: Int = 0
    /// The stream type that produced the current AVPlayerItem, set by each successful load path.
    /// Used by the slow-load Crashlytics event to identify which fallback path was used.
    var lastSuccessfulStreamType: String = "unknown"
    /// Elapsed ms from `load()` to the first `readyToPlay` (low-quality fast-start frame). 0 = not yet measured.
    var timeToPlayMs: Int = 0
    /// Elapsed ms from `load()` to the quality-ramp task firing (~readyToPlay + 800 ms). 0 = not yet measured.
    var timeToHighQualityMs: Int = 0
    /// Cache hit/miss summary set at load time (e.g. "pi:HIT wkHLS:MISS").
    var cacheStatusSummary: String = ""
    /// Task running the exhaustive retry loop; cancelled on new load or retryLoad.
    var exhaustiveRetryTask: Task<Void, Never>?
    /// Set after a Cannot-Decode failure on the Auto HLS master — forwarded to qualityManager.
    var hasAppliedH264Cap: Bool {
        get { qualityManager.hasAppliedH264Cap }
        set { qualityManager.hasAppliedH264Cap = newValue }
    }
    /// True while a SponsorBlock auto-skip seek is in-flight — forwarded to sponsorBlockManager.
    var isSkippingSegment: Bool { sponsorBlockManager.isSkippingSegment }
    var itemObserverTask: Task<Void, Never>?
    /// Cancels an AVPlayerItem attempt that remains `.unknown` indefinitely. YouTube
    /// CDN failures do not always transition AVFoundation to `.failed` on iOS 26.
    var itemStartupWatchdogTask: Task<Void, Never>?
    /// Bounds the complete native loading/fallback pipeline. Individual AVPlayerItem
    /// attempts are timed out separately, but a sequence of bad CDN URLs must not leave
    /// the player spinner visible indefinitely.
    var loadDeadlineTask: Task<Void, Never>?
    var endObserverTask: Task<Void, Never>?
    var stallObserverTask: Task<Void, Never>?
    /// Observes `AVPlayerItem.duration` via KVO after `.readyToPlay` for HLS streams
    /// where the duration is `.invalid` at ready-time and arrives later. Cancelled in `stop()`.
    var durationObserverTask: Task<Void, Never>?
    /// Number of `AVPlayerItemPlaybackStalled` (or rateObserver rate→0) events in this session.
    var stallCount: Int = 0
    /// Wall-clock time of the first stall in the current sequence. Used by rateObserver to
    /// detect a rapid-repeat stall loop (≥3 stalls in <30s) where seeks re-stall immediately
    /// because the CDN URL is expired/rate-limited. Reset to nil alongside stallCount in load().
    var firstRapidStallTime: Date? = nil
    var qualityTask: Task<Void, Never>? {
        get { qualityManager.qualityTask }
        set { qualityManager.qualityTask = newValue }
    }
    #if canImport(WebKit)
    /// Forwarded from qualityManager; keeps YTHLSProxyLoader alive during WebView-HLS playback.
    var webHLSProxyLoader: YTHLSProxyLoader? {
        get { qualityManager.webHLSProxyLoader }
        set { qualityManager.webHLSProxyLoader = newValue }
    }
    /// The master manifest URL obtained via WKWebView HLS extraction. Non-nil only when the
    /// video is playing via the WKWebView path; used to route quality switches correctly.
    var wkHLSMasterURL: URL? {
        get { qualityManager.wkHLSMasterURL }
        set { qualityManager.wkHLSMasterURL = newValue }
    }
    #endif
    /// True while `replaceCurrentItem` is executing; guards the rate observer from
    /// treating the transient rate-drop as an unexpected external pause.
    var isSwappingItem: Bool = false
    /// True while an AVAudioSession interruption (e.g. an incoming phone call) is in
    /// progress. Suppresses the rate-observer's stall detection/recovery so a
    /// deliberate interruption-pause isn't mistaken for a playback stall (#244).
    var isHandlingAudioInterruption: Bool = false
    /// Captures `isPlaying` at the start of an audio interruption so playback can be
    /// resumed on `.ended` only if it was actually playing before the call (#244).
    var wasPlayingBeforeInterruption: Bool = false
    #if canImport(WebKit)
    /// Set to true when BotGuardWebViewRunner successfully produces a minted (non-websafe-fallback)
    /// PO token for the current video. Allows the inner rqh=1 guard in attemptComposition to
    /// proceed — the CDN accepts minted tokens from the full getMinter() path.
    var hasMintedPoToken: Bool = false
    #endif
    /// True from when a quality-change replaceCurrentItem fires until readyToPlay is
    /// handled. The time observer skips currentTime updates during this window so the
    /// UI position is preserved and any user seek during transition is not lost.
    var isQualityChangePending: Bool = false
    var hlsVariantURLs: [Int: URL] {
        get { qualityManager.hlsVariantURLs }
        set { qualityManager.hlsVariantURLs = newValue }
    }
    var controlsTimer: Task<Void, Never>?
    let sleepTimer = SleepTimerController()
    /// Remaining minutes on the sleep timer (nil = off). Observable so PlayerView can show it.
    public var sleepTimerMinutes: Int? { sleepTimer.sleepTimerMinutes }
    public func setSleepTimer(minutes: Int?) {
        sleepTimer.setSleepTimer(minutes: minutes) { [weak self] in
            self?.player.pause()
            self?.isPlaying = false
        }
    }
    /// Available sleep timer durations in minutes.
    public static let sleepTimerOptions: [Int] = [15, 30, 45, 60]
    /// Position to seek to once the AVPlayerItem is ready.
    var savedPositionToRestore: TimeInterval? = nil
    /// Manages watch-history state: position saving, playback-started ping,
    /// and watchtime segment reporting. See WatchtimeTracker.
    var tracker: WatchtimeTracker

    // AVMediaSelectionGroup (forwarded to AudioTrackManager)
    @ObservationIgnored nonisolated var audioSelectionGroup: AVMediaSelectionGroup? {
        get { audioManager.audioSelectionGroup }
        set { audioManager.audioSelectionGroup = newValue }
    }
    @ObservationIgnored var audioOptionsByID: [String: AVMediaSelectionOption] {
        get { audioManager.audioOptionsByID }
        set { audioManager.audioOptionsByID = newValue }
    }

    // Caption cues (forwarded to CaptionsManager)
    var captionCues: [CaptionCue] {
        get { captionsManager.captionCues }
        set { captionsManager.captionCues = newValue }
    }
    @ObservationIgnored var captionFetchTask: Task<Void, Never>? {
        get { captionsManager.captionFetchTask }
        set { captionsManager.captionFetchTask = newValue }
    }
    /// Timestamp of the last commitScrub(). Used to ignore the spurious
    /// beginScrubbing() that SwiftUI's Slider fires immediately after commitScrub
    /// causes a binding re-evaluation and the slider thumb re-positions itself.
    var lastCommitScrubTime: Date = .distantPast
    /// Debounce task for preview seeks while dragging the slider.
    /// Fires a seek after the thumb has been held still for 300 ms.
    var seekDebounceTask: Task<Void, Never>?
    /// Tracks the in-flight loadAsync so it can be cancelled if load() is called again.
    var loadTask: Task<Void, Never>?
    /// Phase 2 background work: nextInfo, endCards, trackingURLs, neighbour prefetch.
    /// Cancelled at the start of every new load() and in stop().
    var phase2Task: Task<Void, Never>?
    /// Background prefetch task: either fetches AndroidVR playerInfo (muxed fallback)
    /// or pre-warms AVAssetTrack arrays for the user's preferred quality tier.
    /// Cancelled on every new video load.
    var prefetchTask: Task<Void, Never>?
    /// Early WKWebView HLS extraction task, started concurrently with the primary iOS
    /// path in loadAsync() so the result is ready (or close to ready) by the time
    /// exhaustiveRetry reaches Phase -2. Cancelled by load() only when a different
    /// video is requested; preserved across stop() so same-video replay can reuse it.
    #if canImport(WebKit)
    var wkHLSEarlyTask: Task<URL?, Never>?
    /// The videoId for which `wkHLSEarlyTask` was last started.
    /// Allows load() to skip cancellation when the same video is re-tapped after stop().
    var wkHLSEarlyTaskVideoId: String?
    #endif
    /// fix2/fix30: TVEmbedded PlayerInfo pre-fetch started concurrently with the race paths.
    /// On tvOS: started inside tryAllStreams alongside the AndroidVR rqh=1 timeout (fix2).
    /// On iOS: started at the beginning of exhaustiveRetry alongside the race group (fix30).
    /// By the time exhaustiveRetry reaches Phase 1, the result is typically ready —
    /// eliminating the sequential ~0.5 s Phase 1 network fetch.
    var tvEmbeddedEarlyTask: Task<PlayerInfo?, Never>?

    /// Set to `true` when WKWebView HLS fails with a CDN permission error (HTTP 403 /
    /// "You do not have permission"). Cleared by load(). When set, serial WKWebView
    /// extraction is skipped in exhaustiveRetry — a fresh extraction yields the same
    /// URL signed by the same CDN session, so the same 403 is guaranteed.
    var wkHLSPermissionDenied: Bool = false

    // fix12: videoId of the item stop() left alive in player.currentItem (parked).
    // When load() is called for the same id and the item is still .readyToPlay, the
    // entire exhaustiveRetry race (~1.27s) is skipped — audio session re-activated and
    // playback resumes in <0.1s. Cleared when a different video is requested.
    var parkedVideoId: String?

    // MARK: - Now Playing cache
    // Never read nowPlayingInfo back from MPNowPlayingInfoCenter — doing a
    // read-modify-write while MediaPlayer is processing on its accessQueue
    // causes EXC_BREAKPOINT. Mirror the dict locally instead.
    @ObservationIgnored var nowPlayingInfoCache: [String: Any] = [:]
    // Cached thumbnail for MPMediaItemArtwork. Written from a background URLSession task;
    // read from MediaPlayer's internal artwork-closure thread. nonisolated(unsafe) is
    // intentional: UIImage is immutable after creation and the worst-case race is that
    // MediaPlayer gets nil on the first render (it will retry on the next state update).
    #if canImport(UIKit)
    nonisolated(unsafe) var cachedArtwork: UIImage? = nil
    @ObservationIgnored var cachedArtworkVideoID: String? = nil
    #endif

    // MARK: - Dependencies

    let api: InnerTubeAPI
    let sponsorBlock: SponsorBlockService
    let deArrow: DeArrowService
    public var settings: AppSettings
    var hasAuthToken: Bool = false
    var currentAuthToken: String? = nil

    public init(
        api: InnerTubeAPI = InnerTubeAPI(),
        sponsorBlock: SponsorBlockService = SponsorBlockService(),
        deArrow: DeArrowService = DeArrowService(),
        settings: AppSettings = AppSettings()
    ) {
        self.api = api
        self.tracker = WatchtimeTracker(api: api)
        self.sponsorBlock = sponsorBlock
        self.deArrow = deArrow
        self.settings = settings

        // Create managers before any other setup (they hold no back-references yet).
        let sbm = SponsorBlockSkipManager()
        let cam = CaptionsManager()
        let aqm = PlaybackQualityManager(player: player)
        let atm = AudioTrackManager(player: player)
        self.sponsorBlockManager = sbm
        self.captionsManager = cam
        self.qualityManager = aqm
        self.audioManager = atm
        self.likeDislike = LikeDislikeController(
            api: api,
            logError: { msg in playerLog.error("[likeDislike] \(msg)") }
        )
        self.comments = CommentsController(api: api)

        player.allowsExternalPlayback = true
        #if canImport(UIKit)
        do {
            // Only configure the audio category at init time. setActive(true) is
            // deliberately deferred to loadAsync (PlaybackViewModel+Loading.swift ~line 494)
            // so that cold-launching the app does not interrupt background audio from
            // other apps before the user starts a video (GitHub issue #54).
            // setCategory alone does not interrupt other apps per AVAudioSession docs.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            playerLog.error("AVAudioSession category setup failed: \(error.localizedDescription)")
        }
        #endif
        setupTimeObserver()
        setupRateObserver()
        #if canImport(UIKit)
        setupRemoteCommandCenter()
        setupAudioSessionObserver()
        setupAirPlayObserver()
        #endif

        // Wire delegates (self is now fully initialised).
        sbm.delegate = self
        sbm.player = player
        aqm.delegate = self
        atm.delegate = self

        // Auto-enable Stats for Nerds during UI test runs so tests don't need to
        // navigate the more menu manually. Activated by `--uitesting-stats-for-nerds`.
        if ProcessInfo.processInfo.arguments.contains("--uitesting-stats-for-nerds") {
            statsForNerdsVisible = true
        }
    }

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        rateObserver?.invalidate()
        airPlayObserver?.invalidate()
        if let obs = audioSessionObserver { NotificationCenter.default.removeObserver(obs) }
        #if canImport(UIKit)
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

    // MARK: - Load video

    /// The ID of the video currently loaded (or being loaded). Exposed so PlayerView
    /// can detect spurious onAppear/onDisappear cycles (e.g. when a ShareLink sheet
    /// temporarily covers the player) and skip unnecessary reloads.
    public var currentVideoId: String? { currentVideo?.id }

    public func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        isAudioOnlyMode = newSettings.audioOnlyMode
    }
}

// MARK: - Delegate conformances

extension PlaybackViewModel: SponsorBlockDelegate {
    public func snapCurrentTime(to seconds: Double) { currentTime = seconds }
}

extension PlaybackViewModel: QualityContext {}

extension PlaybackViewModel: QualityEventHandler {
    func loadAudioTracks(from item: AVPlayerItem) {
        audioManager.loadAudioTracks(from: item)
    }

    func qualityItemDidBecomeReady(_ item: AVPlayerItem, seekTo time: TimeInterval) {
        // Clear the quality-change freeze so the time observer resumes.
        isQualityChangePending = false
        // currentTime was preserved during the transition (time observer suspended).
        // If the user seeked while the new item was loading, currentTime reflects
        // their intent (set in seek(to:) completion handler); otherwise it holds
        // the position captured at quality-change start.
        // Either way, currentTime is the authoritative target; `time` is the fallback
        // when currentTime is 0 (e.g. video is at the very start).
        let seekTarget = currentTime > 0 ? currentTime : time
        playerLog.notice("[quality] readyToPlay — seekTarget=\(seekTarget)s (currentTime=\(currentTime)s savedTime=\(time)s)")
        if seekTarget > 0 { seek(to: seekTarget) }
        isPlaying = true
        loadAudioTracks(from: item)
    }

    func qualityItemDidFail(error: Error?, quality: AppSettings.VideoQuality, hasAppliedH264Cap: Bool) async {
        let nsErr = (error as? NSError) ?? NSError(domain: "", code: 0)
        let action = qualityRecoveryAction(
            for: nsErr,
            quality: quality,
            hasAppliedH264Cap: hasAppliedH264Cap
        )
        switch action {
        case .retry403Recovery:
            if let video = currentVideo {
                playerLog.notice("Quality-switch 403 — invalidating cache and re-fetching player info")
                await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                HLSManifestCache.shared.invalidate(for: video.id)
                qualityManager.selectedFormat = nil
                await retryWith403Recovery(video: video, originalError: error)
            }
        case .revertToAuto:
            playerLog.notice("Quality-switch failed — reverting selectedFormat to Auto")
            qualityManager.selectedFormat = nil
            toastMessage = "Quality unavailable — reverting to Auto"
            await qualityManager.reloadHLSItem(seekTo: currentTime, quality: .auto)
        case .retryWithH264Cap:
            playerLog.notice("Auto HLS Cannot Decode — retrying with H.264 bitrate cap")
            qualityManager.hasAppliedH264Cap = true
            toastMessage = "Adjusting quality for this device…"
            await qualityManager.reloadHLSItemH264Capped(seekTo: currentTime)
        case .fail(let e):
            self.error = e
        }
    }

    func qualitySelectDASHFormat(videoURL: URL, audioURL: URL, seekTo: TimeInterval) async {
        await rebuildCompositionForQuality(videoURL: videoURL, audioURL: audioURL, seekTo: seekTo)
    }

    // MARK: - Wrong-video detection (fix236)

    /// Fires once per `load()` cycle when `isPlaying` transitions to `true`.
    /// Compares `currentVideo.id` against `intendedVideoId` set at `load()` time.
    /// On mismatch: records a `SmartTube.WrongVideo` non-fatal to Crashlytics and
    /// shows the user a toast so they know a report was filed automatically.
    private func checkWrongVideoOnFirstPlay() {
        guard pendingWrongVideoCheck else { return }
        pendingWrongVideoCheck = false
        guard let intended = intendedVideoId,
              let active = currentVideo,
              active.id != intended else { return }
        playerLog.error("[WrongVideo] MISMATCH at readyToPlay — intended=\(intended) active=\(active.id)")
        CrashlyticsLogger.sendWrongVideoReport(
            intendedId: intended,
            intendedTitle: intendedVideoTitle ?? intended,
            activeId: active.id,
            activeTitle: active.title
        )
        toastMessage = "⚠️ Wrong video loaded — report sent"
    }
}

extension PlaybackViewModel: AudioTrackDelegate {}
