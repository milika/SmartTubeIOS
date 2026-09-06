#if os(iOS)
import UIKit
import Observation
import OSLog

private let externalDisplayLog = Logger(subsystem: "com.void.smarttube.app", category: "ExternalDisplay")

// MARK: - ExternalDisplayManager

/// Shows the TOS player's web view on a connected external screen (HDMI / USB-C).
///
/// iOS mirrors the device display by default, so the TV would get a scaled copy of the
/// phone UI. Apple's only supported way to put app content on that screen is a scene
/// with the `windowExternalDisplayNonInteractive` role plus a window of our own in it —
/// and the system falls back to mirroring whenever no such window is shown. That is
/// exactly the behaviour wanted here: mirror while browsing, take the screen over while
/// a video plays.
///
/// The `AVPlayer` pipeline needs none of this: it hands video to an external screen
/// natively via `usesExternalPlaybackWhileExternalScreenIsActive` (see
/// `PlaybackViewModel`). A `WKWebView` has no such facility, so its view is physically
/// moved into the external window — the same `addSubview` transplant the full-screen
/// and mini-player containers already do between themselves.
@MainActor
@Observable
public final class ExternalDisplayManager {

    public static let shared = ExternalDisplayManager()

    /// The view actually embedded in the external window right now — nil whenever no
    /// screen is attached, however much a player would like to hand one over. Observed,
    /// so SwiftUI containers re-evaluate and stop competing for a view that lives on
    /// the TV. Held strongly only while shown.
    public private(set) var presented: UIView?

    /// What the active player offers for the external screen, shown as soon as one
    /// appears. Separate from `presented`: playback runs with no screen attached most
    /// of the time.
    @ObservationIgnored private weak var offered: UIView?

    /// True while an external screen is attached, whatever is shown on it. Drives the
    /// player menu row that offers to move playback between phone and TV.
    public private(set) var isScreenConnected = false

    /// Cleared when the user asks for playback back on the phone; restored when the
    /// screen is unplugged, so the next connection behaves as expected. Drives the
    /// label of the player menu row.
    public private(set) var userWantsExternal = true

    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var idleTimerWasDisabled: Bool?

    /// UI-test seam. No simulator emulates an external screen, so
    /// `--uitesting-fake-external-display` connects the phone's own scene as if it
    /// were one; this frame keeps the stand-in window clear of the controls the test
    /// taps. Nil in production: the window fills the external scene.
    @ObservationIgnored public var uiTestWindowFrame: CGRect?

    private init() {}

    /// True when `view` is the one on the external screen. Containers ask before
    /// re-embedding it locally; the player asks before drawing a stand-in.
    public func owns(_ view: UIView) -> Bool { presented === view }

    // MARK: - Scene lifecycle

    public func sceneConnected(_ scene: UIWindowScene) {
        externalDisplayLog.notice("[ExternalDisplay] scene connected — screen=\(NSCoder.string(for: scene.screen.bounds), privacy: .public)")
        // A window built for an earlier scene cannot be moved to this one.
        if window != nil, window?.windowScene !== scene { teardownWindow() }
        self.scene = scene
        isScreenConnected = true
        updateWindow()
    }

    public func sceneDisconnected(_ scene: UIScene) {
        guard scene === self.scene else { return }
        externalDisplayLog.notice("[ExternalDisplay] scene disconnected")
        self.scene = nil
        isScreenConnected = false
        userWantsExternal = true
        updateWindow()
    }

    // MARK: - Content

    /// Offer `view` for the external screen, replacing whatever is offered. Shown at
    /// once if a screen is attached, otherwise as soon as one is.
    ///
    /// Called once playback is actually running: the YouTube IFrame fails its
    /// player-config check against a page that is not in a visible window, so a freshly
    /// created web view has to load on the phone first. That is also why a new video —
    /// which builds a new view model and a new web view — must take this screen over
    /// from its predecessor rather than find it occupied.
    public func offer(_ view: UIView) {
        guard offered !== view else { return }
        externalDisplayLog.notice("[ExternalDisplay] offer — \(String(describing: type(of: view)), privacy: .public)")
        offered = view
        updateWindow()
    }

    /// Take the offer back. Ignored unless `view` is the one offered, so a pipeline
    /// that has already been replaced cannot withdraw its successor.
    public func withdraw(_ view: UIView) {
        guard offered === view else { return }
        externalDisplayLog.notice("[ExternalDisplay] withdraw — \(String(describing: type(of: view)), privacy: .public)")
        offered = nil
        updateWindow()
    }

    /// Take back whatever is offered, whoever offered it. For the player being torn
    /// down: a successor that never reached playback would otherwise leave its
    /// predecessor's last frame on the screen with nobody left to withdraw it.
    public func withdrawAll() {
        guard offered != nil || presented != nil else { return }
        externalDisplayLog.notice("[ExternalDisplay] withdraw all")
        offered = nil
        updateWindow()
    }

    /// Move playback between the TV and the phone by hand. Survives a video change;
    /// unplugging the screen resets it.
    public func setUserWantsExternal(_ wanted: Bool) {
        guard userWantsExternal != wanted else { return }
        externalDisplayLog.notice("[ExternalDisplay] userWantsExternal=\(wanted, privacy: .public)")
        userWantsExternal = wanted
        updateWindow()
    }

    // MARK: - Window

    private func updateWindow() {
        guard let scene, userWantsExternal, let content = offered else {
            teardownWindow()
            return
        }
        let window = window ?? makeWindow(on: scene)
        guard let root = window.rootViewController else { return }
        guard content.superview !== root.view else { return }

        // A replaced view is held by nothing but this window; leaving it in place
        // would keep its web process alive for every video change until teardown.
        if let previous = presented, previous !== content {
            previous.removeFromSuperview()
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.view.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
        ])
        window.layoutIfNeeded()
        presented = content
        externalDisplayLog.notice("[ExternalDisplay] content shown — window=\(NSCoder.string(for: window.frame), privacy: .public) content=\(NSCoder.string(for: content.bounds), privacy: .public)")
    }

    private func makeWindow(on scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        // Track the scene rather than a snapshot of the screen bounds, so a display mode
        // change resizes the window with it.
        window.frame = uiTestWindowFrame ?? scene.coordinateSpace.bounds
        window.autoresizingMask = uiTestWindowFrame == nil ? [.flexibleWidth, .flexibleHeight] : []

        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        // Key for its own scene only — the phone's scene keeps its key window. WebKit
        // treats a web view in a window that is not key as hidden: media stays
        // paused on foreground and an unmute there never becomes audible. The
        // UI-test stand-in shares the phone's scene and must not take its key window.
        if uiTestWindowFrame == nil {
            window.makeKeyAndVisible()
        } else {
            window.isHidden = false
        }
        self.window = window

        // The phone shows only controls while video plays on the TV, so nothing would
        // stop the idle timer from locking the device mid-playback. Remember the value
        // the players set for themselves and put it back on teardown.
        idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        return window
    }

    private func teardownWindow() {
        if presented != nil { presented = nil }
        guard let window else { return }
        externalDisplayLog.notice("[ExternalDisplay] window torn down")
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
        self.window = nil
        if let previous = idleTimerWasDisabled {
            UIApplication.shared.isIdleTimerDisabled = previous
            idleTimerWasDisabled = nil
        }
    }
}
#endif
