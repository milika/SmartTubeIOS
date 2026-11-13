#if !os(tvOS)
import Foundation
import CoreFoundation
import AVFoundation
import WebKit
import os
import SmartTubeIOSCore

private let shortsLog = Logger(subsystem: appSubsystem, category: "ShortsPlayer")

/// State owner for the iOS Shorts TOS-embed player — replaces the AVPlayer-based
/// `PlaybackViewModel` for the Shorts pipeline (see
/// `docs/superpowers/specs/2026-06-11-tos-player-shorts-design.md`).
///
/// Owns ONE persistent `WKWebView` for the lifetime of a `ShortsPlayerView` session.
/// `loadShort(video:)` is called once per Short: the first call loads the HTML
/// wrapper page via `webView.loadHTMLString`; every subsequent call swaps the
/// already-loaded `<iframe id="yt">`'s `src` via `eval()` — the mechanism validated
/// by Task 1's `ShortsEmbedSrcSwapSpikeViewModel.swapToNextVideo()`.
///
/// Structurally mirrors `TOSPlayerViewModel` (same JS-bridge architecture, same
/// frame-targeted `eval()` pattern via `embedFrameInfo`), but is a separate type per
/// the design spec's "Code-structure approach" decision — isolation from the
/// production regular-video player in exchange for some duplication.
@MainActor
@Observable
final class ShortsEmbedPlayerViewModel: NSObject {

    // MARK: - Public state

    var playerState: YTPlayerState = .unstarted
    var currentTime: Double = 0
    var duration: Double = 0
    var isReady: Bool = false
    /// Non-nil when the player encounters an error that requires falling back
    /// (e.g. auto-advancing to the next Short — see Task 9).
    var playerError: TOSPlayerError? = nil
    /// A decoded frame of this Short is on screen in the web view (JS `frame`
    /// message): the poster covering this page can drop without flashing black.
    var hasFrame: Bool = false
    /// True for the Short on screen. False for a neighbour preloading in its own
    /// slot of `ShortsPlayerPool`: the embed sits muted and paused on its first frame
    /// (`ShortsEmbedJS` "held" mode), and Darwin notifications, tick-driven state and
    /// watch history stay quiet until `activate()`.
    private(set) var isLive: Bool = false
    /// Set by `stop()` (and by going to the background mid-start) until the next
    /// `play()`. While set, the embed is kept on hold even when this Short is live:
    /// its frame can report in late, and telling it to go live then would start the
    /// hidden player with sound.
    private(set) var isStopped: Bool = false
    /// `applyPlaybackMode()` held a live Short because it was stopped; `play()`
    /// sends the live mode it skipped.
    private(set) var isLiveModeDeferred: Bool = false
    /// The live Short timed out while stopped (see `timedOut()`); `play()` reloads it.
    private(set) var reloadsOnPlay: Bool = false

    // MARK: - View State
    //
    // Controls visibility, playback-ended state, and lifecycle bookkeeping —
    // surfaced via ShortsEmbedPlayerViewModel+ViewState.swift (Task 9) to give this
    // type the same name-matching surface as PlaybackViewModel, which
    // ShortsPlayerView's shared (non-#if) call sites rely on.

    var controlsVisible: Bool = false
    var videoEnded: Bool = false
    var wasPlayingBeforeSuspend: Bool = false
    var controlsTimer: Task<Void, Never>?
    /// Tracks `pause()`'s in-flight `webView.pauseAllMediaPlayback()` call, which can
    /// take a noticeable amount of time to actually execute inside WebKit's WebContent
    /// process. Without tracking it, a `play()` issued shortly after a `pause()` races
    /// against this delayed call — the video visibly resumes, then the stale
    /// `pauseAllMediaPlayback()` finally lands and pauses it again ~0.2-0.3s later,
    /// with no corresponding `togglePlayPause()` call (confirmed via live device log).
    /// `play()` awaits this before issuing its own play command so the two can never
    /// race out of order.
    private var pauseAllMediaTask: Task<Void, Never>?
    /// Incremented on every `play()`/`pause()` call. `play()`'s post-resume
    /// verification (see below) checks this hasn't changed before re-asserting
    /// playback, so it never overrides a more recent, deliberate pause.
    private var playPauseEpoch: Int = 0
    /// Cancelled once "ready" arrives for the in-flight `loadShort` (see
    /// ShortsEmbedPlayerViewModel+WebBridge.swift's "ready" case); if it fires
    /// first, `playerError` is set to `.webViewLoadFailed` so the new `advanceAfterError()`
    /// (below) can skip to the next Short.
    var readyTimeoutTask: Task<Void, Never>?
    /// Tracks the in-flight SponsorBlock fetch so it can be cancelled on swipe.
    var sponsorTask: Task<Void, Never>?

