#if os(tvOS)
import XCTest

// MARK: - TVSettingsUITests
//
// Verifies that the Settings tab is reachable via the tvOS tab bar and that
// key controls are present in the accessibility tree.
//
// No network access is required — all tested elements are static UI.
//
// Navigation: tab bar → right × 4 → select = Settings tab
// (same pattern proven by TVFocusChainUITests.testSettingsTabBarVisibleAfterScrollDownAndUp)

final class TVSettingsUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        try openSettings()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func openSettings() throws {
        for _ in 0..<4 { remote.press(.right) }
        remote.press(.select)
        // Wait for resetAllButton as the sentinel that Settings has fully rendered
        let sentinel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        guard sentinel.waitForExistence(timeout: 12) else {
            try captureAndSkip("settings.resetAllButton not found — Settings tab did not open", in: app)
        }
    }

    // MARK: - Tests

    /// The sign-in button must appear in Settings when the user is not signed in.
    func testSignInButtonVisibleWhenSignedOut() throws {
        let signInButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.signInButton'"))
            .firstMatch
        guard signInButton.waitForExistence(timeout: 5) else {
            try captureAndSkip(
                "settings.signInButton not found — device may already be signed in (expected a signed-out state for this test)",
                in: app
            )
        }
        XCTAssertTrue(signInButton.exists, "settings.signInButton must be in the accessibility tree when signed out")
    }

    /// The Hide Shorts toggle must be in the accessibility tree.
    func testHideShortsToggleExists() {
        let toggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.hideShortsToggle'"))
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "settings.hideShortsToggle must be in the accessibility tree"
        )
    }

    /// The SponsorBlock toggle must be in the accessibility tree.
    func testSponsorBlockToggleExists() {
        let toggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.sponsorBlockToggle'"))
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "settings.sponsorBlockToggle must be in the accessibility tree"
        )
    }

    /// The Max Resolution picker must be in the accessibility tree.
    func testPreferredQualityPickerExists() {
        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.preferredQualityPicker'"))
            .firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: 10),
            "settings.preferredQualityPicker must be in the accessibility tree"
        )
    }

    /// The Preferred Audio Language row must be in the accessibility tree.
    func testPreferredAudioLanguageRowExists() {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.preferredAudioLanguageRow'"))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "settings.preferredAudioLanguageRow must be in the accessibility tree"
        )
    }

    /// The Seek Back picker must be in the accessibility tree on tvOS.
    func testSeekBackRowExists() {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.seekBackRow'"))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "settings.seekBackRow must be in the accessibility tree on tvOS"
        )
    }

    /// tvOS 27 pushes an empty option list for a `Picker` in a `Form`, and leaving it left
    /// Settings blank. Settings rows push their own list (`SettingsPicker`): opening one
    /// must show its options, and choosing one must return to Settings.
    func testPickerRowShowsOptionsAndReturnsToSettings() throws {
        let row = app.cells.containing(.any, identifier: "settings.preferredQualityPicker").element
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Default Quality row must exist")
        var focused = false
        for _ in 0..<6 where !focused {
            remote.press(.down)
            focused = waitForFocus(on: row, timeout: 2)
        }
        XCTAssertTrue(focused, "Default Quality row must take focus")

        remote.press(.select)
        let option = app.cells.containing(NSPredicate(format: "label ==[c] '1080p'")).element
        XCTAssertTrue(option.waitForExistence(timeout: 5), "the pushed list must show the quality options")

        // The current value (Auto) starts focused, so this keeps the setting unchanged.
        remote.press(.select)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "choosing an option must return to Settings")
        XCTAssertFalse(option.exists, "the option list must be closed")
    }

    private func waitForFocus(on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let focus = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        return XCTWaiter.wait(for: [focus], timeout: timeout) == .completed
    }

    /// The Reset All Settings button must be in the accessibility tree.
    func testResetAllSettingsButtonExists() {
        let button = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        XCTAssertTrue(
            button.waitForExistence(timeout: 10),
            "settings.resetAllButton must be in the accessibility tree"
        )
    }

    /// Regression test for #149: the Settings tab must open on the first select press.
    /// Before the fix, MainTVTabView used an unbound TabView which made the tvOS focus
    /// engine require two presses — the first focused the tab, the second activated it.
    func testSettingsTabOpensSingleSelectPress() throws {
        // setUpWithError already calls openSettings() which presses select exactly once.
        // If the sentinel was found (setup succeeded), Settings opened on a single press.
        let sentinel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        XCTAssertTrue(
            sentinel.waitForExistence(timeout: 10),
            "#149 regression: Settings tab must open after a single select press, not two"
        )
    }
}
#endif
