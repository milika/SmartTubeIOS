#if os(iOS)
import Foundation
import SwiftUI
import SmartTubeIOSCore
import os

private let tosStoreLog = Logger(subsystem: "com.void.smarttube.app", category: "TOSPlayerStateStore")

// MARK: - TOSPlayerStateStore
//
// iOS equivalent of PlayerStateStore, but for the WKWebView-backed TOS player.
// Owns TOSPlayerViewModel (and its WKWebView) so it survives TOSPlayerView
// dismiss/re-present cycles — enabling mini-player audio continuity.
//
// Presentation state:
//   .hidden     — no video loaded, WKWebView released
//   .miniPlayer — audio continues in TOSMiniPlayerView, TOSPlayerView dismissed
//   .fullScreen — TOSPlayerView presented as a full-screen cover
//
// Lifecycle:
//   play(video:api:)  → create/reload vm, set .fullScreen
//   minimize()        → set .miniPlayer (vm/WKWebView kept alive, audio continues)
//   expand()          → set .fullScreen (re-present TOSPlayerView)
//   stop()            → vm.pause() + vm.saveProgress(), release vm, set .hidden

@MainActor
@Observable
public final class TOSPlayerStateStore {

    // MARK: - Presentation state

    public enum Presentation: Equatable {
        case hidden
        case miniPlayer
        case fullScreen
    }

    public private(set) var presentation: Presentation = .hidden

    /// The video currently loaded or playing. Non-nil when presentation != .hidden.
    public private(set) var currentVideo: Video?

    // MARK: - Per-video fallback guard
    //
    // When the embed fires a fatal error (embeddingDisabled / notFound), we mark that
    // videoId so the next play() call routes to AVPlayer instead of TOS again.
    // Cleared when a different video is opened.
    public private(set) var fallbackVideoId: String?

    // MARK: - Owned view model
    //
    // Optional — nil when presentation == .hidden (WKWebView released).
    // The view model lives here, not in TOSPlayerView's @State, so the WKWebView
    // keeps running after the view is dismissed to mini-player.
    // Internal (not public) because TOSPlayerViewModel is an internal type;
    // all consumers (TOSPlayerView, TOSMiniPlayerView) are in the same module.
    private(set) var vm: TOSPlayerViewModel?

    // MARK: - Navigation history (swipe-right / "previous")
    //
    // Pushed in play(video:api:) whenever a *different* video is opened while one
    // is already loaded. popHistory() is used by TOSPlayerView's onPlayPrevious
    // wiring to re-play the prior video on swipe-right. Capped at 20 entries so
    // Video objects don't accumulate without bound across a long swipe session.
    private static let maxHistoryDepth = 20
    private(set) var history: [Video] = []

    // MARK: - Seen video IDs (loop prevention)
    //
    // Accumulates the ID of every video played in this session. Passed to each
    // new TOSPlayerViewModel so its fetchRelatedVideos() can filter them out —
    // prevents the same video from cycling back on repeated swipes.
    private var seenVideoIds: Set<String> = []

    // MARK: - Imperative dismiss hook

    /// Set by LandscapePresenter's coordinator when the TOS full-screen player is
    /// presented. Fired imperatively by minimize() / stop() to bypass the SwiftUI
    /// update-propagation pause that occurs when the presenting VC's view is removed
    /// from the window by UIKit's .fullScreen presentation style (so
    /// updateUIViewController never fires while the cover is on screen). Mirrors
    /// PlayerStateStore.dismissPlayerAction — see FullScreenPlayerDismissible.
    var dismissPlayerAction: (() -> Void)?

    // MARK: - Init

    public init() {
        // Test-only: listen for the "takesnapshot" Darwin notification so
        // XCUITest can ask the running app to capture the WKWebView's
        // rendered content and write it to a known file path. The test
        // simulator's WKWebView is in a hidden state when the inline
        // presentation path is used (the SwiftUI `.overlay` puts the
        // WKWebView in a layer that iOS marks `document.hidden=true`),
        // so `XCUIScreen.main.screenshot()` returns a black image.
        // `webView.takeSnapshot` bypasses view visibility — it captures
        // the actual rendered web content. The test posts
        // `com.void.smarttube.tosplayer.takesnapshot`, waits for
        // `com.void.smarttube.tosplayer.snapshot.taken` (posted by
        // `TOSPlayerViewModel.takeSnapshot`), then reads the file.
        Self.installSnapshotListener()
    }

