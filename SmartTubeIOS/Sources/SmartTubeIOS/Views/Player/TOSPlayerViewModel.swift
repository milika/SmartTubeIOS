#if !os(tvOS)
import Foundation
import CoreFoundation
import AVFoundation
import WebKit
import SmartTubeIOSCore
import os
#if os(iOS)
import UIKit
#endif

private let tosLog = Logger(subsystem: "com.void.smarttube.app", category: "TOSPlayer")

// MARK: - YTPlayerState

/// Maps the numeric state code returned by the YouTube IFrame API.
enum YTPlayerState: Int {
    case unstarted  = -1
    case ended      =  0
    case playing    =  1
    case paused     =  2
    case buffering  =  3
    case cued       =  5
    case unknown    = 999

    init(raw: Int) {
        self = YTPlayerState(rawValue: raw) ?? .unknown
    }
}

// MARK: - TOSPlayerError

enum TOSPlayerError: Equatable {
    /// Video does not allow embedding (IFrame error 101 / 150).
    case embeddingDisabled
    /// Video not found (IFrame error 100).
    case notFound
    /// Generic IFrame player error.
    case iframeError(Int)
    /// WKWebView failed to load the player page.
    case webViewLoadFailed

    var isFatal: Bool {
        switch self {
        case .embeddingDisabled, .notFound, .webViewLoadFailed: return true
        case .iframeError(153): return true  // Video player configuration error
        default: return false
        }
    }
}

// MARK: - TOSPlayerViewModel

/// State owner for the macOS TOS-compliant YouTube embed player.
///
/// Architecture: loads `https://www.youtube.com/embed/{videoId}` directly in WKWebView
/// (not via the IFrame API in our own HTML), then injects `stateDetectionJS` to poll
/// the `<video>` element and relay state via `window.webkit.messageHandlers.ytCallback`.
///
/// All mutation is `@MainActor`. The `WKScriptMessageHandler` bridge dispatches back
/// to main actor via `Task { @MainActor in ... }`.
@MainActor
@Observable
final class TOSPlayerViewModel: NSObject {

    // MARK: - Public state

    var playerState: YTPlayerState = .unstarted
    var currentTime: Double = 0
    var duration: Double = 0
    var isReady: Bool = false
    /// Mirror of the player's mute state, for the external-display controls.
    var isMuted: Bool = false
    /// Mirror of YouTube's caption toggle, for the external-display controls.
    var captionsOn: Bool = false
    /// Whether the current embed document carries the external-display CSS class.
    /// Reset by loadEmbed: a new document starts without it.
    @ObservationIgnored private var chromeHiddenForExternalDisplay = false
    /// Non-nil when the player encounters an error that requires falling back.
    var playerError: TOSPlayerError? = nil

    // MARK: - SponsorBlock

    var sponsorSegments: [SponsorSegment] = []
    /// The segment currently showing a skip toast, if any.
    var currentToastSegment: SponsorSegment? = nil

    // MARK: - Like / Dislike / Sleep Timer
    //
    // Backed by the shared LikeDislikeController/SleepTimerController
    // (PlayerFeatures/) also used by PlaybackViewModel — both features are pure
    // API/timer operations with no AVPlayer dependency.

    /// Seeded from cached `nextInfo.likeStatus` in `beginWatchtimeTracking()`.
    let likeDislike: LikeDislikeController
    var likeStatus: LikeStatus { likeDislike.likeStatus }
    func like() { likeDislike.like(videoId: videoId) }
    func dislike() { likeDislike.dislike(videoId: videoId) }
    /// Non-nil while a sleep-timer countdown is active; drives the moreButton's label
    /// and the checkmark in its picker submenu. Mirrors `PlaybackViewModel.sleepTimerMinutes`.
    let sleepTimer = SleepTimerController()
    var sleepTimerMinutes: Int? { sleepTimer.sleepTimerMinutes }
    func setSleepTimer(minutes: Int?) {
        sleepTimer.setSleepTimer(minutes: minutes) { [weak self] in
            self?.pause()
            tosLog.notice("[sleepTimer] fired — pausing playback")
        }
    }

    // MARK: - Comments
    //
    // Backed by the shared CommentsController (PlayerFeatures/) also used by
    // PlaybackViewModel — see TOSPlayerViewModel+Comments.swift for loadComments().

    let comments: CommentsController

    // MARK: - Navigation (swipe left/right)
    //
    // Backs TOSSwipeNavigationOverlay (swipe-left → next, swipe-right → previous).
    // See TOSPlayerViewModel+Navigation.swift for fetchRelatedVideos()/playNext()/playPrevious().

    /// Populated by `fetchRelatedVideos()` once the "ready" bridge message fires.
    var relatedVideos: [Video] = []
    /// Set by `TOSPlayerStateStore.play(video:api:)` via `setNavigationContext(hasPrevious:)`
    /// based on whether a navigation history exists.
    var hasPrevious: Bool = false
    /// Wired by TOSPlayerView to `tosState.play(video:api:)` for the next related video.
    var onPlayNext: ((Video) -> Void)?
    /// Wired by TOSPlayerView to pop `TOSPlayerStateStore.history` and re-play it.
    var onPlayPrevious: (() -> Void)?

    // MARK: - Dependencies

    private(set) var settings: AppSettings = AppSettings()
    /// Used by `fetchSponsorSegments()` (TOSPlayerViewModel+SponsorBlock.swift).
    let sponsorService = SponsorBlockService()
    /// Passed to `likeDislike`/`comments` controllers and used to construct
    /// `tracker` below.
    let api: InnerTubeAPI
    /// Drives watch-position checkpointing (VideoStateStore) and watch-history
    /// reporting (InnerTubeAPI) — parity with the standard PlaybackViewModel's
    /// `tracker`. See `beginWatchtimeTracking()`/`saveProgress()`
    /// (TOSPlayerViewModel+WatchHistory.swift) for where this is begun/used.
    let tracker: WatchtimeTracker

    // MARK: - Internal

