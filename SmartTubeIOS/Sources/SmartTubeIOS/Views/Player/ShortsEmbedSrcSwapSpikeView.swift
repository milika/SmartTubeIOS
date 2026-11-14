#if os(iOS)
import SmartTubeIOSCore
import SwiftUI
import WebKit

/// SwiftUI host for the Task 1 iframe-src-swap spike. Presented as a full-screen
/// cover from `RootView` when launched with `--uitesting-shorts-srcswap-spike`.
struct ShortsEmbedSrcSwapSpikeView: View {
    @State private var vm = ShortsEmbedSrcSwapSpikeViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            SpikeWebView(webView: vm.webView)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(vm.statusSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("shortsSpike.statusLabel")

                Button(L10n.string("Swap")) {
                    vm.swapToNextVideo()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isExhausted)
                .accessibilityIdentifier("shortsSpike.swapButton")
            }
            .padding(.bottom, 40)
        }
        .onAppear { vm.start() }
    }
}

/// Hosts the spike's WKWebView — mirrors `TOSPlayerView`'s `YouTubeWebPlayerView`
/// (TOSPlayerView.swift:544-572).
private struct SpikeWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if webView.superview !== uiView {
            attach(to: uiView)
        }
    }

    private func attach(to container: UIView) {
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = true
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
#endif