    /// One-time (per app launch) install of the Darwin notification observer
    /// for the test-only takesnapshot path. Idempotent.
    private static var hasInstalledSnapshotListener = false
    private static func installSnapshotListener() {
        guard !hasInstalledSnapshotListener else { return }
        hasInstalledSnapshotListener = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        // Use a sentinel object as the observer — the actual work happens
        // by reading `TOSPlayerStateStore.activeStore` (set on play()), so
        // we don't need to keep a strong reference to any particular store.
        let observer = Unmanaged.passRetained(SnapshotObserver()).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { (_, _, name, _, _) in
                let path = "/tmp/smarttube-logs/tos_snapshot.png"
                if let vm = TOSPlayerStateStore.activeStore?.vm {
                    tosStoreLog.notice("[snapshot] takesnapshot received — capturing to \(path, privacy: .public)")
                    vm.takeSnapshot(to: path)
                } else {
                    tosStoreLog.notice("[snapshot] takesnapshot received but no active vm — posting snapshot.taken anyway")
                    CFNotificationCenterPostNotification(
                        CFNotificationCenterGetDarwinNotifyCenter(),
                        CFNotificationName("com.void.smarttube.tosplayer.snapshot.taken" as CFString),
                        nil, nil, true
                    )
                }
            },
            "com.void.smarttube.tosplayer.takesnapshot" as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Tracks the most-recently-active TOSPlayerStateStore so the snapshot
    /// observer (a global singleton) can find the current vm. Multiple stores
    /// could exist in theory (tests / multi-window), but in practice the app
    /// has a single one in the environment.
    fileprivate static var activeStore: TOSPlayerStateStore?
    private func setActive() { Self.activeStore = self }
    private func setInactive() {
        if Self.activeStore === self { Self.activeStore = nil }
    }

    // MARK: - Actions

    /// Load `video` and present the TOS player full-screen.
    /// If the same video is already loaded and playing, just expands.
    public func play(video: Video, api: InnerTubeAPI) {
        tosStoreLog.notice("[TOSPlayerStateStore] play — id=\(video.id) currentPresentation=\(String(describing: self.presentation))")

        if vm?.videoId == video.id, presentation == .miniPlayer {
            // Same video minimized — just re-expand.
            expand()
            return
        }

        // Stop and release any previous session.
        let replacesOnScreenPlayer = vm != nil && presentation == .fullScreen
        if let existingVM = vm {
            existingVM.pause()
            existingVM.saveProgress()
        }

        // Push the outgoing video onto the navigation history so swipe-right
        // (playPrevious) can return to it. FIFO-evict when the cap is reached.
        if let current = currentVideo, current.id != video.id {
            if history.count >= Self.maxHistoryDepth { history.removeFirst() }
            history.append(current)
        }

        // Clear fallback guard when opening a new video.
        if fallbackVideoId != video.id {
            fallbackVideoId = nil
        }

        seenVideoIds.insert(video.id)
        let newVM = TOSPlayerViewModel(videoId: video.id, title: video.title, channelId: video.channelId, channelTitle: video.channelTitle, thumbnailURL: video.thumbnailURL, playlistId: video.playlistId, playlistIndex: video.playlistIndex, startTime: 0, api: api)
        newVM.seenVideoIds = seenVideoIds
        newVM.setNavigationContext(hasPrevious: !history.isEmpty)
        // Wire swipe-navigation callbacks here (not in TOSPlayerView.onAppear) so
        // every vm created by a swipe-driven play() — not just the first — gets
        // working onPlayNext/onPlayPrevious. SwiftUI's .onAppear fires once per
        // view identity and does not re-run when tosState.vm is swapped out from
        // under an already-presented TOSPlayerView, so re-wiring only on initial
        // appearance would leave the second-and-later vm's callbacks nil.
        // [weak self] avoids a retain cycle: self -> vm -> closure -> self.
        newVM.onPlayNext = { [weak self] next in
            self?.play(video: next, api: api)
        }
        newVM.onPlayPrevious = { [weak self] in
            guard let prev = self?.popHistory() else { return }
            self?.play(video: prev, api: api)
        }
        self.vm = newVM
        self.currentVideo = video
        self.presentation = .fullScreen
        setActive()
        tosStoreLog.notice("[TOSPlayerStateStore] play — presentation set to .fullScreen, vm created for \(video.id)")
        // When swipe navigation creates a new vm while the fullscreen player is
        // already on screen, the cover is not re-presented, so the window-ready
        // callback in YouTubeWebPlayerView — the normal trigger for the IFrame
        // load — never fires for the new vm. Start the load here: updateUIView
        // attaches the new web view well within the load delay. First open keeps
        // the window-ready path.
        if replacesOnScreenPlayer {
            newVM.startIfNeededWhenWindowReady()
        }
    }

    /// Pops and returns the most recent video from the swipe-navigation history,
    /// or `nil` if there is none. Used by TOSPlayerView's onPlayPrevious wiring.
    func popHistory() -> Video? {
        history.isEmpty ? nil : history.removeLast()
    }

    /// Collapse the full-screen player to the mini-player bar.
    /// The WKWebView keeps running — audio continues.
    public func minimize() {
        tosStoreLog.notice("[TOSPlayerStateStore] minimize — currentPresentation=\(String(describing: self.presentation))")
        guard presentation == .fullScreen else { return }
        let wasActive = vm?.playerState == .playing || vm?.playerState == .buffering
        presentation = .miniPlayer
        let action = dismissPlayerAction
        dismissPlayerAction = nil
        tosStoreLog.notice("[TOSPlayerStateStore] minimize — presentation set to .miniPlayer, dismissPlayerAction=\(action != nil)")
        action?()

        // Defense-in-depth: TOSMiniPlayerLayerView transplants the WKWebView into the
        // mini-player container so the embedded <video> stays attached to the window
        // (visibilityState remains 'visible'). But a brief detach can still occur during
        // the SwiftUI/UIKit transition, which pauses the embedded YouTube player. If
        // playback was active before minimizing and hasn't resumed shortly after,
        // explicitly resume it.
        guard wasActive else { return }
        let resumeVM = vm
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.presentation == .miniPlayer, self.vm === resumeVM else { return }
            let state = resumeVM?.playerState
            if state != .playing, state != .buffering {
                tosStoreLog.notice("[TOSPlayerStateStore] minimize — playback did not resume (state=\(String(describing: state))), calling vm.play()")
                resumeVM?.play()
            }
        }
    }

