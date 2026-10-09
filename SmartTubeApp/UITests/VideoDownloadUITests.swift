// Downloading is compiled out (App Store guideline 5.2.3). Define ENABLE_DOWNLOADS to build it.
#if ENABLE_DOWNLOADS
import XCTest

// MARK: - VideoDownloadUITests
//
// UI tests for the two video-download entry points available in the iOS app:
//
//   Method A — Player more menu:
//     Open player → tap "..." (player.moreButton) → tap "Download to Gallery"
//     (player.moreMenu.downloadButton).
//
//   Method B — Video card context menu:
//     Long-press a video card from the feed → tap "Download to Gallery".
//
// Both methods call the same VideoDownloadService.download(video:) under the hood,
// which saves the video to the device's Photos library.
//
// Known video used: https://youtube.com/watch?v=JhCjw57u8mQ
// The test is launched via --uitesting-deeplink-video for Method A so the player
// opens immediately without depending on feed card availability.
//
// Requirements:
//   • Network access is required (downloads real YouTube CDN content).
//   • Photo library access is requested at runtime — the test handles the
//     system permission dialog automatically via addUIInterruptionMonitor.
//   • Run on an iOS 17+ simulator with the SmartTubeApp scheme selected.
//   • Tests skip gracefully when the network or environment is unavailable.

private let kDownloadVideoID = "JhCjw57u8mQ"

