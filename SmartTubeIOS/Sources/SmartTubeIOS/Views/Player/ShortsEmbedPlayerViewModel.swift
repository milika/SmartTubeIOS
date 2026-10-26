#if !os(tvOS)
import Foundation
import CoreFoundation
import AVFoundation
import WebKit
import os
import SmartTubeIOSCore

private let shortsLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsPlayer")

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
    /// True while this VM is loading a Short in the background for pre-warming.
    /// Suppresses Darwin notifications and auto-unmute so the standby WKWebView
    /// doesn't produce audible output or confuse active-VM observers.
    /// Cleared by `activate()` when the standby is promoted to the active slot.
    private(set) var isStandby: Bool = false

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
    /// Used by `transitionWatchHistory(to:)` (called from `loadShort`, once per
    /// swipe) and `saveProgress()` (called on dismiss) — see
    /// ShortsEmbedPlayerViewModel+WatchHistory.swift, Task 7.
    let tracker: WatchtimeTracker

    // MARK: - Internal

    let webView: WKWebView
    /// Distinguishes concurrent VM instances (active + standby) in the shared
    /// `shortsLog` stream — every prior debugging session lost time correlating
    /// which of two simultaneously-running VMs produced a given log line. See #275.
    let instanceId: Int
    private static var nextInstanceId = 0
    /// Short tag prefixed onto every log line — e.g. "vm3" or "vm3/standby".
    var logTag: String { "vm\(instanceId)\(isStandby ? "/standby" : "")" }
    /// Set by `loadShort(video:)`. Read by Task 6's `fetchSponsorSegments()` and
    /// Task 7's watch-history tracking — hence `private(set)`, not `private`.
    private(set) var videoId: String = ""
    /// Used to respect `settings.sponsorBlockExcludedChannels` — read by
    /// `fetchSponsorSegments()` (Task 6).
    private(set) var channelId: String? = nil

    /// Fires the "tickstarted" Darwin notification on the first tick received after
    /// each `loadShort(video:)` call — reset to `false` on every load.
    var hasReceivedFirstTick = false
    /// `false` until the first `loadShort(video:)` call — gates whether `loadShort`
    /// performs the initial `loadHTMLString` (`startEmbed`) or an iframe-src swap
    /// (`swapEmbed`).
    private var hasStarted = false
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
        config.allowsAirPlayForMediaPlayback = false
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
                source: ShortsEmbedJS.stateDetectionJS,
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

        let navDel = ShortsNavigationDelegate()
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

    // MARK: - Loading

    /// Loads `video` into the persistent `WKWebView`. The first call loads the HTML
    /// wrapper page (`startEmbed`); every subsequent call swaps the already-loaded
    /// `<iframe id="yt">`'s `src` (`swapEmbed`) — the mechanism validated by Task 1's
    /// spike. Resets all per-video `@Observable` state before loading, per the design
    /// spec's Data Flow section.
    func loadShort(video: Video) {
        transitionWatchHistory(to: video.id)

        sponsorTask?.cancel()
        sponsorTask = nil

        videoId = video.id
        channelId = video.channelId

        playerState = .unstarted
        currentTime = 0
        duration = 0
        isReady = false
        playerError = nil
        videoEnded = false
        embedFrameInfo = nil
        hasReceivedFirstTick = false
        sponsorSegments = []
        currentToastSegment = nil
        activeSkipEnd = nil
        pendingSkipLog = nil
        lastLoggedToastSegment = nil
        lastLoggedNearEndSegment = nil

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.void.smarttube.shortsplayer.loadstarted" as CFString),
            nil, nil, true
        )

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

    /// Loads `video` into this VM's WKWebView in standby (pre-warm) mode.
    /// The video initialises and reaches the "ready" state, but is immediately
    /// paused and never unmuted — no audible output occurs.
    /// Awaits `isReady` or a terminal `playerError` before returning, so the
    /// caller can check `isReady` synchronously after the call.
    func loadShortAsStandby(video: Video) async {
        isStandby = true
        loadShort(video: video)
        while !isReady && playerError == nil {
            if Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Promotes this VM to active: clears the standby flag and begins playback.
    /// Call after swapping this VM into the active `vm` slot — either a fresh
    /// forward standby (#272) or a cached `previousVM` being resumed after a
    /// backward swipe (#277).
    ///
    /// The "ready" Darwin notification is posted here rather than relying on a
    /// fresh JS message — "ready" only fires once per page load, and for a
    /// forward standby it already fired (suppressed) while in standby mode, so
    /// no second one is coming.
    ///
    /// `hasReceivedFirstTick` is reset here unconditionally. It's a one-shot
    /// gate ("has this VM ever ticked") that a fresh forward standby naturally
    /// starts at `false` — but `previousVM` is the SAME instance that was
    /// already active before being retired, so its first tick already fired
    /// and the flag is permanently `true` without this reset. Left unreset, the
    /// "tickstarted" Darwin notification (and downstream UI relying on it)
    /// would never refire on a backward swipe — confirmed via
    /// `ShortsEmbedPlayerUITests.testSwipingBackwardAlsoRefiresJSBridge`. The
    /// reset is a harmless no-op for the forward case, where it's already false.
    func activate() {
        isStandby = false
        hasReceivedFirstTick = false
        play()
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.void.smarttube.shortsplayer.ready" as CFString),
            nil, nil, true
        )
    }

    /// First-ever load for this session — loads the HTML wrapper page via
    /// `webView.loadHTMLString`. Mirrors `TOSPlayerViewModel.loadEmbed`
    /// (TOSPlayerViewModel.swift:392-453), using `ShortsEmbedURL` (Task 2) instead of
    /// duplicating the URL/HTML construction.
    private func startEmbed(videoId: String) {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            shortsLog.error(
                "[\(self.logTag, privacy: .public)] [audioSession] setActive(true) failed: \(error.localizedDescription, privacy: .public)"
            )
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
                "[\(self.logTag, privacy: .public)] [loadShort] ready TIMEOUT — videoId=\(videoId, privacy: .public) after 9s"
            )
            self.playerError = .webViewLoadFailed
        }
    }

    // MARK: - JS Commands (operating on YouTube embed page's <video> element)
    //
    // Identical eval()-based pattern to TOSPlayerViewModel.swift:292-388 — see
    // `embedFrameInfo`'s doc comment for why frame-targeting is required.

    func play() {
        playPauseEpoch &+= 1
        let myEpoch = playPauseEpoch
        // Wait for any in-flight pauseAllMediaPlayback() (from a just-prior pause())
        // to actually land first — otherwise it can resolve after this play() and
        // re-pause the video out from under it. See pauseAllMediaTask's doc comment.
        let priorPause = pauseAllMediaTask
        Task { [weak self] in
            await priorPause?.value
            guard let self, self.playPauseEpoch == myEpoch else { return }
            self.eval(
                "play",
                "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.play();}return {found: !!v, iframes: ifr, paused: v ? v.paused : null};})();"
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
            "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.pause();}return {found: !!v, iframes: ifr, paused: v ? v.paused : null};})();"
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

// MARK: - ShortsNavigationDelegate

/// Minimal navigation delegate — logs provisional-navigation failures only. Modeled
/// on Task 1's `SpikeNavigationDelegate`; per-Short "ready"/"tick" notifications
/// (Task 5) already give Task 10's UI test what it needs without porting
/// `TOSNavigationDelegate`'s full set of diagnostic notifications.
private final class ShortsNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        shortsLog.error("[nav] provisional navigation failed: \(error)")
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
