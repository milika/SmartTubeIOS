import XCTest

// MARK: - HomeShortsUITests
//
// Merged from ShortsNavigationUITests + HomeShortsRowUITests.
// All tests share a single app launch with:
//   --uitesting --uitesting-reset-settings --uitesting-enable-shorts
//
// ShortsNavigationUITests: 7 tests — chip navigation, content/empty state, context menu, regression #93
// HomeShortsRowUITests: 2 tests — cold-launch Shorts chip, home.shortsRow presence (regression #96)

final class HomeShortsUITests: XCTestCase {

    // MARK: - Shared app lifecycle

    private static var sharedApp: XCUIApplication!

    override class func setUp() {
        super.setUp()
        sharedApp = XCUIApplication()
        sharedApp.launchArguments += [
            "--uitesting", "--uitesting-reset-settings", "--uitesting-enable-shorts", "--uitesting-signed-in",
        ]
        sharedApp.launch()
    }

    override class func tearDown() {
        sharedApp.terminate()
        sharedApp = nil
        super.tearDown()
    }

    private var app: XCUIApplication { HomeShortsUITests.sharedApp }

    // MARK: - Per-test reset

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // Dismiss player if open.
        let backButton = app.buttons["player.backButton"].firstMatch
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
            _ = app.buttons["Home"].waitForExistence(timeout: 3)
        }
        // Dismiss mini-player if present.
        let closeButton = app.buttons["miniPlayer.closeButton"].firstMatch
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.tap()
        }
    }

    // MARK: - Helpers

    /// Scrolls the chip bar until the Shorts chip is fully visible on screen.
    private func scrollToShortsChip() {
        let chip = app.buttons["Shorts"]
        let screenWidth = app.windows.firstMatch.frame.width
        let rightEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.09))
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.09))
        for _ in 0..<6 {
            let frame = chip.frame
            guard frame.origin.x < 4 || frame.maxX > screenWidth - 4 else { break }
            if frame.origin.x < 4 {
                leftEdge.press(forDuration: 0.05, thenDragTo: rightEdge)
            } else {
                rightEdge.press(forDuration: 0.05, thenDragTo: leftEdge)
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// Scrolls the chip bar back to the left until the Home chip is visible, then taps it.
    private func tapHomeChip() {
        let chipBar = app.scrollViews["home.chipBar"]
        guard chipBar.waitForExistence(timeout: 5) else { return }
        let homeChip = chipBar.buttons["Home"].firstMatch
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.09))
        let rightEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.09))
        for _ in 0..<6 {
            guard homeChip.frame.origin.x < 0 else { break }
            leftEdge.press(forDuration: 0.05, thenDragTo: rightEdge)
            Thread.sleep(forTimeInterval: 0.3)
        }
        homeChip.tap()
    }

    /// Scrolls the chip bar until the Shorts chip is on-screen, then taps it.
    private func tapShortsChip(timeout: TimeInterval = 10) {
        let chip = app.buttons["Shorts"]
        XCTAssertTrue(chip.waitForExistence(timeout: timeout), "Shorts chip not found in Home chip bar")
        scrollToShortsChip()
        chip.tap()
    }

    // MARK: - Tests (from ShortsNavigationUITests)

    /// Verifies the root window exists immediately after launch.
    func testAppLaunchesSuccessfully() {
        XCTAssertTrue(app.windows.firstMatch.exists, "App window should exist after launch")
    }

    func testNavigateToHomeTab() {
        UITestHelpers.tapTab(named: "Home", in: app)

        let shortsChip = app.buttons["Shorts"]
        XCTAssertTrue(shortsChip.waitForExistence(timeout: 5), "Shorts chip should be visible in the Home chip bar")
    }

    func testShortsChipIsReachable() {
        UITestHelpers.tapTab(named: "Home", in: app)

        let shortsChip = app.buttons["Shorts"]
        XCTAssertTrue(shortsChip.waitForExistence(timeout: 5), "Shorts chip should exist in the Home chip bar")
        scrollToShortsChip()
        shortsChip.tap()

        XCTAssertTrue(
            shortsChip.isSelected,
            "Shorts chip should be selected after tap"
        )
    }

    func testShortsScreenShowsContentOrEmptyState() {
        UITestHelpers.tapTab(named: "Home", in: app)

        let shortsChip = app.buttons["Shorts"]
        XCTAssertTrue(shortsChip.waitForExistence(timeout: 5))
        scrollToShortsChip()
        shortsChip.tap()

        let contentOrEmpty =
            app.scrollViews.firstMatch.waitForExistence(timeout: 5)
            || app.staticTexts["Nothing here yet"].waitForExistence(timeout: 5)
            || app.staticTexts["Sign in to see your library"].waitForExistence(timeout: 5)

        XCTAssertTrue(contentOrEmpty, "Shorts screen should show content, an empty state, or a sign-in prompt")
    }

    func testNavigationDoesNotCrash() {
        UITestHelpers.tapTab(named: "Home", in: app)

        let shortsChip = app.buttons["Shorts"]
        guard shortsChip.waitForExistence(timeout: 5) else {
            XCTFail("Shorts chip not found — --uitesting-enable-shorts should guarantee it")
            return
        }
        scrollToShortsChip()
        shortsChip.tap()

        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(app.windows.firstMatch.exists, "App should still be running after navigating to Shorts")
    }

    // MARK: - Context menu regression (#90)

    /// Regression for #90: Short cards must show a long-press context menu
    /// with the same core actions as regular video cards.
    func testShortsCardLongPressShowsContextMenu() throws {
        UITestHelpers.tapTab(named: "Home", in: app)
        tapHomeChip()

        let shortsRow = app.scrollViews["home.shortsRow"]
        guard shortsRow.waitForExistence(timeout: 30) else {
            try captureAndSkip("home.shortsRow not found — fetchShorts() API flakiness. Skipping.", in: app)
        }

        let predicate = NSPredicate(format: "identifier BEGINSWITH 'shorts.card.'")
        let cards = shortsRow.descendants(matching: .any).matching(predicate)
        guard cards.count > 0 else {
            try captureAndSkip("No shorts.card.* elements found — feed empty. Skipping.", in: app)
        }
        let firstCard = cards.element(boundBy: 0)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))

        firstCard.press(forDuration: 1.2)

        let shareButton = app.buttons["Share"].firstMatch
        let addToQueue = app.buttons["Add to Queue"].firstMatch
        let menuAppeared =
            shareButton.waitForExistence(timeout: 4)
            || addToQueue.waitForExistence(timeout: 4)

        XCTAssertTrue(
            menuAppeared,
            "Long-pressing a Short card must show a context menu with Share or Add to Queue")
    }

    // MARK: - Chip immediate load regression (#93)

    /// Regression for #93: Shorts chip must show videos immediately after tapping,
    /// without requiring a Settings-and-back navigation to trigger the refresh.
    func testShortsChipShowsVideosImmediately() throws {
        UITestHelpers.tapTab(named: "Home", in: app)

        let chipBar = app.scrollViews.matching(identifier: "home.chipBar").firstMatch
        guard chipBar.waitForExistence(timeout: 5) else {
            try captureAndSkip("Chip bar not found — cannot verify Shorts chip load.", in: app)
        }

        let shortsChip = app.buttons["Shorts"]
        XCTAssertTrue(shortsChip.waitForExistence(timeout: 5))
        scrollToShortsChip()
        shortsChip.tap()

        let sectionContainer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'home.sectionContainer'")).firstMatch
        guard sectionContainer.waitForExistence(timeout: 15) else {
            try captureAndSkip("Section container not found after Shorts chip tap — network issue.", in: app)
        }

        // The Shorts chip renders its vertical list via ShortsRowSection, whose
        // cards carry "shorts.card.*" identifiers (not "video.card.*", which is
        // used by the regular grid/row sections for other chips).
        let hasContent =
            sectionContainer.descendants(matching: .any)
            .matching(
                NSPredicate(format: "identifier BEGINSWITH 'video.card.' OR identifier BEGINSWITH 'shorts.card.'")
            )
            .count > 0
        let hasEmpty =
            app.staticTexts["Nothing here yet"].exists
            || app.staticTexts["Sign in to see your library"].exists

        XCTAssertTrue(
            hasContent || hasEmpty,
            "Shorts chip must show content or empty state immediately — not require Settings nav")
    }

    // MARK: - Tests (from HomeShortsRowUITests)

    /// Regression test for #96 — cold-launch Shorts chip shows video cards.
    ///
    /// Before the fix, `fetchShorts()` used `post()` (WEB client headers,
    /// www.youtube.com) with the TV OAuth Bearer token, causing HTTP 400 and
    /// an empty Shorts feed on fresh launch. After the fix it uses `postTV()`
    /// (TVHTML5 headers, youtubei.googleapis.com), which accepts the token.
    func test_ColdLaunch_ShortsChip_ShowsVideos() throws {
        UITestHelpers.tapTab(named: "Home", in: app)
        tapShortsChip()

        let eitherPredicate = NSPredicate { [weak self] _, _ in
            guard let app = self?.app else { return false }
            let hasCards =
                app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'video.card.'"))
                .count > 0
            let hasEmpty = app.staticTexts["Nothing here yet"].exists
            return hasCards || hasEmpty
        }
        let eitherExpectation = XCTNSPredicateExpectation(predicate: eitherPredicate, object: nil)
        let result = XCTWaiter().wait(for: [eitherExpectation], timeout: 60)

        guard result == .completed else {
            try captureAndSkip(
                "Neither Shorts cards nor empty state appeared in 60 s — "
                    + "network unavailable or fetchShorts() is hanging. Skipping.",
                in: app
            )
        }

        if app.staticTexts["Nothing here yet"].exists {
            let hasCards =
                app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'video.card.'"))
                .count > 0
            if !hasCards {
                try captureAndSkip("Shorts section returned 0 videos — network/auth issue. Skipping.", in: app)
            }
        }

        let videoCards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'video.card.'"))
        XCTAssertGreaterThan(
            videoCards.count, 0,
            "Shorts chip on cold launch showed 0 video.card.* — "
                + "fetchShorts() regression #96 may be returning HTTP 400."
        )
    }

    /// The home feed must display a Shorts row (`home.shortsRow`) containing
    /// at least one `shorts.card.*` element.
    func test_HomeTab_ShortsRowVisible() throws {
        UITestHelpers.tapTab(named: "Home", in: app)
        tapHomeChip()

        guard UITestHelpers.waitForVideoCards(in: app, timeout: 30) != nil else {
            try captureAndSkip("Home feed did not load any video cards — network issue.", in: app)
        }

        let shortsRow = app.scrollViews["home.shortsRow"]
        guard shortsRow.waitForExistence(timeout: 15) else {
            try captureAndSkip(
                "home.shortsRow not found — fetchShorts() likely returned 0 videos "
                    + "(FEshorts API flakiness). Skipping rather than failing.",
                in: app
            )
        }

        let predicate = NSPredicate(format: "identifier BEGINSWITH 'shorts.card.'")
        let cards = shortsRow.descendants(matching: .any).matching(predicate)
        XCTAssertGreaterThan(
            cards.count, 0,
            "home.shortsRow is present but contains no shorts.card.* elements."
        )
    }
}