    // MARK: - SponsorBlock
    //
    // Declared here so Task 4 compiles standalone. Fetch (loadShort → Task 6's
    // fetchSponsorSegments) and tick-driven skip (Task 6's checkSponsorSkip) are
    // wired up by Task 6's edits to this file and to +WebBridge.swift.

    var sponsorSegments: [SponsorSegment] = []
    /// The segment currently showing a skip toast, if any.
    var currentToastSegment: SponsorSegment? = nil
    /// Guards against re-triggering a skip within the same segment.
    var activeSkipEnd: Double? = nil
    /// Bridges an auto-skip's "before" log line to its "after" line — see
    /// `PendingSkipLog` in TOSPlayerViewModel+SponsorBlock.swift (reused as-is).
    var pendingSkipLog: PendingSkipLog? = nil
    var lastLoggedToastSegment: SponsorSegment? = nil
    var lastLoggedNearEndSegment: SponsorSegment? = nil

    // MARK: - Sleep Timer
    //
    // Mirrors TOSPlayerViewModel.swift:92-101 — the sleep timer calls pause() on
    // whatever's playing, so it works automatically once pause() exists below.

    let sleepTimer = SleepTimerController()
    var sleepTimerMinutes: Int? { sleepTimer.sleepTimerMinutes }
    func setSleepTimer(minutes: Int?) {
        sleepTimer.setSleepTimer(minutes: minutes) { [weak self] in
            self?.pause()
            shortsLog.notice("[\(self?.logTag ?? "vm?", privacy: .public)] [sleepTimer] fired — pausing playback")
        }
    }

    // MARK: - Dependencies

    private(set) var settings: AppSettings = AppSettings()
    /// Used by `fetchSponsorSegments()` (ShortsEmbedPlayerViewModel+SponsorBlock.swift,
    /// Task 6).
    let sponsorService = SponsorBlockService()
    let api: InnerTubeAPI
    /// Used by `beginWatchSession()`/`endWatchSession()` (a Short going live / leaving
    /// the screen) and `saveProgress()` (called on dismiss) — see
    /// ShortsEmbedPlayerViewModel+WatchHistory.swift.
    let tracker: WatchtimeTracker

    // MARK: - Internal

    let webView: WKWebView
    /// Distinguishes concurrent VM instances (active + standby) in the shared
    /// `shortsLog` stream — every prior debugging session lost time correlating
    /// which of two simultaneously-running VMs produced a given log line. See #275.
    let instanceId: Int
    private static var nextInstanceId = 0
    /// Short tag prefixed onto every log line — e.g. "vm3" or "vm3/held".
    var logTag: String { "vm\(instanceId)\(isLive ? "" : "/held")" }
    /// Set by `loadShort(video:)`. Read by Task 6's `fetchSponsorSegments()` and
    /// Task 7's watch-history tracking — hence `private(set)`, not `private`.
    private(set) var videoId: String = ""
    /// The Short last passed to `loadShort(video:live:)` — reloaded by `activate()`
    /// when its preload timed out.
    private(set) var video: Video?
    /// Used to respect `settings.sponsorBlockExcludedChannels` — read by
    /// `fetchSponsorSegments()` (Task 6).
    private(set) var channelId: String? = nil

