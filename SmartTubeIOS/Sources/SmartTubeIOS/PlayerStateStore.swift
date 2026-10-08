#if os(iOS)
import AVFoundation
import UIKit
import Observation
import SmartTubeIOSCore
import OSLog

private let storeLog = Logger(subsystem: "com.void.smarttube.app", category: "PlayerStateStore")

// MARK: - PersistentPlayerHostView

/// A UIView that owns an AVPlayerLayer for the lifetime of the app.
/// Its reference lives in PlayerStateStore, so the layer — and the AVPlayer
/// connection — survive PlayerView dismiss/re-present cycles (mini-player).
///
/// Embed it as a subview in full-screen and mini-player contexts.
/// UIView.addSubview automatically removes it from the previous parent,
/// so no explicit removeFromSuperview is needed when transplanting.
final class PersistentPlayerHostView: UIView {

    let playerLayer = AVPlayerLayer()

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - PlayerStateStore

/// Centralised iOS playback state for the in-app mini-player.
///
/// Owns the single `PlaybackViewModel` and `PersistentPlayerHostView` so they
/// survive PlayerView presentation/dismiss cycles. Injected as an environment
/// object at the `AppEntry` level; accessed via `@Environment(PlayerStateStore.self)`.
@MainActor
@Observable
public final class PlayerStateStore {

    // MARK: - Presentation state

    public enum Presentation: Equatable {
        case hidden
        case miniPlayer
        case fullScreen
    }

    public private(set) var presentation: Presentation = .hidden

    /// The video that is currently loaded or playing. Non-nil when presentation != .hidden.
    private(set) var currentVideo: Video? = nil

    /// The video whose frames the AVPlayer is actually rendering.
    ///
    /// During a load (`vm.isLoading == true`), `currentVideo` has already been updated to
    /// the newly selected video but `AVPlayerItem` may not be ready yet — the player layer
    /// is still showing the previous video's frames. `playingVideo` resolves this by
    /// returning the last-confirmed playing video while the new one is loading, so the
    /// MiniPlayer label stays in sync with the visual content.
    ///
    /// - When idle (`isLoading == false`): equals `currentVideo`.
    /// - When loading (`isLoading == true`) and there is a previous video: equals that
    ///   video (last entry in `vm.history` — pushed onto the stack just before the new
    ///   video starts loading).
    /// - When loading the very first video ever (history is empty): returns `nil` (the
    ///   MiniPlayer is hidden during a first-play full-screen open, so this is harmless).
    var playingVideo: Video? {
        vm.isLoading ? vm.history.last : currentVideo
    }

    // MARK: - Imperative dismiss hook

    /// Set by LandscapePresenter's coordinator when a full-screen player is presented.
    /// Fired imperatively by minimize() / stop() to bypass the SwiftUI update-propagation
    /// pause that occurs when the presenting VC's view is removed from the window by
    /// UIKit's .fullScreen presentation style (so updateUIViewController never fires).
    var dismissPlayerAction: (() -> Void)?

    // MARK: - Owned objects

    /// The single PlaybackViewModel for the app. Lives for the app's lifetime.
    public let vm: PlaybackViewModel

    /// The UIView that owns the AVPlayerLayer. Never deallocated; transplanted
    /// between full-screen and mini-player containers via UIView.addSubview.
    let playerHostView: PersistentPlayerHostView

    // MARK: - Init

    public init(api: InnerTubeAPI) {
        let vm = PlaybackViewModel(api: api)
        self.vm = vm
        let hostView = PersistentPlayerHostView()
        hostView.playerLayer.player = vm.player
        self.playerHostView = hostView
    }

    // MARK: - Actions

    /// Load `video` (if not already loaded) and present the full-screen player.
    public func play(video: Video) {
        storeLog.notice(
            "[PlayerStateStore] play — id=\(video.id) currentPresentation=\(String(describing: self.presentation))")
        // Stamp intended_video_id immediately — before load() runs and before the
        // breadcrumb buffer can fill. Comparing with active_video_id in a report
        // reveals prefetch-race / wrong-card-tap scenarios.
        CrashlyticsLogger.setIntendedVideo(id: video.id, title: video.title)
        // Also reload when:
        //   1. Different video — always load
        //   2. No current item — item was cleared by stop() (legacy path)
        //   3. Not playing — item is parked (fix12 park path): stop() keeps the
        //      AVPlayerItem alive but pauses and sets isPlaying=false. On re-tap,
        //      call load() so the park fast-path in PlaybackViewModel resumes it.
        if vm.currentVideoId != video.id || vm.player.currentItem == nil || !vm.isPlaying {
            vm.load(video: video)
        }
        currentVideo = video
        presentation = .fullScreen
        storeLog.notice("[PlayerStateStore] play — presentation set to .fullScreen")
    }

    /// Collapse the full-screen player to the mini-player bar. Playback continues.
    public func minimize() {
        storeLog.notice("[PlayerStateStore] minimize — currentPresentation=\(String(describing: self.presentation))")
        presentation = .miniPlayer
        let action = dismissPlayerAction
        dismissPlayerAction = nil
        storeLog.notice(
            "[PlayerStateStore] minimize — presentation set to .miniPlayer, dismissPlayerAction=\(action != nil)")
        action?()
    }

    /// Expand the mini-player back to full-screen.
    func expand() {
        storeLog.notice("[PlayerStateStore] expand — currentPresentation=\(String(describing: self.presentation))")
        presentation = .fullScreen
        storeLog.notice("[PlayerStateStore] expand — presentation set to .fullScreen")
    }

    /// Stop playback completely and hide the player UI.
    func stop() {
        storeLog.notice("[PlayerStateStore] stop — currentPresentation=\(String(describing: self.presentation))")
        vm.stop()
        currentVideo = nil
        presentation = .hidden
        let action = dismissPlayerAction
        dismissPlayerAction = nil
        storeLog.notice("[PlayerStateStore] stop — presentation set to .hidden, dismissPlayerAction=\(action != nil)")
        action?()
    }
}
#endif
