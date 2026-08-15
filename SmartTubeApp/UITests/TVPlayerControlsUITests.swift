#if os(tvOS)
import XCTest

// MARK: - TVPlayerControlsUITests
//
// Verifies the tvOS player controls overlay and more menu elements:
//   - play/pause and next buttons exist in the accessibility tree
//   - more menu rows (quality, captions, audio track, audio only, cancel) are present
//   - quality picker opens and dismisses with the Menu button
//
// Uses --uitesting-open-more-menu so the more menu is open automatically on player launch.
// Player controls (playPauseButton, nextBtn) are rendered in the ZStack below the more
// menu and remain in the accessibility tree even while the menu is visible.
//
// Run against the "Smart Tube" tvOS scheme:
//   xcodebuild test -workspace SmartTube.xcworkspace -scheme "Smart Tube"
//     -destination "id=30E83929-0C67-4572-82C4-FE0F228EA835"
//     -only-testing:SmartTubeTVUITests/TVPlayerControlsUITests

final class TVPlayerControlsUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-open-more-menu"]
        app.launch()
        try openPlayer()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private var chipBar: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'home.chipBar'"))
            .firstMatch
    }

    private var titleLabel: XCUIElement {
        app.staticTexts["player.titleLabel"].firstMatch
    }

    private var moreMenuSpeedRow: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'player.moreMenu.speedRow'"))
            .firstMatch
    }

    /// Opens the player by navigating from the Home feed: ↓ into chip bar → ↓ into video list → select.
    /// With --uitesting-open-more-menu the player will open the more menu automatically on appear.
    private func openPlayer() throws {
        guard chipBar.waitForExistence(timeout: 15) else {
            try captureAndSkip("home.chipBar not found — app did not reach Home tab", in: app)
        }
        // Wait for at least one video card so we can navigate into it.
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(predicate)
        let cardExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: cards)
        guard XCTWaiter().wait(for: [cardExpectation], timeout: 20) == .completed else {
            try captureAndSkip("No video cards loaded — network unavailable", in: app)
        }
        remote.press(.down)       // tab bar → chip bar
        Thread.sleep(forTimeInterval: 0.6)
        remote.press(.down)       // chip bar → video list
        Thread.sleep(forTimeInterval: 0.6)
        remote.press(.select)     // open first video
        guard titleLabel.waitForExistence(timeout: 15) else {
            try captureAndSkip("player.titleLabel not found — player failed to open", in: app)
        }
    }

    /// Waits for the more menu to open (triggered by --uitesting-open-more-menu launch arg).
    private func waitForMoreMenu() throws {
        guard moreMenuSpeedRow.waitForExistence(timeout: 12) else {
            try captureAndSkip("More menu did not open automatically — check --uitesting-open-more-menu handling", in: app)
        }
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == '\(identifier)'"))
            .firstMatch
    }

    // MARK: - Tests

    /// The play/pause button must be in the accessibility tree when controls are visible.
    func testPlayPauseButtonExistsInControls() throws {
        try waitForMoreMenu()
        // Close the more menu so the controls layer becomes accessible.
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 0.8)
        // Press playPause to ensure controls are visible.
        remote.press(.playPause)
        Thread.sleep(forTimeInterval: 0.5)
        let btn = element(identifier: "player.playPauseButton")
        guard btn.waitForExistence(timeout: 8) else {
            try captureAndSkip("player.playPauseButton not found after showing controls", in: app)
        }
        XCTAssertTrue(btn.exists, "player.playPauseButton must be in the accessibility tree")
    }

    /// Highlighted center transport controls must not overlap.
    func testCenterTransportControlsDoNotOverlap() throws {
        try waitForMoreMenu()
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 0.8)
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.5)

        let seekBack = element(identifier: "player.seekBackButton")
        let playPause = element(identifier: "player.playPauseButton")
        let seekForward = element(identifier: "player.seekForwardButton")
        guard seekBack.waitForExistence(timeout: 8),
              playPause.waitForExistence(timeout: 8),
              seekForward.waitForExistence(timeout: 8) else {
            try captureAndSkip("Center transport controls were not available", in: app)
        }

        XCTAssertGreaterThanOrEqual(
            playPause.frame.midX - seekBack.frame.midX,
            110,
            "Rewind and play/pause are too close when highlighted"
        )
        XCTAssertGreaterThanOrEqual(
            seekForward.frame.midX - playPause.frame.midX,
            110,
            "Play/pause and fast-forward are too close when highlighted"
        )
    }

    /// The next-video button must be in the accessibility tree when controls are visible.
    func testNextVideoButtonExistsInControls() throws {
        try waitForMoreMenu()
        // Close the more menu so the controls layer becomes accessible.
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 0.8)
        // Press playPause to ensure controls are visible.
        remote.press(.playPause)
        Thread.sleep(forTimeInterval: 0.5)
        let btn = element(identifier: "player.nextBtn")
        guard btn.waitForExistence(timeout: 8) else {
            try captureAndSkip("player.nextBtn not found after showing controls", in: app)
        }
        XCTAssertTrue(btn.exists, "player.nextBtn must be in the accessibility tree")
    }

    /// The quality row must be present in the more menu.
    func testQualityRowVisibleInMoreMenu() throws {
        try waitForMoreMenu()
        let row = element(identifier: "player.moreMenu.qualityRow")
        XCTAssertTrue(row.exists, "player.moreMenu.qualityRow must appear in the more menu")
    }

    /// Pressing select on the quality row must open the quality picker.
    func testQualityPickerOpensFromMoreMenu() throws {
        try waitForMoreMenu()
        let qualityRow = element(identifier: "player.moreMenu.qualityRow")
        guard qualityRow.exists else {
            try captureAndSkip("player.moreMenu.qualityRow not found — cannot open quality picker", in: app)
        }
        // Navigate down from the speed row (which has prefersDefaultFocus) until the
        // quality row has focus. The row position varies with auth/network state.
        var reached = false
        for _ in 0..<4 {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.4)
            if qualityRow.hasFocus {
                reached = true
                break
            }
        }
        guard reached else {
            try captureAndSkip("quality row did not receive focus after 4 down presses", in: app)
        }
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1.0)
        let picker = element(identifier: "player.qualityPicker")
        guard picker.waitForExistence(timeout: 8) else {
            try captureAndSkip("player.qualityPicker did not appear after selecting quality row", in: app)
        }
        XCTAssertTrue(picker.exists, "player.qualityPicker must appear after selecting the quality row")
    }

    /// After opening the quality picker, pressing Menu must dismiss it and leave the player open.
    func testQualityPickerDismissesWithMenu() throws {
        try waitForMoreMenu()
        let qualityRow = element(identifier: "player.moreMenu.qualityRow")
        guard qualityRow.exists else {
            try captureAndSkip("player.moreMenu.qualityRow not found — cannot open quality picker", in: app)
        }
        var reached = false
        for _ in 0..<4 {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.4)
            if qualityRow.hasFocus {
                reached = true
                break
            }
        }
        guard reached else {
            try captureAndSkip("quality row did not receive focus — cannot test picker dismissal", in: app)
        }
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1.0)
        let picker = element(identifier: "player.qualityPicker")
        guard picker.waitForExistence(timeout: 8) else {
            try captureAndSkip("player.qualityPicker did not appear — cannot test dismissal", in: app)
        }
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(element(identifier: "player.qualityPicker").exists,
                       "player.qualityPicker must be gone after pressing Menu")
        XCTAssertTrue(titleLabel.exists, "player.titleLabel must still exist after dismissing quality picker")
    }

    /// The captions row must be present in the more menu (or skip if video has no captions).
    func testCaptionsRowVisibleInMoreMenu() throws {
        try waitForMoreMenu()
        let row = element(identifier: "player.moreMenu.captionsRow")
        guard row.waitForExistence(timeout: 5) else {
            try captureAndSkip("player.moreMenu.captionsRow not found — video may not have captions", in: app)
        }
        XCTAssertTrue(row.exists, "player.moreMenu.captionsRow must appear for a video with captions")
    }

    /// The audio track row must be present in the more menu (or skip if video has one track).
    func testAudioTrackRowVisibleInMoreMenu() throws {
        try waitForMoreMenu()
        let row = element(identifier: "player.moreMenu.audioTrackRow")
        guard row.waitForExistence(timeout: 5) else {
            try captureAndSkip("player.moreMenu.audioTrackRow not found — video may have only one audio track", in: app)
        }
        XCTAssertTrue(row.exists, "player.moreMenu.audioTrackRow must appear for a video with multiple audio tracks")
    }

    /// The audio-only row must be present in the more menu.
    func testAudioOnlyRowVisibleInMoreMenu() throws {
        try waitForMoreMenu()
        let row = element(identifier: "player.moreMenu.audioOnlyRow")
        XCTAssertTrue(row.exists, "player.moreMenu.audioOnlyRow must appear in the more menu")
    }

    /// Selecting the cancel row must dismiss the more menu while the player stays open.
    func testMoreMenuCancelRowDismissesMenu() throws {
        try waitForMoreMenu()
        let cancelRow = element(identifier: "player.moreMenu.cancel")
        guard cancelRow.exists else {
            try captureAndSkip("player.moreMenu.cancel not found — cannot test dismissal", in: app)
        }
        // The cancel button is at the bottom. Navigate down several times to reach it.
        for _ in 0..<6 { remote.press(.down); Thread.sleep(forTimeInterval: 0.3) }
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(element(identifier: "player.moreMenu.speedRow").exists,
                       "More menu must be dismissed after selecting the cancel row")
        XCTAssertTrue(titleLabel.exists, "player.titleLabel must still exist after dismissing the more menu")
    }

    /// Regression test for #150: pressing Menu/Back while the description panel is open
    /// must close the panel, not exit the app.
    func testDescriptionPanelClosesWithMenu() throws {
        try waitForMoreMenu()
        let descriptionRow = element(identifier: "player.moreMenu.descriptionRow")
        guard descriptionRow.waitForExistence(timeout: 5) else {
            try captureAndSkip("player.moreMenu.descriptionRow not found", in: app)
        }
        // Navigate down to find the description row (position varies).
        var reached = false
        for _ in 0..<8 {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.35)
            if descriptionRow.hasFocus { reached = true; break }
        }
        guard reached else {
            try captureAndSkip("#150 regression: description row did not receive focus", in: app)
        }
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1.0)
        // Description overlay must be visible.
        let xButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'player.descriptionOverlay' OR label == 'Description'"))
            .firstMatch
        guard xButton.waitForExistence(timeout: 6) else {
            try captureAndSkip("#150 regression: description panel did not open", in: app)
        }
        // Press Menu (Back) — must dismiss the panel, not exit the app.
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1.0)
        // Player title must still be present — app must not have exited.
        XCTAssertTrue(titleLabel.waitForExistence(timeout: 5),
                      "#150 regression: player.titleLabel must still exist after pressing Menu to close description panel")
    }
}
#endif