    /// Fires the "tickstarted" Darwin notification on the first tick received after
    /// each `loadShort(video:)` call — reset to `false` on every load.
    var hasReceivedFirstTick = false
    /// `false` until the first `loadShort(video:)` call — gates whether `loadShort`
    /// performs the initial `loadHTMLString` (`startEmbed`) or an iframe-src swap
    /// (`swapEmbed`).
    private(set) var hasStarted = false
    /// Strong reference to the WKWebView's navigation delegate (WKWebView retains it
    /// weakly).
    private var navigationDelegate: ShortsNavigationDelegate?

    /// `WKFrameInfo` of the cross-origin YouTube embed `<iframe>` — see
    /// `TOSPlayerViewModel.embedFrameInfo`'s doc comment (TOSPlayerViewModel.swift:161-184)
    /// for the full root-cause story of why `eval()` must target this frame rather
    /// than the wrapper page's main frame. Reset to `nil` on every
    /// `loadShort(video:)` call (each iframe-src swap produces a new frame) and
    /// re-captured from the next "ready" message
    /// (ShortsEmbedPlayerViewModel+WebBridge.swift, Task 5).
    var embedFrameInfo: WKFrameInfo?

    // MARK: - Init

    init(api: InnerTubeAPI) {
        self.api = api
        self.tracker = WatchtimeTracker(api: api)
        ShortsEmbedPlayerViewModel.nextInstanceId += 1
        self.instanceId = ShortsEmbedPlayerViewModel.nextInstanceId

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        // CRITICAL on iOS: without this, YouTube's embed hijacks the native system
        // video player when the user taps play — mirrors TOSPlayerViewModel.swift:206-209.
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        #endif

        let contentController = WKUserContentController()
        let proxyHandler = ShortsScriptMessageProxy()
        contentController.add(proxyHandler, contentWorld: .page, name: "ytCallback")

        contentController.addUserScript(
            WKUserScript(
                source: ShortsEmbedJS.webkitHiderJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            ))
        contentController.addUserScript(
            WKUserScript(
                source: ShortsEmbedJS.playerControlsHiderJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            ))
        contentController.addUserScript(
            WKUserScript(
                source: ShortsEmbedJS.pooledStateDetectionJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                in: .page
            ))
        config.userContentController = contentController

        self.webView = WKWebView(frame: .zero, configuration: config)
        // TV User-Agent so YouTube serves the TV player variant — same reason
        // as TOSPlayerViewModel.swift. The TV variant uses the YouTube TV API
        // for its auth check, which authenticates against the TV session
        // cookies (TVFAS etc.) that the TV device-code sign-in flow sets. The
        // web variant needs a YouTube WEB session (SAPISID) which the TV flow
        // can't produce. See AuthService+YouTubeCookies.swift for the
        // Multilogin 403 INVALID_TOKENS root cause.
        self.webView.customUserAgent =
            "Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) " + "AppleWebKit/537.36 (KHTML, like Gecko) "
            + "SamsungBrowser/2.1 Chrome/56.0.2924.0 TV Safari/537.36"
        #if os(iOS)
        // isOpaque=false forces WebKit into software compositing, which silently
        // disables the hardware-accelerated <video> layer — the JS bridge still
        // reports ready/playing correctly (that's all JS-driven), but no video
        // frames ever reach the screen, just a black rect. Mirrors
        // TOSPlayerViewModel.swift:282-284 (the working regular-video pipeline),
        // which has always used isOpaque=true/.black. See #275.
        self.webView.isOpaque = true
        self.webView.backgroundColor = .black
        self.webView.scrollView.backgroundColor = .black
        #endif

        super.init()

        proxyHandler.target = self

        let navDel = ShortsNavigationDelegate(target: self)
        self.webView.navigationDelegate = navDel
        self.navigationDelegate = navDel
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "ytCallback",
            contentWorld: .page
        )
    }

    // MARK: - Settings update

    /// Called from `ShortsPlayerView.onAppear`. Mirrors `TOSPlayerViewModel.updateSettings(_:)`.
    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
    }

    /// `updateSettings(_:)` for a Short that is already loaded (e.g. back from
    /// Settings): reloads its SponsorBlock segments when the change affects them.
    func syncSettings(_ newSettings: AppSettings) {
        let before = SponsorBlockConfig(settings)
        settings = newSettings
        if SponsorBlockConfig(newSettings) != before { reloadSponsorSegments() }
    }

    /// Fills in the current Short's channel once its metadata arrives (reel entries
    /// load without one), so `sponsorBlockExcludedChannels` applies to it.
    func updateChannelId(_ newChannelId: String?, for videoId: String) {
        guard videoId == self.videoId, let newChannelId, newChannelId != channelId else { return }
        channelId = newChannelId
        if settings.sponsorBlockExcludedChannels[newChannelId] != nil { reloadSponsorSegments() }
    }

    // MARK: - Loading

    /// Loads `video` into the persistent `WKWebView`. The first call loads the HTML
    /// wrapper page (`startEmbed`); every subsequent call swaps the already-loaded
    /// `<iframe id="yt">`'s `src` (`swapEmbed`). Resets all per-video `@Observable`
    /// state before loading.
    ///
    /// `live: false` preloads it as a neighbour: muted, paused on its first frame,
    /// until `activate()`.
    func loadShort(video: Video, live: Bool) {
        if isLive { endWatchSession() }
        isLive = live
        playPauseEpoch &+= 1

        sponsorTask?.cancel()
        sponsorTask = nil

        self.video = video
        videoId = video.id
        channelId = video.channelId

        playerState = .unstarted
        currentTime = 0
        duration = 0
        isReady = false
        hasFrame = false
        playerError = nil
        videoEnded = false
        embedFrameInfo = nil
        isLiveModeDeferred = false
        reloadsOnPlay = false
        hasReceivedFirstTick = false
        sponsorSegments = []
        currentToastSegment = nil
        activeSkipEnd = nil
        pendingSkipLog = nil
        lastLoggedToastSegment = nil
        lastLoggedNearEndSegment = nil

        if live {
            beginWatchSession()
            postLoadStarted()
        }

        if hasStarted {
            swapEmbed(to: video.id)
        } else {
            hasStarted = true
            // Sync YouTube cookies from HTTPCookieStorage → WKWebsiteDataStore
            // BEFORE startEmbed's loadHTMLString. Mirrors TOSPlayerViewModel's
            // startIfNeeded fix (same root cause — see TOSPlayerViewModel.swift
            // doc comment for syncYouTubeCookiesIntoWKWebView).
            Task { @MainActor in
                await self.syncYouTubeCookiesIntoWKWebView()
                self.startEmbed(videoId: video.id)
            }
        }

        startReadyTimeout(for: video.id)
    }

    /// Makes this preloaded Short the one on screen: unmutes it and starts it from
    /// its first frame, which is already decoded and buffered. No-op when already live.
    ///
    /// Returns a task that finishes once the embed has been told to play with sound
    /// (nil when nothing was sent to it), so the outgoing Short can stay audible
    /// until then — see `holdEmbed(after:)`.
    @discardableResult
    func activate() -> Task<Void, Never>? {
        guard !isLive else { return nil }
        if case .webViewLoadFailed? = playerError, let video {
            // The preload never got ready; try again as the live Short.
            loadShort(video: video, live: true)
            return nil
        }
        isLive = true
        hasReceivedFirstTick = false
        playPauseEpoch &+= 1
        // The held embed reports "paused"; don't flash the paused icon until the
        // next tick reports real playback.
        if playerState == .paused || playerState == .ended { playerState = .buffering }
        beginWatchSession()
        postLoadStarted()
        let started = applyPlaybackMode()
        if isReady {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.shortsplayer.ready" as CFString),
                nil, nil, true
            )
        }
        // Unconditionally: a neighbour preloaded at another speed keeps that rate on
        // its <video> until told otherwise, including back to 1×.
        setPlaybackRate(settings.playbackSpeed)
        shortsLog.notice(
            "[\(self.logTag, privacy: .public)] [activate] videoId=\(self.videoId, privacy: .public) isReady=\(self.isReady, privacy: .public) hasFrame=\(self.hasFrame, privacy: .public)"
        )
        return started
    }

    /// The Short scrolled off screen but stays loaded as a neighbour: flushes its
    /// watch history and puts it back on hold (muted, paused on its first frame).
    ///
    /// `keepingEmbedLive` leaves the embed itself playing until `holdEmbed(after:)`.
    /// The pool does that on a swipe: if the old Short went quiet before the new one
    /// was playing with sound, WebKit would deactivate the audio session in between,
    /// and on a device the new Short's audio would stay dead.
    func deactivate(keepingEmbedLive: Bool = false) {
        guard isLive else { return }
        endWatchSession()
        isLive = false
        isStopped = false
        isLiveModeDeferred = false
        if reloadsOnPlay {
            // Held now: `activate()` retries a failed preload.
            reloadsOnPlay = false
            playerError = .webViewLoadFailed
        }
        playPauseEpoch &+= 1
        videoEnded = false
        controlsVisible = false
        cancelControlsHide()
        currentToastSegment = nil
        activeSkipEnd = nil
        pendingSkipLog = nil
        if !keepingEmbedLive { applyPlaybackMode() }
        shortsLog.notice("[\(self.logTag, privacy: .public)] [deactivate] videoId=\(self.videoId, privacy: .public)")
    }

    /// Puts the embed of a Short deactivated with `keepingEmbedLive` on hold once
    /// `handOff` (the incoming Short's `activate()`) has finished. Skipped if the
    /// Short became live again meanwhile.
    func holdEmbed(after handOff: Task<Void, Never>?) {
        guard let handOff else {
            if !isLive { applyPlaybackMode() }
            return
        }
        Task { @MainActor in
            await handOff.value
            guard !self.isLive else { return }
            self.applyPlaybackMode()
        }
    }

    /// Tells the embed whether it is live or held (`window.__stSetLive`). Before the
    /// embed frame has reported in there is nothing to target; the frame's first
    /// message calls this again (see `captureEmbedFrame(_:)`).
    ///
    /// Returns a task that finishes once the page has run it, or nil if there was no
    /// embed frame to tell.
    @discardableResult
    func applyPlaybackMode() -> Task<Void, Never>? {
        guard let frame = embedFrameInfo else { return nil }
        let live = embedShouldBeLive
        isLiveModeDeferred = isLive && !live
        let label = live ? "setLive(true)" : "setLive(false)"
        let js = "window.__stSetLive && window.__stSetLive(\(live));"
        return Task { @MainActor in
            do {
                let value = try await self.webView.evaluateJavaScript(js, in: frame, contentWorld: .page)
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [eval] \(label, privacy: .public) result: \(String(describing: value), privacy: .public)"
                )
            } catch {
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [eval] \(label, privacy: .public) ERROR: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// What `applyPlaybackMode()` tells the embed: live only for the Short on screen,
    /// and not while it is stopped.
    var embedShouldBeLive: Bool { isLive && !isStopped }

    /// Pauses the player until the next `play()`. A Short still starting is put back
    /// on hold instead: pausing alone doesn't stick there, as the embed keeps
    /// retrying its autoplay while the video sits at its start.
    func suspendPlayback() {
        isStopped = true
        pause()
        if isStarting { applyPlaybackMode() }
    }

    /// This player becomes live while the player view is still out of sight
    /// (`ShortsPlayerPool.show` carries the stop over): it stays on hold until `play()`.
    func markStopped() {
        isStopped = true
    }

    /// The player view is visible again but not resuming (e.g. the user had paused).
    /// A Short held by the stop stays on hold, paused, until `play()`.
    func endStop() {
        isStopped = false
    }

    private func postLoadStarted() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.void.smarttube.shortsplayer.loadstarted" as CFString),
            nil, nil, true
        )
    }

    /// First-ever load for this session — loads the HTML wrapper page via
    /// `webView.loadHTMLString`. Mirrors `TOSPlayerViewModel.loadEmbed`
    /// (TOSPlayerViewModel.swift:392-453), using `ShortsEmbedURL` (Task 2) instead of
    /// duplicating the URL/HTML construction.
    private func startEmbed(videoId: String) {
        #if os(iOS)
        // Only for the Short on screen. A neighbour preloading held makes no sound,
        // and activating the app's own session interrupts WebKit's (a separate
        // session in its GPU process): the Short playing at that moment pauses. On a
        // device that hit the first swipe after every launch, when the third slot
        // loads its first Short.
        if isLive {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                shortsLog.error(
                    "[\(self.logTag, privacy: .public)] [audioSession] setActive(true) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        #endif
        // Cookie sync happens in loadShort (the await syncYouTubeCookies runs
        // BEFORE this method is called). See TOSPlayerViewModel.swift doc
        // comment for syncYouTubeCookiesIntoWKWebView for the root cause.
        let url = ShortsEmbedURL.embedURL(videoId: videoId)
        let html = ShortsEmbedURL.htmlWrapper(embedURL: url)
        shortsLog.notice(
            "[\(self.logTag, privacy: .public)] [loadShort] initial load — videoId=\(videoId, privacy: .public)")
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.example.com")!)
    }

    /// Sync YouTube session cookies from HTTPCookieStorage.shared into
    /// WKWebsiteDataStore.default(). See TOSPlayerViewModel.syncYouTubeCookiesIntoWKWebView
    /// for the full root-cause story — the same bug applies here.
    private func syncYouTubeCookiesIntoWKWebView() async {
        let yt = URL(string: "https://www.youtube.com")!
        let google = URL(string: "https://www.google.com")!
        let cookies =
            (HTTPCookieStorage.shared.cookies(for: yt) ?? []) + (HTTPCookieStorage.shared.cookies(for: google) ?? [])
        guard !cookies.isEmpty else {
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [loadShort] no youtube/google cookies in HTTPCookieStorage — IFrame will run unauthenticated"
            )
            return
        }
        let names = cookies.map { "\($0.name)@\($0.domain)" }.joined(separator: " ")
        shortsLog.notice(
            "[\(self.logTag, privacy: .public)] [loadShort] copying \(cookies.count) cookies → WKWebsiteDataStore: \(names as NSString)"
        )
        let store = WKWebsiteDataStore.default().httpCookieStore
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { cont.resume() }
        }
        shortsLog.notice("[\(self.logTag, privacy: .public)] [loadShort] cookie sync done")
    }

    /// Every load after the first — swaps the already-loaded `<iframe id="yt">`'s
    /// `src` to the new video's embed URL. This is the core mechanic validated by
    /// Task 1's `ShortsEmbedSrcSwapSpikeViewModel.swapToNextVideo()`.
    private func swapEmbed(to videoId: String) {
        let url = ShortsEmbedURL.embedURL(videoId: videoId)
        shortsLog.notice(
            "[\(self.logTag, privacy: .public)] [loadShort] src swap — videoId=\(videoId, privacy: .public)")
        eval("swap", "document.getElementById('yt').src = '\(url.absoluteString)';")
    }

    /// Starts a 9s timeout for the in-flight `loadShort(video:)` call. Cancelled by
    /// the "ready" case in ShortsEmbedPlayerViewModel+WebBridge.swift once the new
    /// frame reports ready; if it fires first, sets `playerError =
    /// .webViewLoadFailed` so ShortsPlayerView+Navigation.swift's
    /// `advanceAfterError()` can skip to the next Short. Mirrors the design spec's
    /// Error Handling section ("ready" timeout, ~8-10s).
    private func startReadyTimeout(for videoId: String) {
        readyTimeoutTask?.cancel()
        readyTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            guard let self, !Task.isCancelled else { return }
            guard self.videoId == videoId, !self.isReady else { return }
            shortsLog.notice(
                "[\(self.logTag, privacy: .public)] [loadShort] ready TIMEOUT — videoId=\(videoId, privacy: .public) after 9s stopped=\(self.isStopped, privacy: .public)"
            )
            self.timedOut()
        }
    }

    /// The Short never got ready. A hidden web view doesn't load the stream, so a live
    /// Short that timed out while stopped isn't broken: it reloads on the next
    /// `play()` instead of failing (which would skip it while nobody is looking).
    func timedOut() {
        if isLive && isStopped {
            reloadsOnPlay = true
        } else {
            playerError = .webViewLoadFailed
        }
    }

    // MARK: - JS Commands (operating on YouTube embed page's <video> element)
    //
    // Identical eval()-based pattern to TOSPlayerViewModel.swift:292-388 — see
    // `embedFrameInfo`'s doc comment for why frame-targeting is required.

    func play() {
        isStopped = false
        if reloadsOnPlay, isLive, let video {
            loadShort(video: video, live: true)
            return
        }
        playPauseEpoch &+= 1
        let myEpoch = playPauseEpoch
        // Wait for any in-flight pauseAllMediaPlayback() (from a just-prior pause())
        // to actually land first — otherwise it can resolve after this play() and
        // re-pause the video out from under it. See pauseAllMediaTask's doc comment.
        let priorPause = pauseAllMediaTask
        Task { [weak self] in
            await priorPause?.value
            guard let self, self.playPauseEpoch == myEpoch else { return }
            if self.isLiveModeDeferred {
                // Held while stopped: going live unmutes it and starts it.
                self.applyPlaybackMode()
                return
            }
            self.eval(
                "play",
                "(function(){var p=document.getElementById('movie_player');var api=!!(p&&typeof p.playVideo==='function');if(api){p.playVideo();}var v=document.querySelector('video');if(v){v.play();}return {found: !!v, api: api, paused: v ? v.paused : null};})();"
            )
            // Defense-in-depth: even after awaiting the prior pause, a late-landing
            // pause from some other source (e.g. WebKit's own stall handling) can
            // still clobber this resume a few hundred ms later — exactly the "plays
            // then re-pauses" symptom confirmed via live device log. Verify shortly
            // after that playback actually stuck, and re-assert if not — but only if
            // nothing more recent (a deliberate pause or another play) has happened.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, self.playPauseEpoch == myEpoch else { return }
            self.eval(
                "verifyPlay",
                "(function(){var v=document.querySelector('video');if(v&&v.paused){v.play();}return {paused: v?v.paused:null};})();"
            )
        }
    }

    /// Stops playback — including audio — regardless of which frame the `<video>`
    /// element lives in. See `TOSPlayerViewModel.pause()`'s doc comment
    /// (TOSPlayerViewModel.swift:296-324) for the cross-origin-iframe root cause this
    /// works around.
    ///
    /// Pauses through YouTube's player API (`movie_player.pauseVideo()`) as well as the
    /// `<video>` element: pausing only the element leaves YouTube's player thinking it
    /// is still playing, and it resumes the video ~200 ms later — a single tap then
    /// never pauses (seen in device logs: `pause → paused=1`, then `paused=false`).
    func pause() {
        playPauseEpoch &+= 1
        pauseAllMediaTask = Task { [weak self] in
            guard let self else { return }
            await self.webView.pauseAllMediaPlayback()
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.shortsplayer.pausedAllMedia" as CFString),
                nil, nil, true
            )
        }
        eval(
            "pause",
            "(function(){var p=document.getElementById('movie_player');var api=!!(p&&typeof p.pauseVideo==='function');if(api){p.pauseVideo();}var v=document.querySelector('video');if(v){v.pause();}return {found: !!v, api: api, paused: v ? v.paused : null};})();"
        )
    }

    func seekTo(_ seconds: Double) {
        eval(
            "seekTo(\(seconds))",
            "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.currentTime=\(seconds);}return {found: !!v, iframes: ifr, currentTime: v ? v.currentTime : null};})();"
        )
    }

    /// Shows the native `<video controls>` UI inside the embed iframe (play/pause,
    /// scrubber, time). Called when the player pauses so the user has something to
    /// interact with. The native controls live in WebKit's shadow DOM and are not
    /// affected by our `body * { visibility:hidden }` CSS, so they always show on
    /// top of the video regardless of the style injection.
    func showEmbedControls() {
        eval("embedControls(on)", "(function(){var v=document.querySelector('video');if(v)v.controls=true;})();")
    }

    /// Hides the native `<video controls>` UI. Called when playback resumes.
    func hideEmbedControls() {
        eval("embedControls(off)", "(function(){var v=document.querySelector('video');if(v)v.controls=false;})();")
    }

    func setPlaybackRate(_ rate: Double) {
        eval(
            "setPlaybackRate(\(rate))",
            "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.playbackRate=\(rate);}return {found: !!v, iframes: ifr, playbackRate: v ? v.playbackRate : null};})();"
        )
    }

    // MARK: - Private helpers

    /// Frame-targeted eval — see `TOSPlayerViewModel.eval`'s doc comment
    /// (TOSPlayerViewModel.swift:363-378).
    private func eval(_ label: String, _ js: String) {
        webView.evaluateJavaScript(js, in: embedFrameInfo, in: .page) { result in
            switch result {
            case .success(let value):
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [eval] \(label, privacy: .public) result: \(String(describing: value), privacy: .public)"
                )
            case .failure(let error):
                shortsLog.notice(
                    "[\(self.logTag, privacy: .public)] [eval] \(label, privacy: .public) ERROR: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}

// MARK: - Web content process termination

extension ShortsEmbedPlayerViewModel {
    /// WebKit terminated this web view's content process (on a device: the GPU process
    /// asks for it under media pressure). Left alone, WebKit reloads the page as the
    /// bare embed URL, without the wrapper's `<iframe id="yt">`, so every later
    /// `swapEmbed` throws and each Short loaded here times out. Load the wrapper again
    /// with the current Short instead.
    func webContentProcessDidTerminate() {
        shortsLog.error(
            "[\(self.logTag, privacy: .public)] [nav] web content process terminated — reloading the wrapper for videoId=\(self.videoId, privacy: .public)"
        )
        hasStarted = false
        guard let video else { return }
        loadShort(video: video, live: isLive)
    }
}

// MARK: - ShortsNavigationDelegate

/// Minimal navigation delegate — logs provisional-navigation failures and recovers
/// from a terminated web content process. Modeled on Task 1's
/// `SpikeNavigationDelegate`; per-Short "ready"/"tick" notifications (Task 5) already
/// give Task 10's UI test what it needs without porting `TOSNavigationDelegate`'s full
/// set of diagnostic notifications.
private final class ShortsNavigationDelegate: NSObject, WKNavigationDelegate {
    weak var target: ShortsEmbedPlayerViewModel?

    init(target: ShortsEmbedPlayerViewModel) {
        self.target = target
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        shortsLog.error("[nav] provisional navigation failed: \(error)")
    }

    /// Implementing this also stops WebKit's own reload, which would leave the bare
    /// embed page as the main frame — see `webContentProcessDidTerminate()`.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated { [weak target] in
            target?.webContentProcessDidTerminate()
        }
    }
}

// MARK: - ShortsScriptMessageProxy

/// Breaks the retain cycle: `WKUserContentController` retains its handlers strongly.
/// This proxy holds a `weak` reference so `ShortsEmbedPlayerViewModel` is not kept
/// alive by the web view's content controller — mirrors `ScriptMessageProxy` in
/// TOSPlayerViewModel.swift:631-656 / `SpikeScriptMessageProxy` in Task 1.
private final class ShortsScriptMessageProxy: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    weak var target: ShortsEmbedPlayerViewModel?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? String else { return }
        let frameInfo = message.frameInfo
        MainActor.assumeIsolated { [weak target] in
            target?.handleScriptMessage(body, frameInfo: frameInfo)
        }
    }
}
#endif