    /// Expand the mini-player back to full-screen.
    public func expand() {
        tosStoreLog.notice("[TOSPlayerStateStore] expand — currentPresentation=\(String(describing: self.presentation))")
        guard presentation == .miniPlayer else { return }
        presentation = .fullScreen
        tosStoreLog.notice("[TOSPlayerStateStore] expand — presentation set to .fullScreen")
    }

    /// Stop playback completely, release the WKWebView, and hide all player UI.
    public func stop() {
        tosStoreLog.notice("[TOSPlayerStateStore] stop — currentPresentation=\(String(describing: self.presentation))")
        vm?.pause()
        vm?.saveProgress()
        vm?.clearNowPlayingInfo()
        vm?.onPlayNext = nil
        vm?.onPlayPrevious = nil
        ExternalDisplayManager.shared.withdrawAll()
        vm = nil
        currentVideo = nil
        presentation = .hidden
        seenVideoIds = []
        setInactive()
        let action = dismissPlayerAction
        dismissPlayerAction = nil
        tosStoreLog.notice("[TOSPlayerStateStore] stop — presentation set to .hidden, vm released, dismissPlayerAction=\(action != nil)")
        action?()
    }

    /// Mark a video as requiring AVPlayer fallback (embedding disabled / not found).
    /// The next play() call for this videoId will be routed to AVPlayer by the caller.
    public func markFallback(videoId: String) {
        tosStoreLog.notice("[TOSPlayerStateStore] markFallback — videoId=\(videoId)")
        fallbackVideoId = videoId
    }
}

// MARK: - SnapshotObserver (test-only)
//
// Sentinel object that the Darwin notification observer holds a strong reference
// to (via `Unmanaged.passRetained`). The observer closure itself doesn't use
// the observer — it looks up the active TOSPlayerStateStore via the static
// `activeStore` property — but CFNotificationCenter requires a non-nil
// observer pointer to be passed to `CFNotificationCenterAddObserver`. Without
// this object, the observer pattern leaks / misbehaves.
private final class SnapshotObserver: NSObject {}

#endif // os(iOS)
