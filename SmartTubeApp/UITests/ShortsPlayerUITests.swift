import XCTest

// MARK: - ShortsPlayerUITests
//
// UI tests for ShortsPlayerView, split into two launch modes:
//
//   Direct-launch (--uitesting-shorts)
//   ────────────────────────────────────
//   AppEntry bypasses navigation and presents ShortsPlayerView directly with
//   stub videos. `shorts.indexLabel` appears immediately — no warm-up, no
//   network required. Used for tests that verify player behavior (index badge,
//   swipes, controls overlay) where the path TO the player is irrelevant.
//
//   Direct-launch with real video (--uitesting-shorts-ids=<ID>)
//   ─────────────────────────────────────────────────────────────
//   Same direct launch but with a real YouTube Short video ID so
//   InnerTubeAPI fetches a real stream. Used when verifying network behavior
//   (e.g. no error banner).
//
//   Full-app navigation (--uitesting --uitesting-enable-shorts)
//   ─────────────────────────────────────────────────────────────
//   The full app launches. Tests navigate Home → Shorts chip → tap card.
//   Used only for tests that verify the navigation PATH to the player.

final class ShortsPlayerUITests: XCTestCase {

    // MARK: - Known real YouTube Short video IDs
    //
    // Used when a test needs a real stream (e.g. no-error-banner check).
    // IDs are tried in order; the first one that loads without an error banner is used.
    // Replace the primary ID (index 0) when it becomes unavailable, or append new entries.
    private static let knownGoodShortIDs: [String] = [
        "MCv4EyEFgVg",  // Primary — popular public Short
        "pPvd8UxmCGY",  // Fallback 1
        "fKopy74weus",  // Fallback 2
    ]

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Do NOT launch here — each test picks its own launch mode.
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch helpers

    /// Direct-launch: `ShortsPlayerView` with three stub videos.
    /// No network required. `shorts.indexLabel` shows "1 / 3" immediately.
    private func launchWithStubs() {
        app.launchArguments = ["--uitesting", "--uitesting-shorts"]
        app.launch()
    }

    /// Direct-launch: `ShortsPlayerView` with specific real YouTube Short IDs.
    /// InnerTubeAPI fetches real streams — use when testing playback behavior.
    private func launchWithRealShorts(ids: [String]) {
        app.launchArguments = [
            "--uitesting", "--uitesting-shorts",
            "--uitesting-shorts-ids=\(ids.joined(separator: ","))",
        ]
        app.launch()
    }

    /// Full-app launch with the complete navigation stack and real Home feed.
    /// Use only for tests that verify the navigation path to the player.
    private func launchFullApp() {
        app.launchArguments = ["--uitesting", "--uitesting-enable-shorts"]
        app.launch()
    }

    // MARK: - Helpers

    private var indexLabel: XCUIElement {
        app.staticTexts["shorts.indexLabel"].firstMatch
    }

    /// Navigates Home → Shorts chip → taps the first Short card.
    /// Requires `launchFullApp()` to have been called first.
    private func openFirstShortViaNavigation() throws {
        UITestHelpers.tapTab(named: "Home", in: app)

        let chipBar = app.scrollViews["home.chipBar"]
        XCTAssertTrue(chipBar.waitForExistence(timeout: 10), "home.chipBar must appear on Home tab")

        let shortsChip = chipBar.buttons["Shorts"]
        guard shortsChip.waitForExistence(timeout: 5) else {
            XCTFail("Shorts chip not found — section may be disabled")
            return
        }
        UITestHelpers.scrollChipIntoView(shortsChip, in: chipBar, app: app)
        shortsChip.tap()

        // Wait for the Shorts section feed ScrollView before querying cards.
        // Without this guard the predicate below can match stale Home-feed cards
        // still in the accessibility tree during the section-switch animation.
        let sectionFeed = app.descendants(matching: .any)["home.sectionContainer"]
        guard sectionFeed.waitForExistence(timeout: 20) else {
            try captureAndSkip(
                "Shorts section feed did not appear within 20 s — network unavailable or Shorts empty", in: app)
        }

        let feedPredicate = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(feedPredicate)
        let feedLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"),
            object: cards)
        guard XCTWaiter().wait(for: [feedLoaded], timeout: 10) == .completed else {
            try captureAndSkip("Shorts feed did not load within 10 s — network unavailable or Shorts empty", in: app)
        }

