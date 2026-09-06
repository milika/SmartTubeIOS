#if os(iOS)
import SwiftUI
import WebKit
import SmartTubeIOSCore

// MARK: - TOSMiniPlayerView
//
// Compact playback bar shown at the bottom of MainTabView when the TOS player
// has been minimized (TOSPlayerStateStore.presentation == .miniPlayer).
//
// Layout: [ ▶/⏸ ] [ thumbnail + title ] [ ✕ ]
//
// Actions:
//   play/pause button → vm.play() / vm.pause()
//   tap bar (thumbnail / title) → tosState.expand() → re-presents TOSPlayerView
//   ✕ button → tosState.stop() → releases WKWebView, hides mini-player

struct TOSMiniPlayerView: View {
    @Environment(TOSPlayerStateStore.self) private var tosState

    var body: some View {
        HStack(spacing: 0) {
            // Play / pause
            Button {
                if tosState.vm?.playerState == .playing || tosState.vm?.playerState == .buffering {
                    tosState.vm?.pause()
                } else {
                    tosState.vm?.play()
                }
            } label: {
                let isPlaying = tosState.vm?.playerState == .playing || tosState.vm?.playerState == .buffering
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 62)
            }
            .accessibilityIdentifier("tosPlayer.miniPlayer.playPauseButton")

            // Thumbnail + title → tap to expand
            Button {
                tosState.expand()
            } label: {
                HStack(spacing: 10) {
                    if let webView = tosState.vm?.webView {
                        // Live thumbnail — transplants the same WKWebView that was hosting
                        // the full-screen player, so the embedded YouTube <video> stays
                        // attached to the window (visibilityState remains 'visible') and
                        // playback continues. See TOSMiniPlayerLayerView below.
                        TOSMiniPlayerLayerView(
                            webView: webView,
                            externalDisplayOwnsWebView: ExternalDisplayManager.shared.owns(webView)
                        )
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .accessibilityHidden(true)
                    } else if let thumb = tosState.currentVideo?.thumbnailURL {
                        AsyncImage(url: thumb) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color.gray.opacity(0.3)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 46, height: 46)
                    }

                    Text(tosState.currentVideo?.title ?? "")
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer()
                }
            }
            .accessibilityIdentifier("tosPlayer.miniPlayer.expandButton")

            // Dismiss
            Button {
                tosState.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 62)
            }
            .accessibilityIdentifier("tosPlayer.miniPlayer.closeButton")
        }
        .padding(.leading, 4)
        .frame(height: 62)
        .background(.regularMaterial)
        // Without this, SwiftUI flattens this HStack's accessibility tree so each
        // child Button (play/pause, expand, close) inherits THIS container's
        // identifier ("tosPlayer.miniPlayerBar") instead of its own — e.g.
        // app.buttons["tosPlayer.miniPlayer.closeButton"] is never found by
        // XCUITest. .contain keeps each child individually discoverable. Same
        // fix as MiniPlayerView.bar — see its comment for details.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tosPlayer.miniPlayerBar")
    }
}

// MARK: - TOSMiniPlayerLayerView

/// UIViewRepresentable that hosts the TOS player's WKWebView as a live thumbnail.
/// UIView.addSubview transplants the webView from the full-screen
/// YouTubeWebPlayerView's container automatically — no explicit removeFromSuperview
/// needed. Keeping the webView attached to the window keeps the embedded YouTube
/// <video> element's document.visibilityState == 'visible', so playback continues
/// while minimized. Mirrors MiniPlayerLayerView's transplant pattern for AVPlayer.
private struct TOSMiniPlayerLayerView: UIViewRepresentable {
    let webView: WKWebView
    /// True while the external screen holds this web view. Passed in rather than read
    /// from the manager inside make/update, which are not observation-tracked.
    let externalDisplayOwnsWebView: Bool

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        if !externalDisplayOwnsWebView {
            attach(to: container)
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if !externalDisplayOwnsWebView, webView.superview !== uiView {
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
#endif // os(iOS)
