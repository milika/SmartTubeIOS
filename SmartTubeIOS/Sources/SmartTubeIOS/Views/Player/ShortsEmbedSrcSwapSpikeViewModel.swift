#if !os(tvOS)
import Foundation
import CoreFoundation
import WebKit
import os

private let spikeLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsSpike")

/// Standalone spike (Task 1 of `docs/superpowers/plans/2026-06-12-tos-player-shorts-implementation-plan.md`)
/// — validates that swapping a cross-origin YouTube embed iframe's `src` via `eval()`
/// repeatedly: (a) actually navigates the iframe, (b) re-triggers the injected
/// `forMainFrameOnly: false` user scripts for the new frame, and (c) produces a fresh
/// "ready"/"tick" message sequence — without leaking memory or accumulating stale JS
/// state/timers from the previous video.
///
/// See `docs/superpowers/specs/2026-06-11-tos-player-shorts-design.md`, "Critical
/// pre-work". This view model owns ONE persistent `WKWebView` and swaps the
/// `<iframe id="yt">`'s `src` across `testVideoIds` on each `swapToNextVideo()` call
/// (driven by `ShortsEmbedSrcSwapSpikeView`'s "Swap" button / the UI test).
@MainActor
@Observable
final class ShortsEmbedSrcSwapSpikeViewModel: NSObject {

    /// Four distinct, long-lived public videos with different durations (~136s, 213s,
    /// 252s, 282s) — chosen so `readyDurations` entries are distinguishable across
    /// swaps (freshReady check). Index 0 is loaded via the *initial* `loadHTMLString`
    /// (no warm network connections yet) and is inherently racier than indices 1-3,
    /// which reuse an already-warm WKWebView after a src swap: `stateDetectionJS`'s
    /// `pollVideo()` fires its one-shot `ready` on the first 250ms poll, and
    /// `video.duration` can still occasionally read `NaN`/0 for index 0 at that point.
    /// See git history for videos that were tried and rejected (`BaW_jenozKc`,
    /// `jNQXAC9IVRw` — both reliably produced `ready duration=0.0` or embed errors).
    static let testVideoIds = ["XqZsoesa55w", "kJQP7kiw5Fk", "dQw4w9WgXcQ", "9bZkp7q19f0"]

    /// How long after each "ready" to count "tick" messages (ticksResume/tickRateStable checks).
    static let tickWindowNanoseconds: UInt64 = 3_000_000_000

    // MARK: - Observable state (read by ShortsEmbedSrcSwapSpikeView + the UI test's AX query)

    /// One entry per "ready" message received, in order — `duration` reported by
    /// `stateDetectionJS`'s `pollVideo` for that video.
    var readyDurations: [Double] = []
    /// One entry per "ready" message, filled in ~3s later — the number of "tick"
    /// messages observed in the window following that "ready".
    var tickCountsSinceReady: [Int] = []
    /// Total "error" messages received across all videos — must stay 0.
    var errorCount = 0
    /// Index into `testVideoIds` of the currently-loaded video.
    private(set) var currentIndex = 0

    var isExhausted: Bool { currentIndex >= Self.testVideoIds.count - 1 }

    /// Single-line summary surfaced via AX for the UI test to parse without needing a
    /// Darwin notification per field, e.g. "idx=2 ready=[19.0,615.0,212.0] ticks=[12,11] errors=0".
    var statusSummary: String {
        let readyStr = readyDurations.map { String(format: "%.1f", $0) }.joined(separator: ",")
        let ticksStr = tickCountsSinceReady.map(String.init).joined(separator: ",")
        return "idx=\(currentIndex) ready=[\(readyStr)] ticks=[\(ticksStr)] errors=\(errorCount)"
    }

    // MARK: - Internal

    let webView: WKWebView
    /// Ticks observed since the most recent "ready" — reset to 0 when "ready" fires,
    /// snapshotted into `tickCountsSinceReady` after `tickWindowNanoseconds`.
    private var ticksSinceLastReady = 0
    /// Captured from the first "ready" message of each video — re-targets `eval()`
    /// at the new iframe's frame after a src swap. Reset to nil in `swapToNextVideo()`
    /// and re-captured on that video's "ready" — see `TOSPlayerViewModel.embedFrameInfo`
    /// for why this is necessary for cross-origin iframe eval.
    private var embedFrameInfo: WKFrameInfo?
    private var navigationDelegate: SpikeNavigationDelegate?

    // MARK: - Init

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = false
        #endif