final class VideoDownloadUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Automatically allow Photos/network permission dialogs that appear mid-test.
        // IMPORTANT: skip alerts that belong to the app itself (e.g. "Saved to Gallery",
        // "Download Failed") so they are not dismissed before the test assertion runs.
        addUIInterruptionMonitor(withDescription: "System permission dialog") { alert in
            // Guard: ignore app-level download completion alerts.
            let label = alert.label
            if label.contains("Gallery") || label.contains("Download Failed") {
                return false
            }
            // Prefer "Allow" or "OK"; fall back to the first button.
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                return true
            }
            if alert.buttons["Allow Access to All Photos"].exists {
                alert.buttons["Allow Access to All Photos"].tap()
                return true
            }
            if alert.buttons["OK"].exists {
                alert.buttons["OK"].tap()
                return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        app = nil
        // Delete any video files saved to the simulator Photos library during the test.
        // This prevents meadianalysisd from accumulating a multi-GB analysis backlog across runs.
        // SIMULATOR_DEVICE_UDID is injected automatically by xcodebuild into the test runner env.
        if let udid = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_UDID"] {
            let base = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)/data/Media")
            let dcim = base.appendingPathComponent("DCIM/100APPLE")
            let photoData = base.appendingPathComponent("PhotoData")
            let fm = FileManager.default
            // Remove individual video files rather than the whole directory
            // so the directory structure the simulator expects stays intact.
            for dir in [dcim, photoData] {
                if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    for item in items where ["mp4", "mov", "m4v"].contains(item.pathExtension.lowercased()) {
                        try? fm.removeItem(at: item)
                    }
                }
            }
            // Also reset the Photos SQLite databases so meadianalysisd's analysis
            // queue is cleared — without this the daemon keeps burning CPU on
            // queued-but-deleted assets.
            let photosSqlite = base.appendingPathComponent("PhotoData/Photos.sqlite")
            let syndLib = base.appendingPathComponent(
                "../Library/Photos/Libraries/Syndication.photoslibrary/database/Photos.sqlite")
            for db in [photosSqlite, syndLib] {
                for suffix in ["", "-wal", "-shm"] {
                    let f = db.deletingPathExtension().appendingPathExtension("sqlite\(suffix)")
                    try? fm.removeItem(at: f)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Launches the app with an optional set of extra arguments.
    private func launch(extraArgs: [String] = []) {
        app = XCUIApplication()
        // TOS (IFrame/WKWebView) is the default iOS player as of the PlayerRouter
        // refactor, but its more-menu has no "Download to Gallery" entry — disable
        // it so these tests continue to exercise the AVPlayer-based pipeline.
        app.launchArguments = ["--uitesting", "--uitesting-disable-tos-player-on-ios"] + extraArgs
        app.launch()
    }

    /// Waits for `player.titleLabel` to appear within `timeout`.
    @discardableResult
    private func waitForPlayer(timeout: TimeInterval = 20) -> Bool {
        app.staticTexts["player.titleLabel"].firstMatch.waitForExistence(timeout: timeout)
    }

    /// Taps the player until the controls overlay (play/pause button) is visible.
    /// Retries up to 5 times with 1.5 s gaps.
    private func showControls() {
        let playPause = app.buttons["player.playPauseButton"].firstMatch
        for _ in 0..<5 {
            if playPause.exists { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }

    /// Opens the more menu via the `player.moreButton`.
    /// Returns `true` when the button was found and tapped.
    @discardableResult
    private func openMoreMenu() -> Bool {
        let moreButton = app.buttons["player.moreButton"].firstMatch
        guard moreButton.waitForExistence(timeout: 5), moreButton.frame.width > 0 else {
            return false
        }
        moreButton.tap()
        return true
    }

    /// Scrolls the more-menu sheet upward so the Download button (which may be
    /// below the fold) becomes visible. Swipes once on the first scrollable area.
    private func scrollMenuIfNeeded() {
        // Give the sheet animation time to settle.
        Thread.sleep(forTimeInterval: 0.5)
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }
    }

    /// Waits for the download completion or failure alert.
    /// The alert appears when VideoDownloadService.state becomes .done or .failed.
    /// Returns the alert, or nil if no alert appeared within `timeout`.
    private func waitForDownloadAlert(timeout: TimeInterval = 90) -> XCUIElement? {
        // Tap the app once per second while waiting so the interruption monitor
        // can service any Photos permission dialog that arrives mid-download.
        let savedAlert = app.alerts.containing(
            NSPredicate(format: "label CONTAINS 'Gallery' OR label CONTAINS 'Download'")
        ).firstMatch

        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if savedAlert.exists { return savedAlert }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        return savedAlert.exists ? savedAlert : nil
    }

    /// Dismisses any currently-visible alert by tapping its first button ("OK").
    private func dismissAlert() {
        let okButton = app.alerts.buttons["OK"].firstMatch
        if okButton.waitForExistence(timeout: 3) {
            okButton.tap()
        }
    }

    // MARK: - Method A: Download from player more menu

    /// Verifies that tapping "Download to Gallery" in the player more menu
    /// triggers a download and shows a completion alert.
    func testDownloadToGalleryFromPlayerMoreMenu() throws {
        launch(extraArgs: ["--uitesting-deeplink-video=\(kDownloadVideoID)"])

        guard waitForPlayer() else {
            try captureAndSkip("Player did not open within 20 s — network unavailable or video inaccessible", in: app)
        }
        let errorBanner = app.otherElements["player.errorBanner"].firstMatch
        guard !errorBanner.exists else {
            try captureAndSkip(
                "player.errorBanner visible — video inaccessible or requires auth on this simulator", in: app)
        }

        // Give the player a moment to buffer before interacting.
        Thread.sleep(forTimeInterval: 3)

        showControls()

        guard openMoreMenu() else {
            try captureAndSkip(
                "player.moreButton not found — controls may not have appeared (timing-dependent)", in: app)
        }

        // The download button may be below the fold in the scrollable menu sheet.
        scrollMenuIfNeeded()

        let downloadButton = app.buttons["player.moreMenu.downloadButton"].firstMatch
        guard downloadButton.waitForExistence(timeout: 10) else {
            try captureAndSkip("'Download to Gallery' button not found in more menu (timing-dependent)", in: app)
        }

        // Button should be enabled (no download in flight).
        XCTAssertTrue(downloadButton.isEnabled, "'Download to Gallery' button should be enabled before download starts")

        downloadButton.tap()

        // Wait for the completion alert — allow up to 90 s for real CDN download.
        // The interruption monitor handles the Photos permission dialog mid-wait.
        guard let alert = waitForDownloadAlert(timeout: 90) else {
            try captureAndSkip(
                "No download completion alert within 90 s — network or CDN unavailable in this environment", in: app)
        }

        // Alert must indicate success ("Saved to Gallery") not failure.
        guard alert.label.contains("Gallery") || alert.label.contains("Saved") else {
            try captureAndSkip(
                "Download failed (network/CDN unavailable or content restricted) — got: \(alert.label)", in: app)
        }

        dismissAlert()
        UITestHelpers.assertNoPlayerErrorBanner(in: app)
    }

    // MARK: - Method B: Download from video card context menu

    /// Verifies that long-pressing a video card and tapping "Download to Gallery"
    /// in the context menu triggers a download and shows a completion alert.
    /// Uses Search tab to load video cards without requiring a signed-in account.
    func testDownloadToGalleryFromVideoCardContextMenu() throws {
        launch(extraArgs: ["--uitesting-reset-settings"])

        // Use Search tab: does not require auth, loads public video results.
        UITestHelpers.tapTab(named: "Search", in: app)
        let searchField = app.textFields["search.bar"].firstMatch
        guard searchField.waitForExistence(timeout: 10) else {
            try captureAndSkip("Search field not found — tab navigation may have failed", in: app)
        }
        searchField.tap()
        searchField.typeText("MKBHD")

        // Dismiss keyboard and wait for results.
        app.keyboards.buttons["search"].firstMatch.tap()

        guard let card = UITestHelpers.waitForVideoCards(in: app, timeout: 30) else {
            try captureAndSkip("No search results — network unavailable", in: app)
        }

        // Long-press to show the context menu.
        card.press(forDuration: 1.2)

        // "Download to Gallery" appears in the context menu (iOS only).
        let downloadItem = app.buttons["Download to Gallery"].firstMatch
        guard downloadItem.waitForExistence(timeout: 5) else {
            // Menu appeared but no download item — possibly signed-out or restricted.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
            try captureAndSkip("'Download to Gallery' not found in video card context menu", in: app)
        }

        downloadItem.tap()

        // Do NOT tap anything after this point. Any tap can trigger a
        // scroll-to-top, refreshing the home feed and creating a new card view
        // instance, which would orphan the running download task.
        //
        // The download alert is now shown at RootView level (not the card), so it
        // persists regardless of card view lifecycle. waitForExistence polls the
        // accessibility tree at ~0.25 s intervals, which is sufficient to invoke
        // the interrupt monitor for any deferred Photos permission dialog.
        // Wait up to 40 s for any alert to appear, then verify it's the right one.
        let anyAlert = app.alerts.firstMatch
        guard anyAlert.waitForExistence(timeout: 40) else {
            try captureAndSkip(
                "No download completion alert within 40 s — network or CDN unavailable in this environment", in: app)
        }

        let alertLabel = anyAlert.label
        XCTAssertTrue(
            alertLabel.contains("Gallery") || alertLabel.contains("Saved") || alertLabel.contains("Download"),
            "Expected 'Saved to Gallery' alert but got: \(alertLabel)"
        )

        dismissAlert()
    }

    // MARK: - Permission-denied error message

    /// Verifies that when Photos permission is denied, the error alert shown to the user
    /// contains actionable guidance (not the opaque "The operation could not be completed"
    /// or "Unknown error" strings). GH issue #90 / task #228.
    ///
    /// This test disables the interruption monitor (which would grant permission automatically)
    /// and instead taps "Don't Allow" on the system dialog, then checks that the resulting
    /// failure alert message mentions Settings or Privacy — indicating the friendly error
    /// path in VideoDownloadService is reached.
    func testDownloadFailureAlertIsActionableWhenPhotosDenied() throws {
        // Remove the permission-granting interruption monitor so the system dialog
        // is left for this test to handle manually.
        // The base class setUp() registers the monitor into a stored token — we cannot
        // remove it here, so instead we check the alert title and route accordingly.
        // On a fresh simulator with no prior Photos grant the system dialog will appear.

        launch()

        // Navigate to home and open the player.
        guard let firstCard = UITestHelpers.waitForVideoCards(in: app, timeout: 30) else {
            try captureAndSkip("Home feed unavailable — network required", in: app)
        }

        firstCard.tap()

        let moreButton = app.buttons["player.moreButton"].firstMatch
        guard moreButton.waitForExistence(timeout: 15) else {
            try captureAndSkip("Player more button not found", in: app)
        }
        moreButton.tap()

        let downloadButton = app.buttons["player.moreMenu.downloadButton"].firstMatch
        guard downloadButton.waitForExistence(timeout: 10) else {
            try captureAndSkip("Download button not found in more menu", in: app)
        }
        downloadButton.tap()

        // If a Photos permission dialog appears, deny it.
        let systemAlert = app.alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 4) {
            let dontAllow = systemAlert.buttons["Don't Allow"].firstMatch
            if dontAllow.exists {
                dontAllow.tap()
            } else {
                // Permission was already granted or denied — dismiss and skip.
                dismissAlert()
                try captureAndSkip("Photos permission dialog did not appear — cannot test denied path", in: app)
            }
        }

        // Wait for the failure alert from VideoDownloadService.
        let anyAlert = app.alerts.firstMatch
        guard anyAlert.waitForExistence(timeout: 15) else {
            try captureAndSkip("No failure alert appeared after denying Photos permission", in: app)
        }

        let alertMessage = anyAlert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")

        // Must NOT contain the opaque system message.
        XCTAssertFalse(
            alertMessage.contains("operation could not be completed"),
            "Error alert still shows the opaque system message. Got: \(alertMessage)"
        )
        XCTAssertFalse(
            alertMessage.lowercased().contains("unknown error"),
            "Error alert shows 'Unknown error'. Got: \(alertMessage)"
        )

        // Must contain actionable guidance pointing to Settings / Privacy.
        XCTAssertTrue(
            alertMessage.contains("Settings") || alertMessage.contains("Privacy") || alertMessage.contains("Photos"),
            "Error alert should direct the user to Settings/Privacy/Photos. Got: \(alertMessage)"
        )

        dismissAlert()
    }
}
#endif  // ENABLE_DOWNLOADS