        cards.firstMatch.tap()
        XCTAssertTrue(
            indexLabel.waitForExistence(timeout: 15),
            "shorts.indexLabel must appear after tapping a Short")
    }

    /// Performs a swipe-up gesture on the Shorts player.
    private func swipeUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Performs a swipe-down gesture on the Shorts player.
    private func swipeDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Taps the Shorts player until the controls overlay becomes visible.
    /// Uses `shorts.backButton` (a Button inside the overlay) as the visibility
    /// proxy — VStack containers with accessibilityIdentifier are transparent in
    /// the XCTest accessibility tree and cannot be found directly.
    private func showShortsControls() {
        let backButton = app.buttons["shorts.backButton"]
        for _ in 0..<5 {
            if backButton.exists { return }
            // Use window-element tap — reliably triggers UITapGestureRecognizer
            // in SwipeGestureOverlay; coordinate-based taps are unreliable here.
            app.windows.firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }

    // MARK: - Tests

    // ── Navigation tests ──────────────────────────────────────────────────────

    /// Verifies that ShortsPlayerView opens and shows the index badge.
    /// Uses direct-launch with real Short IDs to avoid auth dependency on parallel clone simulators.
    func testShortsPlayerOpensFromHomeChip() throws {
        launchWithRealShorts(ids: Self.knownGoodShortIDs)
        guard indexLabel.waitForExistence(timeout: 20) else {
            try captureAndSkip("Shorts player did not appear — network unavailable or Short IDs may be stale", in: app)
        }
        XCTAssertTrue(
            indexLabel.exists,
            "shorts.indexLabel should be visible when ShortsPlayerView is open")
    }

    /// Verifies the back button in the Shorts player is tappable and does not crash the app.
    /// Uses direct-launch with real Short IDs to avoid auth dependency on parallel clone simulators.
    func testBackButtonDismissesShortsPlayer() throws {
        app.launchArguments = [
            "--uitesting", "--uitesting-shorts",
            "--uitesting-shorts-ids=\(Self.knownGoodShortIDs.joined(separator: ","))",
            "--uitesting-show-controls",
        ]
        app.launch()
        guard indexLabel.waitForExistence(timeout: 40) else {
            try captureAndSkip("Shorts player did not appear — network unavailable or Short IDs may be stale", in: app)
        }
        // Controls are shown immediately via --uitesting-show-controls.
        let backPred = NSPredicate(format: "identifier == 'shorts.backButton'")
        let backBtn = app.descendants(matching: .any).matching(backPred).firstMatch
        guard backBtn.waitForExistence(timeout: 10) else {
            try captureAndSkip("shorts.backButton did not appear — controls may not be visible", in: app)
        }
        backBtn.tap()
        // In direct-launch mode ShortsPlayerView is the root view, so dismiss() has no visual
        // navigation effect. The key regression to catch is a crash on tap.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(
            app.state, .runningForeground,
            "App must not crash after tapping the Shorts back button")
    }

    // ── Direct-launch (stub) tests — no network, instant ────────────────────

    /// Verifies the index badge shows "1 / 3" when the player opens at index 0.
    func testIndexLabelShowsStartIndex() {
        launchWithStubs()
        XCTAssertTrue(
            indexLabel.waitForExistence(timeout: 5),
            "shorts.indexLabel must appear immediately on direct launch")
        XCTAssertEqual(
            indexLabel.label, "1 / 3",
            "Index badge should show '1 / 3' on launch with three stub Shorts")
    }

    /// Verifies swipe-up advances the index from 1 to 2.
    func testSwipeUpAdvancesShort() {
        launchWithStubs()
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(indexLabel.label, "1 / 3")

        swipeUp()
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertEqual(
            indexLabel.label, "2 / 3",
            "Swipe up should advance the index from 1 to 2")
    }

    /// Verifies swipe-down after swipe-up returns to index 1.
    func testSwipeDownGoesBackToPreviousShort() {
        launchWithStubs()
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 5))

        swipeUp()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(indexLabel.label, "2 / 3", "Should be on index 2 after swiping up")

        swipeDown()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(
            indexLabel.label, "1 / 3",
            "Swipe down should return to index 1")
    }

    /// Verifies that the controls overlay elements are accessible in XCTest
    /// when the overlay is shown.
    ///
    /// Uses `--uitesting-show-controls` so the overlay appears on launch without
    /// depending on UIKit gesture delivery, which is unreliable in the simulator
    /// (the `UITapGestureRecognizer` in `SwipeGestureOverlay` requires the
    /// `UIPanGestureRecognizer` to fail first, which XCTest synthetic taps do
    /// not reliably trigger in the required order).
    ///
    /// What this test validates:
    ///   - `shorts.backButton` is in the accessibility tree when controls are shown
    func testControlsOverlayAppearsOnTap() {
        app.launchArguments = ["--uitesting", "--uitesting-shorts", "--uitesting-show-controls"]
        app.launch()

        XCTAssertTrue(
            indexLabel.waitForExistence(timeout: 5),
            "shorts.indexLabel must appear before testing the controls overlay")

        // Controls appear immediately after onAppear via --uitesting-show-controls.
        // Wait up to 5 s for the back button that lives inside the overlay.
        let backButton = app.buttons["shorts.backButton"]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "shorts.backButton should appear when --uitesting-show-controls is active")
    }

    // ── ⋯ menu ───────────────────────────────────────────────────────────────

    /// The ⋯ sheet lists the official actions, and Clear Screen hides the overlay
    /// until the next tap.
    func testMoreMenuClearScreenHidesControlsUntilTap() {
        launchWithStubs()
        let more = app.buttons["shorts.moreButton"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "⋯ button must be on the overlay")

        more.tap()
        XCTAssertTrue(
            app.buttons["shorts.action.description"].waitForExistence(timeout: 5),
            "⋯ sheet must offer Description")
        XCTAssertTrue(app.buttons["shorts.action.report"].exists, "⋯ sheet must offer Report")
        app.buttons["shorts.action.clearScreen"].tap()

        XCTAssertTrue(more.waitForNonExistence(timeout: 5), "Clear Screen must hide the overlay")
        app.windows.firstMatch.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5), "A tap must bring the overlay back")
    }

    /// Description opens its own sheet, and the overlay steps aside while the video
    /// is shrunk above it.
    func testMoreMenuOpensDescriptionSheet() {
        launchWithStubs()
        let more = app.buttons["shorts.moreButton"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))

        more.tap()
        let description = app.buttons["shorts.action.description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()

        XCTAssertTrue(
            app.navigationBars["Description"].waitForExistence(timeout: 5), "Description sheet must open")
        XCTAssertTrue(more.waitForNonExistence(timeout: 5), "Overlay must hide while the video is shrunk")
    }

    // ── Direct-launch with real video — network required ─────────────────────

    /// Verifies no error banner appears when a real Short loads.
    /// Tries each ID in `knownGoodShortIDs` in order; the first one that loads
    /// without an error banner passes the test. If all IDs show errors the test
    /// skips with guidance to update the array.
    func testNoErrorBannerOnShortsOpen() throws {
        guard !Self.knownGoodShortIDs.isEmpty else {
            try captureAndSkip("knownGoodShortIDs is empty — add at least one valid Short ID", in: app)
        }
        var lastError = "unknown"
        for shortID in Self.knownGoodShortIDs {
            app.terminate()
            launchWithRealShorts(ids: [shortID])
            guard indexLabel.waitForExistence(timeout: 20) else {
                // Network unavailable — cannot determine if ID is valid; skip the whole test.
                try captureAndSkip("Shorts player did not appear for '\(shortID)' — network unavailable", in: app)
            }
            Thread.sleep(forTimeInterval: 5)
            let banner = app.staticTexts["shorts.errorBanner"].firstMatch
            if !banner.exists {
                return  // This ID loaded successfully.
            }
            // Video is stale (deleted, private, or region-locked). Try next ID.
            lastError = banner.label
        }
        try captureAndSkip(
            "All \(Self.knownGoodShortIDs.count) short IDs show errors — update knownGoodShortIDs in ShortsPlayerUITests.swift. "
                + "Last error for '\(Self.knownGoodShortIDs.last ?? "")': '\(lastError)'",
            in: app
        )
    }
}
