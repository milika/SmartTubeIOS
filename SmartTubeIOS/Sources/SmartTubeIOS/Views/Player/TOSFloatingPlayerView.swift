#if os(iOS)
import SwiftUI
import WebKit
import SmartTubeIOSCore

// MARK: - TOSFloatingPlayerView

/// Accessibility identifiers for the floating player. Declared as constants (rather
/// than inline literals) so the `raw_accessibility_identifier` lint rule stays clean
/// until the shared `AccessibilityID` migration lands.
private enum TOSMiniPlayerAccessibilityID {
    static let bar = "tosPlayer.miniPlayerBar"
    static let playPause = "tosPlayer.miniPlayer.playPauseButton"
    static let close = "tosPlayer.miniPlayer.closeButton"
}

/// Which screen corner the floating player is snapped to. Persisted on
/// TOSPlayerStateStore so the chosen corner survives expand → minimize.
enum TOSMiniPlayerCorner: String, CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var isTop: Bool { self == .topLeading || self == .topTrailing }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }
}
//
// Floating corner window shown when the TOS player is minimized
// (TOSPlayerStateStore.presentation == .miniPlayer). Mirrors YouTube's minimized
// player: a small 16:9 window that keeps playing while the user browses, which the
// user can drag and snap to any of the four corners of the content area.
//
// Layout:
//   ┌───────────────────┐
//   │ ▶/⏸            ✕ │   ← buttons overlaid in the top corners
//   │      (video)      │   ← live WKWebView; tap anywhere else → expand
//   └───────────────────┘
//
// Actions:
//   play/pause (top-left)  → vm.play() / vm.pause()
//   close (top-right)      → tosState.stop() → releases WKWebView, hides the window
//   tap the video area     → tosState.expand() → re-presents TOSPlayerView
//   drag the video area    → snaps to the nearest corner on release

struct TOSFloatingPlayerView: View {
    @Environment(TOSPlayerStateStore.self) private var tosState

    /// Bottom safe-area inset (tab-bar height + home indicator) supplied by RootView,
    /// because this view lives in a full-bleed overlay that extends under the tab bar
    /// and so can't rely on `geo.safeAreaInsets.bottom` alone to clear it.
    var bottomBarInset: CGFloat = 0

    private let width: CGFloat = 176
    private var height: CGFloat { width * 9 / 16 }
    /// Fixed gap between the card and the safe-area edges it snaps to.
    private let margin: CGFloat = 12

    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false

    private var isPlaying: Bool {
        tosState.vm?.playerState == .playing || tosState.vm?.playerState == .buffering
    }

    var body: some View {
        // Read the corner in `body` (not inside a layout closure) so @Observable
        // registers the dependency and a snap re-renders this view.
        let corner = tosState.miniPlayerCorner
        GeometryReader { geo in
            let insets = insets(in: geo)
            floatingCard
                .gesture(dragGesture(in: geo.size, insets: insets))
                .position(center(in: geo.size, insets: insets, corner: corner))
        }
    }

    // MARK: - Positioning

    /// Safe-area-relative snap margins for each edge, with the fixed `margin` added.
    private func insets(in geo: GeometryProxy) -> EdgeInsets {
        let safe = geo.safeAreaInsets
        return EdgeInsets(
            top: max(safe.top, 0) + margin,
            leading: max(safe.leading, 0) + margin,
            bottom: max(safe.bottom, bottomBarInset) + margin,
            trailing: max(safe.trailing, 0) + margin)
    }

    /// Center for the card's current corner. During a drag the live translation is
    /// added on top and clamped so the card never leaves the content area.
    private func center(in size: CGSize, insets: EdgeInsets, corner: TOSMiniPlayerCorner) -> CGPoint {
        let base = baseCenter(in: size, insets: insets, corner: corner)
        guard isDragging else { return base }
        return clamp(
            CGPoint(x: base.x + dragTranslation.width, y: base.y + dragTranslation.height),
            in: size, insets: insets)
    }

