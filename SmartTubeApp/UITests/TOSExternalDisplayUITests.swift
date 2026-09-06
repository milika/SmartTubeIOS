import XCTest

// MARK: - TOSExternalDisplayUITests
//
// External-display flow of the TOS player, run without hardware: no simulator
// emulates a connected screen, so `--uitesting-fake-external-display` hands the
// phone's own window scene to ExternalDisplayManager as if it were one (see
// AppEntry.attachFakeExternalDisplayFromLaunchArgs). The stand-in window takes the
// bottom quarter of the screen, which leaves the native controls the phone draws
// while the embed is "on the TV" clear for tapping.
//
// Deeplinks to dQw4w9WgXcQ like the other TOS tests — public, embeddable, always
// plays. Skips (not fails) when the embed never starts, which is a network /
// YouTube availability problem rather than an app defect.
final class TOSExternalDisplayUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-enable-tos-player-on-ios",
            "--uitesting-disable-sponsorblock",
            "--uitesting-deeplink-video=dQw4w9WgXcQ",
            "--uitesting-fake-external-display",
        ]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for `tosPlayer.stateLabel` to read `state`.
    private func waitForState(_ state: String, timeout: TimeInterval = 10) -> Bool {
        let label = element("tosPlayer.stateLabel")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", state), object: label
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The embed moves to the external screen once playback is running; the phone
    /// then shows its own controls, which drive the player through the JS bridge.
    /// "Play on Phone" in the more menu brings the embed back.
    func testPlaybackMovesToExternalDisplayAndBack() throws {
        // Registered before launch: the notification can fire before any UI query
        // would have a chance to see the player.
        let timeAdvanced = XCTDarwinNotificationExpectation(
            notificationName: "com.void.smarttube.tosplayer.timeadvanced"
        )
        app.launch()
        guard XCTWaiter().wait(for: [timeAdvanced], timeout: 60) == .completed else {
            throw XCTSkip("video never started playing — network / YouTube availability")
        }

        let overlay = element("tosPlayer.externalDisplayOverlay")
        XCTAssertTrue(overlay.waitForExistence(timeout: 10),
                      "phone should show its own controls once the embed is on the external display")

        // Transport controls reach the player.
        let playPause = element("tosPlayer.externalDisplay.playPauseButton")
        if !playPause.waitForExistence(timeout: 5) {
            captureState("playPauseMissing", in: app)
            XCTFail("play/pause button missing")
        }
        playPause.tap()
        XCTAssertTrue(waitForState("paused"), "pause from the phone did not reach the player")
        playPause.tap()
        XCTAssertTrue(waitForState("playing"), "play from the phone did not reach the player")

        // The more menu offers the way back to the phone.
        let moreButton = element("tosPlayer.moreButton")
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "more button missing while on external display")
        moreButton.tap()
        let row = element("tosPlayer.moreMenu.externalDisplayRow")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "external display row missing from more menu")
        row.tap()

        let overlayGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: overlay
        )
        XCTAssertEqual(XCTWaiter().wait(for: [overlayGone], timeout: 10), .completed,
                       "embed should return to the phone after 'Play on Phone'")
        XCTAssertTrue(waitForState("playing"), "playback should continue on the phone")
    }

    /// A new video has to load on the phone (the IFrame's config check fails in the
    /// external window) and move back to the external display once it plays.
    func testNextVideoReloadsOnPhoneAndReturnsToExternalDisplay() throws {
        let timeAdvanced = XCTDarwinNotificationExpectation(
            notificationName: "com.void.smarttube.tosplayer.timeadvanced"
        )
        app.launch()
        guard XCTWaiter().wait(for: [timeAdvanced], timeout: 60) == .completed else {
            throw XCTSkip("video never started playing — network / YouTube availability")
        }
        let overlay = element("tosPlayer.externalDisplayOverlay")
        XCTAssertTrue(overlay.waitForExistence(timeout: 10), "overlay missing before next")

        let next = element("tosPlayer.externalDisplay.nextButton")
        XCTAssertTrue(next.waitForExistence(timeout: 5), "next button missing")
        // Related videos arrive asynchronously; without them next is a no-op.
        let nextLoaded = XCTDarwinNotificationExpectation(
            notificationName: "com.void.smarttube.tosplayer.loadstarted"
        )
        next.tap()
        guard XCTWaiter().wait(for: [nextLoaded], timeout: 15) == .completed else {
            throw XCTSkip("next video never started loading — related videos unavailable")
        }

        let overlayGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: overlay
        )
        XCTAssertEqual(XCTWaiter().wait(for: [overlayGone], timeout: 10), .completed,
                       "new video should load on the phone, not on the external display")
        XCTAssertTrue(overlay.waitForExistence(timeout: 45),
                      "new video should move to the external display once it plays")
        XCTAssertTrue(waitForState("playing"), "new video should be playing")
    }
}