    let webView: WKWebView
    /// Used by `fetchSponsorSegments()`/`beginWatchtimeTracking()`/`saveProgress()`/
    /// `like()`/`dislike()` — all in extension files, hence `internal` not `private`.
    let videoId: String
    let videoTitle: String
    /// Used to respect `settings.sponsorBlockExcludedChannels` — mirrors the
    /// channel-exclusion check in `PlaybackViewModel+Loading`'s SponsorBlock phase.
    /// Read by `fetchSponsorSegments()` in TOSPlayerViewModel+SponsorBlock.swift.
    let channelId: String?
    /// Used for Now Playing info (lock screen / Control Center) — see
    /// TOSPlayerViewModel+NowPlaying.swift.
    let channelTitle: String
    let thumbnailURL: URL?
    /// Playlist context passed from `Video.playlistId`/`playlistIndex`. Non-nil
    /// when the video was opened from the CurrentQueue or a YouTube playlist.
    let playlistId: String?
    let playlistIndex: Int?
    /// Video IDs already played in this session — filtered from suggestions so
    /// the same videos don't cycle back on repeated swipes.
    var seenVideoIds: Set<String> = []
    private let startTime: Double
    /// Guards against re-triggering a skip within the same segment.
    /// Mutated by `checkSponsorSkip(at:)` in TOSPlayerViewModel+SponsorBlock.swift.
    var activeSkipEnd: Double? = nil
    /// Set when an auto-skip seek is fired; cleared once a subsequent "tick" confirms
    /// where playback landed (or times out). `seekTo` is a fire-and-forget JS eval with
    /// no completion callback, so the "after" time can only be observed asynchronously
    /// from the next tick — never synchronously right after calling `seekTo`. See
    /// `PendingSkipLog` / the "tick" handler in `handleScriptMessage` for the landing
    /// check (both in TOSPlayerViewModel+SponsorBlock.swift).
    var pendingSkipLog: PendingSkipLog? = nil
    /// The most recently logged toast segment, so `checkSponsorSkip` logs a "toast SHOW"
    /// notice only on the transition into a new segment — not on every tick while the
    /// toast remains visible (which would spam the log at ~4 lines/second).
    var lastLoggedToastSegment: SponsorSegment? = nil
    /// The most recently logged near-end segment (`.skipToPlaybackEnd`), so
    /// `checkSponsorSkip` logs once per segment rather than on every tick until
    /// the video naturally ends.
    var lastLoggedNearEndSegment: SponsorSegment? = nil
    /// Strong reference to the WKWebView's navigation delegate (WKWebView retains it weakly).
    private var navigationDelegate: TOSNavigationDelegate?
    /// Fires the "tickstarted" Darwin notification on the first tick received.
    /// Mutated by `handleScriptMessage(_:)` in TOSPlayerViewModel+WebBridge.swift.
    var hasReceivedFirstTick = false
    /// Fires the "timeadvanced" Darwin notification on the FIRST tick where
    /// `currentTime > 0.1` AND `state == .playing` — i.e. the playhead has
    /// actually moved past the seek-to-start point, which is the strict proof
    /// the video is actually playing (not just buffering at t=0). Mutated by
    /// `handleScriptMessage(_:)` in TOSPlayerViewModel+WebBridge.swift.
    ///
    /// WHY THIS EXISTS — the existing "playing" notification fires on state=1
    /// OR state=3 (buffering), so it can be triggered by the IFrame sitting at
    /// t=0 in a buffering state, which is NOT proof of actual playback. The
    /// iOS UI test (TOSPlayerIOSUITests) gates its "video is actually playing"
    /// assertion on this notification, and the two-screenshot diff that
    /// follows it; without it, the test would pass on a stuck-at-t=0
    /// thumbnail screenshot, which was the previous turn's failure mode.
    var hasReceivedTimeAdvanced = false
    /// Prevents loadEmbed from firing in instances SwiftUI creates-then-discards during init.
    private var hasStartedLoading = false
    /// Stored handle for the in-flight fetchSponsorSegments Task. Cancelled on full dismiss
    /// to prevent a late @Observable mutation after TOSPlayerView teardown.
    var sponsorTask: Task<Void, Never>?
    /// Stored handle for the in-flight fetchRelatedVideos Task. Cancelled on full dismiss
    /// to prevent a late @Observable mutation after TOSPlayerView teardown.
    var navigationTask: Task<Void, Never>?

    // MARK: - Now Playing (see TOSPlayerViewModel+NowPlaying.swift)

    #if os(iOS)
    @ObservationIgnored var nowPlayingInfoCache: [String: Any] = [:]
    /// `nonisolated(unsafe)` so MPMediaItemArtwork's requestHandler closure (invoked
    /// on MediaPlayer's private serial queue) can read it without a Swift 6
    /// actor-isolation assertion — mirrors PlaybackViewModel.cachedArtwork exactly.
    nonisolated(unsafe) var cachedArtwork: UIImage? = nil
    @ObservationIgnored var cachedArtworkVideoID: String? = nil
    #endif

    /// `WKFrameInfo` of the cross-origin YouTube embed `<iframe>` — the ONLY frame
    /// whose document contains the `<video>` element. Captured from the first "ready"
    /// message (see `handleScriptMessage`'s "ready" case in +WebBridge.swift).
    ///
    /// WHY THIS EXISTS — root cause of `play/pause/seekTo/setPlaybackRate` being
    /// silent no-ops: `loadEmbed()` wraps the YouTube IFrame embed in a cross-origin
    /// `<iframe id="yt" src="https://www.youtube.com/embed/...">` inside a wrapper
    /// page loaded at `https://www.example.com`. `webView.evaluateJavaScript(_:)`
    /// (no frame parameter) ALWAYS targets the wrapper's MAIN frame — Apple-documented
    /// behavior — so `document.querySelector('video')` run that way always finds
    /// nothing (`{found: false, iframes: 1}`, confirmed empirically — see `eval`'s
    /// diagnostic and the device-log evidence in `pause()`'s doc comment) and the
    /// `if (v) ...` guards silently no-op every command.
    ///
    /// `stateDetectionJS` succeeds where `eval` fails because it's injected with
    /// `forMainFrameOnly: false` (runs natively inside the iframe's own document).
    /// It posts "ready" ONLY after `document.querySelector('video')` actually located
    /// a `<video>` element — so the `WKScriptMessage.frameInfo` carried by that
    /// specific message is GUARANTEED to be the iframe's frame, not the wrapper's.
    /// `ScriptMessageProxy` threads that `frameInfo` through to `handleScriptMessage`,
    /// which stores it here on first sight. From then on, `eval()` targets it directly
    /// via the frame-aware `evaluateJavaScript(_:in:in:completionHandler:)` overload
    /// (macOS 11+ / iOS 14+) — the actual fix for the cross-origin-iframe defect.
    var embedFrameInfo: WKFrameInfo?

    // MARK: - Init

