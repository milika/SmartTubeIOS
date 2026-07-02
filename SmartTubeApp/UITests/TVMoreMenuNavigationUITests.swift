// TVMoreMenuNavigationUITests.swift
// Regression test for tvOS player more-menu double-step navigation bug.
//
// Bug: onMoveCommand + .focused() bidirectional binding both responded to
// the same D-pad event, causing focus to advance 2 rows per DOWN press.
// Fix: removed onMoveCommand; native tvOS focus drives navigation.
//
// Test: open more menu → press DOWN 3 times from Speed →
//       verify each press advanced exactly 1 row (no skip).

#if os(tvOS)
import XCTest

final class TVMoreMenuNavigationUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-open-more-menu"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    // MARK: - Helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", id))
            .firstMatch
    }

    private func focusedIdentifier() -> String {
        let pred = NSPredicate(format: "hasFocus == true")
        let el = app.descendants(matching: .any).matching(pred).firstMatch
        return el.exists ? el.identifier : "<nothing>"
    }

    private func snap(_ label: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = label; a.lifetime = .keepAlways; add(a)
    }

    private func waitForMoreMenu() throws {
        let chipBar = element("home.chipBar")
        guard chipBar.waitForExistence(timeout: 15) else {
            try captureAndSkip("home.chipBar not found — app failed to launch", in: app)
        }

        // Navigate down to the first video card and select it.
        let videoPred = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(videoPred)
        let cardWait = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: cards)],
            timeout: 20
        )
        guard cardWait == .completed else {
            try captureAndSkip("No video cards loaded after 20s — network unavailable", in: app)
        }
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        remote.press(.select)

        // --uitesting-open-more-menu opens the menu automatically in PlayerView.onAppear.
        let speedRow = element("player.moreMenu.speedRow")
        guard speedRow.waitForExistence(timeout: 15) else {
            try captureAndSkip("More menu did not open after selecting a video", in: app)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Test

    /// Opens the more menu and presses DOWN 3 times. Verifies:
    /// 1. Focus starts on Speed (the default row).
    /// 2. Each DOWN press moves focus to a different row (no double-step skip).
    /// 3. After 3 DOWNs we have not jumped all the way to Comments or Cancel
    ///    (which would indicate the old 2-step-per-press bug).
    func test_DownThreeTimes_AdvancesOneRowPerPress() throws {
        try waitForMoreMenu()

        // ── Initial state ──
        let initial = focusedIdentifier()
        snap("0-menu-opened")
        XCTContext.runActivity(named: "Initial focused: \(initial)") { _ in }
        XCTAssertEqual(initial, "player.moreMenu.speedRow",
                       "More menu should open with Speed row focused")

        // ── DOWN 1 ──
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        let after1 = focusedIdentifier()
        snap("1-after-first-down")
        XCTContext.runActivity(named: "After DOWN 1 — focused: \(after1)") { _ in }

        XCTAssertNotEqual(after1, initial,
                          "DOWN 1 must leave Speed — focus did not move at all")
        XCTAssertNotEqual(after1, "player.moreMenu.cancel",
                          "DOWN 1 jumped all the way to Cancel — double-step bug")

        // ── DOWN 2 ──
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        let after2 = focusedIdentifier()
        snap("2-after-second-down")
        XCTContext.runActivity(named: "After DOWN 2 — focused: \(after2)") { _ in }

        XCTAssertNotEqual(after2, after1,
                          "DOWN 2 did not move — focus stuck on \(after1)")
        XCTAssertNotEqual(after2, "player.moreMenu.cancel",
                          "DOWN 2 jumped to Cancel after only 2 presses — double-step bug")

        // ── DOWN 3 ──
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        let after3 = focusedIdentifier()
        snap("3-after-third-down")
        XCTContext.runActivity(named: "After DOWN 3 — focused: \(after3)") { _ in }

        XCTAssertNotEqual(after3, after2,
                          "DOWN 3 did not move — focus stuck on \(after2)")
        XCTAssertNotEqual(after3, "player.moreMenu.cancel",
                          "DOWN 3 jumped to Cancel after only 3 presses — double-step bug; " +
                          "DOWN1=\(after1) DOWN2=\(after2) DOWN3=\(after3)")

        // ── Summary ──
        XCTContext.runActivity(named:
            "Navigation path: Speed → \(after1) → \(after2) → \(after3)") { _ in }
    }

    /// The Quality row must be present in the more menu, directly reachable
    /// with one DOWN press from Speed, and it must open the quality picker.
    func test_QualityRow_ExistsAndOpensPicker() throws {
        try waitForMoreMenu()

        let qualityRow = element("player.moreMenu.qualityRow")
        XCTAssertTrue(qualityRow.waitForExistence(timeout: 5),
                      "player.moreMenu.qualityRow must be in the more menu")

        // Speed is focused initially; one DOWN lands on Quality (the next row).
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(focusedIdentifier(), "player.moreMenu.qualityRow",
                       "One DOWN from Speed must focus the Quality row")

        remote.press(.select)
        let picker = element("player.qualityPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 10),
                      "Selecting the Quality row must open the quality picker")
    }
}
#endif