        let contentController = WKUserContentController()
        let proxyHandler = SpikeScriptMessageProxy()
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
                source: ShortsEmbedJS.stateDetectionJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                in: .page
            ))
        config.userContentController = contentController

        self.webView = WKWebView(frame: .zero, configuration: config)
        #if os(iOS)
        self.webView.isOpaque = false
        self.webView.backgroundColor = .clear
        self.webView.scrollView.backgroundColor = .clear
        #endif

        super.init()

        proxyHandler.target = self

        let navDel = SpikeNavigationDelegate()
        self.webView.navigationDelegate = navDel
        self.navigationDelegate = navDel
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "ytCallback",
            contentWorld: .page
        )
    }

    // MARK: - Lifecycle

    func start() {
        let url = ShortsEmbedJS.embedURL(videoId: Self.testVideoIds[0])
        let html = ShortsEmbedJS.htmlWrapper(embedURL: url)
        spikeLog.notice("[spike] loading video[0]=\(Self.testVideoIds[0], privacy: .public)")
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.example.com")!)
    }

    /// Swaps the `<iframe id="yt">`'s `src` to the next test video — the core
    /// mechanic under test. No-op once `isExhausted`.
    func swapToNextVideo() {
        guard !isExhausted else { return }
        currentIndex += 1
        embedFrameInfo = nil
        let url = ShortsEmbedJS.embedURL(videoId: Self.testVideoIds[currentIndex])
        spikeLog.notice(
            "[spike] swap → video[\(self.currentIndex)]=\(Self.testVideoIds[self.currentIndex], privacy: .public)")
        eval("swap", "document.getElementById('yt').src = '\(url.absoluteString)';")
    }

    // MARK: - JS bridge

    func handleScriptMessage(_ body: String, frameInfo: WKFrameInfo) {
        guard let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        switch type {
        case "ready":
            if embedFrameInfo == nil {
                embedFrameInfo = frameInfo
            }
            let duration = (json["duration"] as? Double) ?? 0
            readyDurations.append(duration)
            ticksSinceLastReady = 0
            let windowIndex = readyDurations.count - 1
            spikeLog.notice("[spike] ready #\(windowIndex) duration=\(duration, format: .fixed(precision: 1))s")
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.shortsspike.ready" as CFString),
                nil, nil, true
            )
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.tickWindowNanoseconds)
                await MainActor.run {
                    guard let self else { return }
                    while self.tickCountsSinceReady.count <= windowIndex {
                        self.tickCountsSinceReady.append(0)
                    }
                    self.tickCountsSinceReady[windowIndex] = self.ticksSinceLastReady
                    spikeLog.notice("[spike] window #\(windowIndex) closed — ticks=\(self.ticksSinceLastReady)")
                    CFNotificationCenterPostNotification(
                        CFNotificationCenterGetDarwinNotifyCenter(),
                        CFNotificationName("com.void.smarttube.shortsspike.windowclosed" as CFString),
                        nil, nil, true
                    )
                }
            }

        case "tick":
            ticksSinceLastReady += 1

        case "error":
            errorCount += 1
            let code = (json["code"] as? Int) ?? -1
            spikeLog.notice("[spike] ❌ error code=\(code)")
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.shortsspike.error" as CFString),
                nil, nil, true
            )

        default:
            break
        }
    }

    // MARK: - Private helpers

    private func eval(_ label: String, _ js: String) {
        webView.evaluateJavaScript(js, in: embedFrameInfo, in: .page) { result in
            switch result {
            case .success(let value):
                spikeLog.notice(
                    "[spike-eval] \(label, privacy: .public) result: \(String(describing: value), privacy: .public)")
            case .failure(let error):
                spikeLog.notice(
                    "[spike-eval] \(label, privacy: .public) ERROR: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

// MARK: - SpikeNavigationDelegate

private final class SpikeNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        spikeLog.error("[spike-nav] provisional navigation failed: \(error)")
    }
}

// MARK: - SpikeScriptMessageProxy

/// Breaks the retain cycle: `WKUserContentController` retains its handlers strongly.
/// This proxy holds a `weak` reference so `ShortsEmbedSrcSwapSpikeViewModel` is not
/// kept alive by the web view's content controller — mirrors `ScriptMessageProxy`
/// in `TOSPlayerViewModel.swift:631-656`.
private final class SpikeScriptMessageProxy: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    weak var target: ShortsEmbedSrcSwapSpikeViewModel?

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
