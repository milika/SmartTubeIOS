import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - SwipeGestureOverlay

#if os(iOS)
/// A transparent UIKit view whose pan/tap gesture recognizers are mirrored onto
/// the window, so they fire *alongside* — not instead of — touches delivered to
/// the WKWebView below. This lets YouTube's native `controls=1` chrome (play/pause,
/// volume, CC, settings gear, etc.) remain tappable while swipe up/down still
/// drives Shorts navigation and a tap still toggles `shortsOverlay`.
///
/// - `hitTest` always returns `nil`, so this view itself never intercepts a
///   touch — the WKWebView underneath becomes the hit-tested view.
/// - `didMoveToWindow` re-homes the recognizers onto the window (an ancestor of
///   both this view and the WKWebView), which is required for them to receive
///   touches that hit-test to a sibling view.
/// - The `shouldRecognizeSimultaneouslyWith` delegate returns `true` so these
///   window-level recognizers don't block WKWebView's own touch handling.
/// - `require(toFail:)` keeps the tap from firing until a vertical pan is ruled out.
struct SwipeGestureOverlay: UIViewRepresentable {
    var onSwipeUp: () -> Void
    var onSwipeDown: () -> Void
    var onTap: (CGPoint) -> Void
    var onTwoFingerTap: () -> Void = {}
    var onPanChanged: ((CGFloat) -> Void)?
    var onSwipeCancelled: (() -> Void)?
    /// When set, replaces the fixed-distance `onSwipeUp`/`onSwipeDown` decision: called
    /// on release with the vertical translation and velocity (points/second) so the
    /// caller can decide by distance *and* flick speed (interactive paging).
    var onPanEnded: ((_ translation: CGFloat, _ velocity: CGFloat) -> Void)?
    /// When `false` (e.g. while a sheet is up) the window-level recognizers ignore
    /// every touch — they live on the window, so they'd otherwise see touches on
    /// sheets presented above the player too.
    var isEnabled: Bool = true
    /// Window-coordinate filter: return `false` for touches that belong to an
    /// overlay control (action rail, progress bar, tab bar…) so tapping or dragging
    /// it doesn't also toggle play/pause or swipe to another Short.
    var shouldHandleTouch: ((CGPoint) -> Bool)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PassthroughGestureView {
        let view = PassthroughGestureView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        tap.require(toFail: pan)

        let twoFingerTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.cancelsTouchesInView = false
        twoFingerTap.delegate = context.coordinator

        view.managedGestureRecognizers = [pan, tap, twoFingerTap]
        return view
    }

    func updateUIView(_ uiView: PassthroughGestureView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SwipeGestureOverlay
        private let minDistance: CGFloat = 40

        init(_ parent: SwipeGestureOverlay) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            MainActor.assumeIsolated {
                guard parent.isEnabled else { return false }
                return parent.shouldHandleTouch?(touch.location(in: nil)) ?? true
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @MainActor @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            let t = gr.translation(in: gr.view)
            switch gr.state {
            case .changed:
                parent.onPanChanged?(t.y)
            case .ended:
                if let onPanEnded = parent.onPanEnded {
                    // A mostly horizontal pan is not a page swipe.
                    guard abs(t.y) >= abs(t.x) else {
                        parent.onSwipeCancelled?()
                        return
                    }
                    onPanEnded(t.y, gr.velocity(in: gr.view).y)
                    return
                }
                guard abs(t.y) > minDistance, abs(t.y) > abs(t.x) else {
                    parent.onSwipeCancelled?()
                    return
                }
                if t.y < 0 { parent.onSwipeUp() } else { parent.onSwipeDown() }
            case .cancelled, .failed:
                parent.onSwipeCancelled?()
            default:
                break
            }
        }

        @MainActor @objc func handleTap(_ gr: UITapGestureRecognizer) {
            // location(in: nil) returns window coordinates, same space as
            // UIScreen.main.bounds — used by the caller to distinguish tap zones.
            parent.onTap(gr.location(in: nil))
        }
        @MainActor @objc func handleTwoFingerTap() { parent.onTwoFingerTap() }
    }
}

/// A fully click-through view: `hitTest` always returns `nil` so it never becomes
/// the hit-tested view, and its `managedGestureRecognizers` are moved onto the
/// window (rather than kept on this view) once it's installed, so they still
/// receive touches that hit-test to a sibling view below.
final class PassthroughGestureView: UIView {
    var managedGestureRecognizers: [UIGestureRecognizer] = []

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        for gr in managedGestureRecognizers {
            if let currentView = gr.view, currentView !== window {
                currentView.removeGestureRecognizer(gr)
            }
            if let window, gr.view !== window {
                window.addGestureRecognizer(gr)
            }
        }
    }
}
#endif