    init(videoId: String, title: String = "", channelId: String? = nil, channelTitle: String = "", thumbnailURL: URL? = nil, playlistId: String? = nil, playlistIndex: Int? = nil, startTime: Double = 0, api: InnerTubeAPI) {
        self.videoId = videoId
        self.videoTitle = title
        self.channelId = channelId
        self.channelTitle = channelTitle
        self.thumbnailURL = thumbnailURL
        self.playlistId = playlistId
        self.playlistIndex = playlistIndex
        self.startTime = startTime
        self.api = api
        self.tracker = WatchtimeTracker(api: api)
        self.likeDislike = LikeDislikeController(
            api: api,
            logError: { msg in tosLog.error("[likeDislike] \(msg)") }
        )
        self.comments = CommentsController(
            api: api,
            logError: { msg in tosLog.error("[comments] \(msg)") }
        )

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        // CRITICAL on iOS: without this, YouTube's embed hijacks the native system
        // video player when the user taps play, taking control away from the WKWebView.
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        // Explicit (default may vary across iOS versions) — required for the native
        // PiP button to appear in the embedded <video>'s controls. Investigated as
        // part of #283 (background play/PiP support); does not by itself enable PiP
        // or background audio — see task-283 for what was actually tried and learned.
        config.allowsPictureInPictureMediaPlayback = true
        #endif

        let contentController = WKUserContentController()
        // The external-display chrome rule travels with every document, in every frame,
        // so a video change cannot lose it. Only the class toggled by setChromeHidden
        // decides whether it applies — and a fresh document starts without the class,
        // which is the right default for playback on the phone.
        //
        // With the TV user agent above, YouTube serves its mobile embed: `#movie_player`
        // runs with `ytp-hide-controls` and the actual controls (title row, play/pause,
        // scrubber, mute/CC/settings) live in a sibling `#player-controls` host at body
        // level, which pops up on every pause and seek. The engagement panel and bottom
        // sheet are its menus; `.ytp-popup` / `.ytp-unmute` are the player's own
        // overlays. Captions stay visible on purpose.
        contentController.addUserScript(WKUserScript(
            source: "(function(){var d=document,i='st-ext-style';if(d.getElementById(i))return;"
                + "var s=d.createElement('style');s.id=i;s.textContent="
                + "'html.st-external-display #player-controls,"
                + "html.st-external-display #engagement-panel-wrapper,"
                + "html.st-external-display #bottom-sheet-wrapper,"
                + "html.st-external-display .ytp-popup,"
                + "html.st-external-display .ytp-unmute{display:none!important}';"
                + "(d.head||d.documentElement).appendChild(s);})();",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        let proxyHandler = ScriptMessageProxy()
        contentController.add(proxyHandler, contentWorld: .page, name: "ytCallback")

        // Hide window.webkit BEFORE any page script runs. YouTube's embed player
        // checks window.webkit.messageHandlers to detect a WKWebView environment and
        // fires error 153 when found. Hiding it lets the player treat this as a normal
        // browser. The native ytCallback reference is saved as window.__nativeYTCallback
        // for use by stateDetectionJS (injected later at atDocumentEnd).
        let webkitHiderScript = WKUserScript(
            source: Self.webkitHiderJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        contentController.addUserScript(webkitHiderScript)

        // Inject state-detection JS into every frame at document-end.
        // The YouTube embed runs inside an <iframe> (see loadEmbed), so
        // forMainFrameOnly: false is required to reach the iframe's document.
        let detectionScript = WKUserScript(
            source: Self.stateDetectionJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
            in: .page
        )
        contentController.addUserScript(detectionScript)

        config.userContentController = contentController

        self.webView = WKWebView(frame: .zero, configuration: config)
        // Use a TV User-Agent so YouTube serves the TV player variant of the
        // embed (vs. the web variant). The TV variant runs the YouTube TV
        // API for its player-config check, which authenticates against the
        // YouTube TV session cookies (`__Secure-YT_TVFAS`, `__Secure-YT_DERP`,
        // `DEVICE_INFO`) that the TV device-code sign-in flow sets. The web
        // variant needs a YouTube WEB session (SAPISID on youtube.com),
        // which the TV flow can never produce — see `AuthService+YouTubeCookies.swift`
        // for the Multilogin 403 INVALID_TOKENS root cause.
        //
        // Same user agent as `YouTubeClientCredentials.swift` (TVHTML5 bot
        // scraping) and the yuliskov Android SmartTube app's TV WebView
        // config — confirmed to work against YouTube's TV auth path.
        self.webView.customUserAgent = "Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) " +
            "SamsungBrowser/2.1 Chrome/56.0.2924.0 TV Safari/537.36"
        #if os(macOS)
        // NSView-level KVC — not available on iOS UIView.
        self.webView.setValue(false, forKey: "drawsBackground")
        #else
        // Opaque black background (matching the AVPlayer pipeline's container) so
        // WKWebView's default white rendering doesn't flash through before the
        // YouTube embed's content paints during the fullscreen transition.
        self.webView.isOpaque = true
        self.webView.backgroundColor = .black
        self.webView.scrollView.backgroundColor = .black
        #endif

        super.init()

        proxyHandler.target = self

        // Separate NSObject navigation delegate avoids Swift 6 @MainActor isolation
        // interfering with Objective-C WKNavigationDelegate dispatch.
        let navDel = TOSNavigationDelegate()
        self.webView.navigationDelegate = navDel
        self.navigationDelegate = navDel

        // loadEmbed is NOT called here — SwiftUI calls View.init() many times during
        // layout (creating and discarding State(initialValue:) values). Only the instance
        // that actually appears calls startIfNeeded() from onAppear.
    }

    /// Move the embed onto an attached external screen once it is audibly playing,
    /// and keep the embed's chrome in step with where it is shown. Called on every
    /// poll tick, so the phone and the TV never disagree for more than one tick.
    ///
    /// The IFrame's player-config check times out against a page that is not visible,
    /// so the web view has to stay in the phone's window until playback has started.
    /// And the embed starts muted: the poll script unmutes it on the first tick past
    /// 0.1 s (the tick that also sets `hasReceivedTimeAdvanced`). Moving the view
    /// before that lands the unmute on a page WebKit already treats as hidden, and
    /// the video plays on silently until the next play() from the phone — hence the
    /// margin after that tick.
    func syncExternalDisplay() {
        #if os(iOS)
        if playerState == .playing, hasReceivedTimeAdvanced, currentTime > 0.5 {
            ExternalDisplayManager.shared.offer(webView)
        }
        let onExternalScreen = ExternalDisplayManager.shared.owns(webView)
        guard onExternalScreen != chromeHiddenForExternalDisplay else { return }
        chromeHiddenForExternalDisplay = onExternalScreen
        setChromeHidden(onExternalScreen)
        if onExternalScreen { refreshExternalDisplayControls() }
        #endif
    }

    /// Read the player's mute and caption state back into the mirrors the
    /// external-display controls draw from. YouTube resets both per video.
    func refreshExternalDisplayControls() {
        evalReturning("refreshExternalDisplayControls",
                      "(function(){var p=document.getElementById('movie_player');"
                        + "if(!p||typeof p.isMuted!=='function')return null;"
                        + "return {muted:p.isMuted(),captions:p.isSubtitlesOn()};})();") { [weak self] value in
            guard let self, let state = value as? [String: Any] else { return }
            if let muted = state["muted"] as? Bool { isMuted = muted }
            if let captions = state["captions"] as? Bool { captionsOn = captions }
        }
    }

    /// Toggle mute through the player API rather than the media element: YouTube keeps
    /// its own mute flag and re-applies it onto `video.muted`, so a DOM-only change
    /// drifts out of step with what the player reports.
    func toggleMuted() {
        evalReturning("toggleMuted",
                      "(function(){var p=document.getElementById('movie_player');"
                        + "if(!p||typeof p.isMuted!=='function')return null;"
                        + "if(p.isMuted()){p.unMute();}else{p.mute();}return p.isMuted();})();") { [weak self] value in
            if let muted = value as? Bool { self?.isMuted = muted }
        }
    }

    /// Toggle YouTube's own caption track. Its CC button is part of the chrome hidden on
    /// the external screen, so the phone needs a way to reach it.
    func toggleCaptions() {
        evalReturning("toggleCaptions",
                      "(function(){var p=document.getElementById('movie_player');"
                        + "if(!p||typeof p.toggleSubtitles!=='function')return null;"
                        + "p.toggleSubtitles();return p.isSubtitlesOn();})();") { [weak self] value in
            if let on = value as? Bool { self?.captionsOn = on }
        }
    }

    /// Called from TOSPlayerView.onAppear. No-op — the actual load happens from
    /// YouTubeWebPlayerView's window-ready callback via startIfNeededWhenWindowReady
    /// (and from TOSPlayerStateStore.play() when a vm replaces one already on
    /// screen). Kept for the existing call site.
    func startIfNeeded() {
        // Intentionally empty — see startIfNeededWhenWindowReady().
    }

    /// Called by YouTubeWebPlayerView (TOSPlayerView.swift) once the
    /// WKWebView is added to a visible (key) window. This is when
    /// the cover-present animation has completed and the IFrame can
    /// safely run its player-config check. Safe to call multiple times —
    /// loads only once.
    func startIfNeededWhenWindowReady() {
        tosLog.notice("[vm] startIfNeededWhenWindowReady called, hasStartedLoading=\(self.hasStartedLoading)")
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        // Delay before loading the IFrame. The historical reason for any delay
        // here was the SwiftUI cover-present animation (UIKit .fullScreen modal)
        // that hides the WKWebView's view during presentation — YouTube's 5s
        // player-config check would time out against a hidden page, producing
        // error 153. With the test-only inline presentation path (see
        // RootView.swift `--uitesting-inline-tos`), the WKWebView is visible
        // from frame 1, so we use a much smaller delay there. Production still
        // uses the cover-present, where a small delay is still needed.
        let useInlinePresentation = ProcessInfo.processInfo.arguments.contains("--uitesting-inline-tos")
        let delaySeconds: TimeInterval = useInlinePresentation ? 0.3 : 1.5
        tosLog.notice("[vm] startIfNeededWhenWindowReady — useInlinePresentation=\(useInlinePresentation) delaySeconds=\(delaySeconds)")
        // Using DispatchQueue.main.asyncAfter (not a Task @MainActor in)
        // because Tasks get cancelled by the SwiftUI re-render cycle before
        // the sleep completes — asyncAfter isn't subject to view-lifecycle
        // cancellation.
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
            guard let self else {
                tosLog.notice("[vm] asyncAfter fired but self is nil — skipping")
                return
            }
            tosLog.notice("[vm] asyncAfter fired, webView isNil=\(self.webView == nil), calling loadEmbed directly (no Task wrapper)")
            Task { @MainActor in
                await self.syncYouTubeCookiesIntoWKWebView()
                tosLog.notice("[vm] cookies synced, calling loadEmbed")
                self.loadEmbed(videoId: self.videoId, startTime: self.startTime)
                tosLog.notice("[vm] loadEmbed returned")
            }
        }
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "ytCallback",
            contentWorld: .page
        )
    }

    // MARK: - Settings update

    /// Called from `TOSPlayerView.onAppear`. Mirrors `PlaybackViewModel.updateSettings(_:)`.
    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
    }