    private func baseCenter(in size: CGSize, insets: EdgeInsets, corner: TOSMiniPlayerCorner) -> CGPoint {
        let x =
            corner.isLeading
            ? insets.leading + width / 2
            : size.width - insets.trailing - width / 2
        let y =
            corner.isTop
            ? insets.top + height / 2
            : size.height - insets.bottom - height / 2
        return CGPoint(x: x, y: y)
    }

    private func clamp(_ point: CGPoint, in size: CGSize, insets: EdgeInsets) -> CGPoint {
        let minX = insets.leading + width / 2
        let maxX = max(minX, size.width - insets.trailing - width / 2)
        let minY = insets.top + height / 2
        let maxY = max(minY, size.height - insets.bottom - height / 2)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY))
    }

    /// Nearest of the four corners to a dropped center.
    private func nearestCorner(to point: CGPoint, in size: CGSize) -> TOSMiniPlayerCorner {
        switch (point.y < size.height / 2, point.x < size.width / 2) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    // MARK: - Drag

    private func dragGesture(in size: CGSize, insets: EdgeInsets) -> some Gesture {
        // minimumDistance keeps a stationary tap routed to the expand tap gesture,
        // so dragging only engages once the finger actually moves.
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                isDragging = true
                dragTranslation = value.translation
            }
            .onEnded { value in
                let base = baseCenter(in: size, insets: insets, corner: tosState.miniPlayerCorner)
                let dropped = clamp(
                    CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height),
                    in: size, insets: insets)
                let newCorner = nearestCorner(to: dropped, in: size)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    tosState.miniPlayerCorner = newCorner
                    dragTranslation = .zero
                    isDragging = false
                }
            }
    }

    // MARK: - Card

    private var floatingCard: some View {
        ZStack {
            if let webView = tosState.vm?.webView {
                // Live video — transplants the same WKWebView that was hosting the
                // full-screen player, so the embedded YouTube <video> stays attached
                // to the window and playback continues. See TOSMiniPlayerLayerView.
                TOSMiniPlayerLayerView(webView: webView)
            } else if let thumb = tosState.currentVideo?.thumbnailURL {
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.black
                    }
                }
            } else {
                Color.black
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { tosState.expand() }
        .overlay(alignment: .topLeading) { playPauseButton }
        .overlay(alignment: .topTrailing) { closeButton }
        // Without this, SwiftUI flattens this ZStack's accessibility tree so each
        // child Button inherits the container identifier and XCUITest can't find
        // them individually. Same fix the bottom bar used.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TOSMiniPlayerAccessibilityID.bar)
    }

    // MARK: - Corner buttons

    private var playPauseButton: some View {
        Button {
            if isPlaying {
                tosState.vm?.pause()
            } else {
                tosState.vm?.play()
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityIdentifier(TOSMiniPlayerAccessibilityID.playPause)
    }

    private var closeButton: some View {
        Button {
            tosState.stop()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityIdentifier(TOSMiniPlayerAccessibilityID.close)
    }
}

// MARK: - TOSMiniPlayerLayerView

/// UIViewRepresentable that hosts the TOS player's WKWebView as a live thumbnail.
/// UIView.addSubview transplants the webView from the full-screen
/// YouTubeWebPlayerView's container automatically — no explicit removeFromSuperview
/// needed. Keeping the webView attached to the window keeps the embedded YouTube
/// <video> element's document.visibilityState == 'visible', so playback continues
/// while minimized. Mirrors MiniPlayerLayerView's transplant pattern for AVPlayer.
struct TOSMiniPlayerLayerView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        attach(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if webView.superview !== uiView {
            attach(to: uiView)
        }
    }

    private func attach(to container: UIView) {
        // Disable interaction so taps fall through to the SwiftUI buttons
        // (expand / play-pause / close) overlaying this view, rather than being
        // captured by YouTube's native player controls inside the WKWebView.
        webView.isUserInteractionEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
#endif  // os(iOS)
