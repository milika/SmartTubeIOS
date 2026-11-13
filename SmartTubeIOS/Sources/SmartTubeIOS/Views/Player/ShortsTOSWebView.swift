#if os(iOS)
import SwiftUI
import WebKit

/// Hosts the persistent `WKWebView` owned by a `ShortsEmbedPlayerViewModel` inside the
/// SwiftUI view hierarchy. Each `ShortsPlayerPool` slot gets one of these for its
/// whole life (one WKWebView reused across many `loadShort(video:live:)` calls); this
/// representable just attaches it to the container view with Auto Layout constraints.
struct ShortsTOSWebView: UIViewRepresentable {
    let vm: ShortsEmbedPlayerViewModel

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if vm.webView.superview !== uiView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            attach(to: uiView)
        }
    }

    private func attach(to container: UIView) {
        let webView = vm.webView
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Every gesture on a Short is handled by SwipeGestureOverlay's window-level
        // recognizers. If the embed also got the touch, a quick tap became a click on
        // YouTube's player, which toggles playback itself: our pause landed, then the
        // click resumed the video a moment later (a long press made no click, so only
        // a long press paused).
        webView.isUserInteractionEnabled = false
        container.isUserInteractionEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        // Fill the container exactly, like the poster that covers it while loading.
        // Pinning to the safe area instead pushed the video below the status bar in
        // the Shorts tab, so it jumped when the poster faded out.
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
#endif