    // MARK: - Lifecycle

    /// Cancels the in-flight sponsor-segments and related-videos fetch Tasks.
    /// Called from `TOSPlayerView.onDisappear` on full dismiss (not mini-player minimize)
    /// to prevent late `@Observable` property mutations after the view's environment chain
    /// is torn down — which would trigger a SwiftUI body re-evaluation crash (a013be1c).
    func cancel() {
        sponsorTask?.cancel()
        navigationTask?.cancel()
    }

    /// Called when the app returns to the foreground (TOSPlayerView's scenePhase observer).
    /// Lifts the OS-level media suspension so audio comes back without the user having
    /// to toggle mute. The stateDetectionJS `visibilitychange` + `_bgRemutePollRetries`
    /// loop handles the DOM-level `video.muted` reset from inside the iframe.
    #if os(iOS)
    func handleForeground() {
        Task { await webView.setAllMediaPlaybackSuspended(false) }
        // On the external screen the resume can leave the element "playing" with the
        // clock stopped. A play() from native counts as a user gesture and gets it
        // going again; only nudge when the clock has actually stalled.
        guard ExternalDisplayManager.shared.owns(webView) else { return }
        let before = currentTime
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, playerState == .playing, currentTime == before,
                  ExternalDisplayManager.shared.owns(webView) else { return }
            tosLog.notice("[ExternalDisplay] foreground — clock stalled at \(before, format: .fixed(precision: 1))s, nudging play()")
            play()
        }
    }
    #endif

    // MARK: - JS Commands (operating on YouTube embed page's <video> element)

    func play() {
        eval("play", "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.play();}return {found: !!v, iframes: ifr, paused: v ? v.paused : null};})();")
    }

    /// Stops playback — including audio — regardless of which frame the `<video>`
    /// element actually lives in.
    ///
    /// ROOT CAUSE of "video can still be heard after pressing back" (the same defect
    /// that made `play/seekTo/setPlaybackRate` silent no-ops — see `embedFrameInfo`'s
    /// doc comment for the full story): `loadEmbed()` wraps the YouTube IFrame embed
    /// in a cross-origin `<iframe id="yt" src="https://www.youtube.com/embed/...">`
    /// inside a wrapper page loaded at `https://www.example.com`. `webView
    /// .evaluateJavaScript(_:)` with no frame parameter ALWAYS targets the wrapper's
    /// MAIN frame (Apple-documented behavior) — but the `<video>` element lives
    /// inside the iframe's own (different-origin) document, which the main frame's
    /// `document.querySelector` cannot see. Before `embedFrameInfo` was wired up, the
    /// eval-based "pause" below silently found nothing (`{found: false, iframes: 1}`
    /// — empirically confirmed via device log) and the JS `if (v) v.pause()` guard
    /// made it a no-op that "succeeded" with no error. `TOSPlayerView.onDisappear`'s
    /// `vm.pause()` therefore never actually paused anything, and the embed kept
    /// playing — and being heard — after the player UI was dismissed.
    ///
    /// Fix: `WKWebView.pauseAllMediaPlayback` is the OS-level API purpose-built for
    /// exactly this — it suspends media playback in EVERY frame of the web view,
    /// including cross-origin iframes, sidestepping the frame-targeting problem
    /// entirely (no `document.querySelector` / `WKFrameInfo` needed). This is what
    /// actually silences the audio on dismissal — kept even after `eval()` became
    /// frame-aware, because it's strictly stronger (works even before "ready" fires
    /// and `embedFrameInfo` is captured) and is the dedicated OS primitive for
    /// "stop everything" scenarios like onDisappear. The `eval("pause", …)` call
    /// below is now retained purely as ongoing diagnostic instrumentation — it will
    /// also report `found: true` once `embedFrameInfo` is captured (frame-targeted
    /// like every other command), confirming the fix from a second angle.
    func pause() {
        let stateBefore = playerState
        let timeBefore = currentTime
        tosLog.notice("[pause] requested — playerState=\(String(describing: stateBefore), privacy: .public) currentTime=\(timeBefore, format: .fixed(precision: 1))s")
        // Strong capture deliberate (mirrors saveProgress()/beginWatchtimeTracking()):
        // this fires from onDisappear, where SwiftUI may release `self` (and thus
        // `webView`) at any moment — [weak self] would race losing the webView
        // reference before pauseAllMediaPlayback() is even called, silently
        // reintroducing the exact bug this method exists to fix.
        Task {
            await self.webView.pauseAllMediaPlayback()
            tosLog.notice("[pause] pauseAllMediaPlayback completed (was playerState=\(String(describing: stateBefore), privacy: .public) currentTime=\(timeBefore, format: .fixed(precision: 1))s)")
            // Cross-process signal for XCTest — lets a UI test `wait(for:)` confirmation
            // that the OS-level "stop everything" pause actually completed when the
            // player is dismissed, instead of guessing a sleep duration. Mirrors the
            // .loadstarted/.navfinished/.ready/.sponsorskip notifications above.
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.tosplayer.pausedAllMedia" as CFString),
                nil, nil, true
            )
        }
        // Diagnostic-only (kept for ongoing monitoring — see eval()'s comment): proves
        // empirically, on every pause() call, that the main-frame query keeps finding
        // nothing. Harmless no-op against the wrapper page's empty `document.querySelector`.
        eval("pause", "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.pause();}return {found: !!v, iframes: ifr, paused: v ? v.paused : null};})();")
    }

    func seekTo(_ seconds: Double) {
        eval("seekTo(\(seconds))", "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.currentTime=\(seconds);}return {found: !!v, iframes: ifr, currentTime: v ? v.currentTime : null};})();")
    }

    /// Hide the IFrame's own chrome while the embed plays on an external screen.
    /// Its controls and menus are unreachable there — nothing can tap them — and they
    /// dim the picture. The phone draws its own. See the user script in init for
    /// what the class hides.
    func setChromeHidden(_ hidden: Bool) {
        eval("setChromeHidden(\(hidden))",
             "(function(){document.documentElement.classList.toggle('st-external-display',\(hidden));"
                + "return document.documentElement.className;})();")
    }

    func setPlaybackRate(_ rate: Double) {
        eval("setPlaybackRate(\(rate))", "(function(){var v=document.querySelector('video');var ifr=document.querySelectorAll('iframe').length;if(v){v.playbackRate=\(rate);}return {found: !!v, iframes: ifr, playbackRate: v ? v.playbackRate : null};})();")
    }

    // MARK: - Private helpers

    // FRAME-TARGETED EVAL (the fix for the cross-origin-iframe defect described on
    // `embedFrameInfo`): `evaluateJavaScript(_:in:in:completionHandler:)` is the
    // frame-aware overload (macOS 11+ / iOS 14+) — passing `embedFrameInfo` runs
    // `js` inside the YouTube embed iframe's own document, where `document
    // .querySelector('video')` actually finds the `<video>` element, instead of the
    // wrapper page's empty main frame. Until the first "ready" message arrives,
    // `embedFrameInfo` is nil — `evaluateJavaScript(_:in: nil, ...)` then falls back
    // to the main frame (the historical, safely-no-op behavior), so commands issued
    // in the brief pre-ready window degrade gracefully instead of crashing.
    //
    // The {found, iframes, ...} diagnostic payload is kept (systematic-debugging
    // Phase 1 evidence gathering): it now flips to `found: true` once the frame
    // targeting is correct, which is the empirical proof the fix actually works —
    // see the device-log comparison in the "before"/"after" sections of this
    // session's investigation. Logged at .notice (not .debug) so it survives
    // xcresulttool diagnostic export.
    /// `eval` plus the returned value, for the controls that mirror player state.
    func evalReturning(_ label: String, _ js: String, _ completion: @escaping (Any?) -> Void) {
        webView.evaluateJavaScript(js, in: embedFrameInfo, in: .page) { result in
            switch result {
            case .success(let value):
                tosLog.notice("[eval] \(label, privacy: .public) result: \(String(describing: value), privacy: .public)")
                Task { @MainActor in completion(value) }
            case .failure(let error):
                tosLog.notice("[eval] \(label, privacy: .public) ERROR: \(String(describing: error), privacy: .public)")
                Task { @MainActor in completion(nil) }
            }
        }
    }

    func eval(_ label: String, _ js: String) {
        webView.evaluateJavaScript(js, in: embedFrameInfo, in: .page) { result in
            switch result {
            case .success(let value):
                tosLog.notice("[eval] \(label, privacy: .public) result: \(String(describing: value), privacy: .public)")
            case .failure(let error):
                tosLog.notice("[eval] \(label, privacy: .public) ERROR: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Embed URL loader

    /// Sync YouTube session cookies from `HTTPCookieStorage.shared` (where the
    /// YouTube TV device-code sign-in flow + `AuthService.fetchYouTubeWebCookies`
    /// land them) into `WKWebsiteDataStore.default()` (where the IFrame reads
    /// from). The two stores are SEPARATE in iOS — `URLSession` writes to
    /// `HTTPCookieStorage`, `WKWebView` reads from `WKWebsiteDataStore`, and
    /// `HTTPCookieStorage.setCookie(_:)` does NOT auto-propagate to the WebKit
    /// store. Without this sync, the IFrame sees an empty `youtube.com` cookie
    /// jar → YouTube's player-config check has no auth → error 153 within ~5s.
    ///
    /// ROOT CAUSE (2026-07-14, finally): the app's CookiePersistence policy for
    /// the YouTube TV device-code OAuth callback is `.allowed` (set by
    /// `ASWebAuthenticationSession`), which writes to the app's
    /// `binarycookies` (the on-disk form of `HTTPCookieStorage.shared`). The
    /// existing codebase syncs WKWebsiteDataStore → HTTPCookieStorage in
    /// `YouTubeWebViewHLSExtractor.swift:800` and `BotGuardWebViewRunner.swift:495`
    /// (for the reverse direction: capturing page-load cookies for the AVPlayer
    /// HLS proxy). Nobody syncs the other way, so the TOS IFrame — which uses
    /// `WKWebsiteDataStore.default()` — has been silently running without cookies
    /// since the TOS port landed (e4e7086). Confirmed on the test simulator:
    /// `Library/Cookies/com.void.smarttube.app.binarycookies` has 9 youtube.com
    /// cookies including `__Secure-YT_TVFAS` (12 chars) and `__Secure-YT_DERP`
    /// (16 chars), but `Library/WebKit/com.void.smarttube.app/WebsiteData/`
    /// has only the `origin` index files, zero cookie files.
    ///
    /// Implementation notes:
    /// - Only copies `*.youtube.com` and `*.google.com` cookies (the union of
    ///   domains the YouTube IFrame / BotGuard PoToken / player-config endpoints
    ///   actually request). Skips 3rd-party trackers, doubleclick, etc.
    /// - Sets cookies via `httpCookieStore.setCookie(_:completionHandler:)` per
    ///   Apple recommendation; awaited serially in the same continuation so
    ///   they all land before the IFrame is loaded (a single `TaskGroup` would
    ///   race the IFrame load).
    /// - Idempotent: safe to call on every `loadEmbed` (the set is overwrite-
    ///   semantics for the same name+domain+path).
    private func syncYouTubeCookiesIntoWKWebView() async {
        let yt = URL(string: "https://www.youtube.com")!
        let google = URL(string: "https://www.google.com")!
        let cookies = (HTTPCookieStorage.shared.cookies(for: yt) ?? []) +
                      (HTTPCookieStorage.shared.cookies(for: google) ?? [])
        guard !cookies.isEmpty else {
            tosLog.notice("[loadEmbed] syncYouTubeCookiesIntoWKWebView: no youtube/google cookies in HTTPCookieStorage — IFrame will run unauthenticated")
            return
        }
        let names = cookies.map { "\($0.name)@\($0.domain)" }.joined(separator: " ")
        tosLog.notice("[loadEmbed] syncYouTubeCookiesIntoWKWebView: copying \(cookies.count) cookies → WKWebsiteDataStore: \(names as NSString)")
        let store = WKWebsiteDataStore.default().httpCookieStore
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { cont.resume() }
        }
        tosLog.notice("[loadEmbed] syncYouTubeCookiesIntoWKWebView: done")
    }

    private func loadEmbed(videoId: String, startTime: Double) {
        #if os(iOS)
        // The document loads on the phone: this web view is not offered to the
        // external screen until playback is running (see syncExternalDisplay), as the
        // IFrame's player-config check times out there (error 153). A fresh document
        // starts without the chrome class.
        chromeHiddenForExternalDisplay = false
        #endif
        // TOSPlayerViewModel never instantiates PlaybackViewModel (PlayerRouter
        // routes TOS and AVPlayer pipelines exclusively), so nothing else in the TOS
        // pipeline activates the audio session. Without this, WKWebView's media
        // engine can grab a brief moment of audio during init and then lose the
        // route — mirrors PlaybackViewModel+Loading's setActive(true) call.
        #if os(iOS)
        // Same .playback/.moviePlayback category PlaybackViewModel uses — more
        // correct than leaving the category unset, though confirmed (#283) this
        // alone does not make TOS audio survive backgrounding; see task-283.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            tosLog.error("[audioSession] setCategory/setActive failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
        // Cookie sync happens in startIfNeeded() (the await syncYouTubeCookies
        // runs BEFORE this method is called). We cannot redo it here without
        // a second loadEmbed awaiting on something already awaited upstream —
        // and the WKWebsiteDataStore cookie set is overwrite-by-name+domain+path,
        // so redoing it is a harmless no-op, but it's a wasted ~10-20ms of
        // dispatch-group round-tripping for the IFrame.
        var comps = URLComponents(string: "https://www.youtube.com/embed/\(videoId)")!
        comps.queryItems = [
            URLQueryItem(name: "autoplay",       value: "1"),
            URLQueryItem(name: "mute",           value: "1"),
            URLQueryItem(name: "controls",       value: "1"),
            URLQueryItem(name: "playsinline",    value: "1"),
            URLQueryItem(name: "rel",            value: "0"),
            URLQueryItem(name: "iv_load_policy", value: "3"),
            URLQueryItem(name: "start",          value: "\(Int(startTime))"),
            URLQueryItem(name: "origin",         value: "https://www.example.com"),
        ]
        let embedURL = comps.url!
        tosLog.notice("[loadEmbed] loading \(embedURL)")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.void.smarttube.tosplayer.loadstarted" as CFString),
            nil, nil, true
        )
        // Wrap the embed URL in a minimal HTML page so YouTube's JS sees
        // window.parent !== window (iframe context). Loading the embed URL
        // directly as the top-level document makes window.parent === window,
        // which causes YouTube to fire error 153 for all videos.
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <style>
                html,body,iframe{margin:0;padding:0;border:0;width:100%;height:100%;background:#000}
                iframe{position:absolute;top:0;left:0}
            </style>
        </head>
        <body>
            <iframe id="yt"
                src="\(embedURL.absoluteString)"
                frameborder="0"
                allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
                allowfullscreen>
            </iframe>
        </body>
        </html>
        """
        // Use a real baseURL so the parent page has a non-null cross-origin origin.
        // This gives iframe HTTP requests a proper Referer and Sec-Fetch-Site: cross-site
        // header (matching a legitimate third-party embed). nil/about:blank produces
        // Sec-Fetch-Site: none which some YouTube CDN nodes reject.
        // Must not be youtube.com — that would trigger YouTube's self-embed detection.
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.example.com")!)
    }

    // MARK: - WKUserScripts

    /// Injected at atDocumentStart into every frame. Hides window.webkit before any page
    /// script runs so YouTube's player can't detect the WKWebView environment. Stores
    /// the native ytCallback reference as window.__nativeYTCallback for stateDetectionJS.
    private static let webkitHiderJS: String = """
    (function() {
        try {
            var wk = window.webkit;
            if (!wk) return;
            var mh = wk.messageHandlers;
            window.__nativeYTCallback = (mh && mh.ytCallback) ? mh.ytCallback : null;
            Object.defineProperty(window, 'webkit', {
                get: function() { return undefined; },
                set: function() {},
                configurable: true,
                enumerable: false
            });
        } catch(e) {}
    })();
    """

    /// JavaScript injected at document-end into the YouTube embed page.
    /// Polls the `<video>` element and relays state via window.__nativeYTCallback
    /// (saved by webkitHiderJS before window.webkit was hidden).
    private static let stateDetectionJS: String = """
    (function() {
        try {
            var _cb = window.__nativeYTCallback;
            if (_cb) _cb.postMessage('{"type":"ping"}');
        } catch(e) {}

        var _prevState = -2;
        var _playAttempts = 0;
        var _autoUnmuted = false;
        var _pausedCandidate = false;
        var _prevMuted = null;
        // Set to true by visibilitychange when the page hides (app backgrounds).
        // Cleared when we detect a mute→true transition caused by the hide, so the
        // subsequent false→true mute is attributed to iOS, not to the user.
        var _wasHidden = false;
        // When > 0, pollVideo re-applies unmute each tick and decrements.
        // Started when we detect iOS re-muted the video after a background event.
        // Cap of 12 polls ≈ 3 seconds — enough for YouTube's player to finish
        // re-initialising after setAllMediaPlaybackSuspended(false), but short enough
        // that we don't fight a user-intentional mute forever.
        var _bgRemutePollRetries = 0;

        function postMsg(obj) {
            try {
                var cb = window.__nativeYTCallback;
                if (cb) cb.postMessage(JSON.stringify(obj));
            } catch(e) {}
        }

        // Page Visibility API — fires when the app backgrounds (hidden=true) or
        // returns to foreground (hidden=false). Used to distinguish iOS background
        // re-muting from a user-intentional mute: if video.muted flips to true
        // within a poll or two of becoming hidden, it's the OS, not the user.
        //
        // Also: when the WKWebView becomes visible again, iOS often leaves the
        // <video> element paused (the WKWebView was hidden briefly during
        // XCUITest's UI query or system events; iOS pauses HTML5 video on view
        // hide and doesn't auto-resume). We call video.play() on the
        // visible transition to recover — without this, the video stays
        // stuck in buffering state=3 at t=0 and `timeadvanced` never fires,
        // which breaks TOSPlayerIOSUITests.testTOSPlayerIOSSmoke's strict
        // "video is actually playing" assertion. The play() is silent
        // (catch-swallowed) because iOS may reject the call if no user
        // gesture has been seen for several minutes — that's fine, the
        // user will be tapping the screen and play() will work then.
        document.addEventListener('visibilitychange', function() {
            if (document.hidden) {
                _wasHidden = true;
                postMsg({type: 'pageHidden'});
            } else {
                postMsg({type: 'pageVisible', wasHidden: _wasHidden});
                // Page just became visible — reset the play-attempt counter so the
                // poll loop's uncapped play() retries have a fresh budget. The cap
                // was already removed (the test simulator's cover-present animation
                // routinely takes >5s to finish), but resetting the counter here
                // also ensures we don't keep trying to play forever after the page
                // stabilised in a paused state.
                _playAttempts = 0;
                var v = document.querySelector('video');
                if (v && v.paused) {
                    var p = v.play();
                    if (p && p['catch']) { p['catch'](function() {}); }
                }
            }
        }, false);

        // Watch for YouTube's error overlay appearing in the DOM. This fires when
        // the player shows "Error 153 - Video player configuration error" (or similar)
        // instead of loading the video. MutationObserver is used so the check runs
        // asynchronously on DOM changes, not inside the pollVideo hot-path.
        var _errorReported = false;
        function checkErrorOverlay(node) {
            if (_errorReported) return;
            var errEl = node.nodeType === 1 && (
                (node.classList && node.classList.contains('ytp-error')) ||
                node.querySelector && node.querySelector('.ytp-error')
            );
            if (!errEl) return;
            _errorReported = true;
            var txt = (typeof errEl === 'object' ? (errEl.textContent || '') : (node.textContent || ''));
            var m = txt.match(/Error\\s+(\\d+)/i);
            postMsg({type: 'error', code: m ? parseInt(m[1], 10) : 153, text: txt.trim().substring(0, 200)});
        }
        var _observer = new MutationObserver(function(mutations) {
            for (var i = 0; i < mutations.length; i++) {
                var added = mutations[i].addedNodes;
                for (var j = 0; j < added.length; j++) { checkErrorOverlay(added[j]); }
            }
        });
        _observer.observe(document.documentElement, {childList: true, subtree: true});

        function pollVideo() {
            var video = document.querySelector('video');
            if (!video) return;

            // video.paused can flicker true→false within a single poll interval right
            // after a resume (confirmed via live device log on the Shorts copy of this
            // poll — see ShortsEmbedJS.swift's stateDetectionJS for the full story).
            // Debounce: only commit to the paused state on the 2nd consecutive poll
            // observing it after a playing state, so a transient blip doesn't get
            // broadcast as a real pause. Already-paused readings (and ended) report
            // immediately.
            var rawPaused = video.paused;
            var s;
            if (video.ended) {
                s = 0;
                _pausedCandidate = false;
            } else if (rawPaused) {
                var wasActivelyPlaying = (_prevState === 1 || _prevState === 3);
                if (wasActivelyPlaying && !_pausedCandidate) {
                    _pausedCandidate = true;
                    s = _prevState;
                } else {
                    s = 2;
                }
            } else {
                _pausedCandidate = false;
                s = (video.readyState >= 3) ? 1 : 3;
            }

            var t = video.currentTime || 0;

            if (_prevState === -2) {
                _prevState = s;
                postMsg({type: 'ready', duration: video.duration || 0,
                         readyState: video.readyState, buffered: video.buffered.length});
            }

            // Kick off playback if YouTube's own autoplay didn't fire (common in WKWebView).
            // Retry every poll, no cap — when the WKWebView finally becomes visible
            // (cover-present animation completes, app returns from background, etc.)
            // the next play() will succeed. The 20-poll cap that used to be here was
            // removed because the test simulator's cover-present animation can take
            // >5s on the first run, leaving the page hidden long enough to exhaust
            // the old cap and leave the video stuck at t=0 indefinitely.
            if (video.paused && t === 0) {
                _playAttempts++;
                video.muted = true;
                var p = video.play();
                if (p && p['catch']) { p['catch'](function() {}); }
            }

            // Auto-unmute once playback is CONFIRMED actively progressing. Loading
            // muted (URL's mute=1 + the video.muted=true nudge above) exists solely
            // to satisfy WebKit's autoplay policy — autoplay is only ever guaranteed
            // to fire unmuted after a recent user gesture, so a muted start is the
            // only reliable way to avoid landing on a frozen first frame. Once we can
            // SEE forward progress (t advancing past startup), drop the mute exactly
            // once. Gated by _autoUnmuted so a later user-initiated mute (via
            // YouTube's own controls=1 chrome) is never fought/overridden.
            //
            // Both video.muted AND #movie_player.unMute() are needed: YouTube's
            // player object keeps its own internal mute flag (seeded true from the
            // mute=1 URL param) and periodically re-applies it onto video.muted,
            // undoing a DOM-only override ~250ms later. unMute() updates that
            // internal flag directly.
            if (!_autoUnmuted && !video.paused && t > 0.1) {
                _autoUnmuted = true;
                video.muted = false;
                var ytPlayer = document.getElementById('movie_player');
                if (ytPlayer && typeof ytPlayer.unMute === 'function') { ytPlayer.unMute(); }
                postMsg({type: 'autoUnmuted', t: t, muted: video.muted});
            }

            // Track video.muted transitions. When we see false→true AFTER _autoUnmuted
            // and the page was recently hidden, iOS re-muted the video during background.
            // Start the retry cycle to fight it from inside the iframe (correct frame,
            // always has access to movie_player) rather than from a Swift eval.
            if (_prevMuted !== null && video.muted !== _prevMuted) {
                if (video.muted && _autoUnmuted && _wasHidden) {
                    // iOS re-muted after background — arm the retry loop.
                    _wasHidden = false;
                    _bgRemutePollRetries = 12;
                    postMsg({type: 'bgRemute', t: t, retriesArmed: _bgRemutePollRetries});
                } else if (video.muted && _autoUnmuted) {
                    // Muted without a preceding background event — treat as user action.
                    postMsg({type: 'userMute', t: t});
                }
                postMsg({type: 'muteChange', muted: video.muted, t: t, prevMuted: _prevMuted});
            }
            _prevMuted = video.muted;

            // Self-healing unmute: re-apply every poll tick until the counter runs out.
            // Runs entirely inside the iframe's document so movie_player is always
            // reachable — no embedFrameInfo needed, no cross-origin issues.
            if (_bgRemutePollRetries > 0) {
                _bgRemutePollRetries--;
                video.muted = false;
                var ytp = document.getElementById('movie_player');
                if (ytp && typeof ytp.unMute === 'function') { ytp.unMute(); }
                postMsg({type: 'pollUnmuted', t: t, retriesLeft: _bgRemutePollRetries, muted: video.muted});
            }

            postMsg({type: 'tick', t: t, state: s, duration: video.duration || 0});

            if (s !== _prevState) {
                _prevState = s;
                postMsg({type: 'stateChange', state: s});
            }
        }

        setInterval(pollVideo, 250);
    })();
    """
}

// MARK: - TOSNavigationDelegate

/// Separate NSObject navigation delegate to ensure Objective-C dispatch works correctly
/// when the view model is a `@MainActor @Observable` actor-isolated class.
/// WKWebView holds a weak reference — TOSPlayerViewModel retains this strongly.
private final class TOSNavigationDelegate: NSObject, WKNavigationDelegate {

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Post navfinished at didCommit (document committed, before resources load).
        // Using didFinish would delay the notification until all subframes (including
        // the YouTube iframe) have loaded, but with iframe wrapping the iframe often
        // finishes after an error fires and the navigation is cancelled. didCommit
        // fires as soon as the main document is ready — reliable for the test gate.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.void.smarttube.tosplayer.navfinished" as CFString),
            nil, nil, true
        )
        tosLog.notice("[nav] navigation committed (navfinished posted)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tosLog.notice("[nav] navigation finished")
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        tosLog.error("[nav] provisional navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tosLog.error("[nav] navigation failed: \(error)")
    }
}

// MARK: - ScriptMessageProxy

/// Breaks the retain cycle: `WKUserContentController` retains its handlers strongly.
/// This proxy holds a `weak` reference to the real handler target so
/// `TOSPlayerViewModel` is not kept alive by the web view's content controller.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    weak var target: TOSPlayerViewModel?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? String else { return }
        // `message.frameInfo` is the missing link for fixing play/seekTo/setPlaybackRate
        // (see `embedFrameInfo`'s doc comment) — it identifies exactly which frame this
        // message originated from, including the cross-origin YouTube embed iframe.
        //
        // We thread it through via `MainActor.assumeIsolated` rather than the previous
        // `Task { @MainActor in ... }` hop: WKScriptMessageHandler delivery is
        // documented by Apple to always occur on the main thread, so `assumeIsolated`
        // safely asserts that and calls straight into the @MainActor view model with
        // NO actor-boundary crossing. That matters because `WKFrameInfo` is a non-Sendable
        // Objective-C type — capturing it in the `@Sendable` closure a `Task { @MainActor
        // in ... }` requires is a Swift 6 concurrency error, whereas `assumeIsolated`'s
        // closure is plain `@MainActor`-isolated (no Sendable requirement at all).
        let frameInfo = message.frameInfo
        MainActor.assumeIsolated { [weak target] in
            target?.handleScriptMessage(body, frameInfo: frameInfo)
        }
    }
}

#endif // !os(tvOS)
