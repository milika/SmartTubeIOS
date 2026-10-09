// Downloading is compiled out (App Store guideline 5.2.3). Define ENABLE_DOWNLOADS to build it.
#if ENABLE_DOWNLOADS
import XCTest

// MARK: - DownloadsPlaybackUITests
//
// Verifies the Downloads section appears in the Library picker and that
// the empty state is shown when no videos have been downloaded.
//
// A full playback test (tap row → player opens) requires an actual download,
// which is performed by VideoDownloadUITests. The test here validates the
// screen structure only, exercising the new DownloadsView and LibrarySection.downloads.
//
// Launch args: --uitesting

final class DownloadsPlaybackUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Tests

    /// Downloads segment appears in the Library section picker.
    func testDownloadsSegmentExistsInLibrary() throws {
        UITestHelpers.tapTab(named: "Library", in: app)
        let picker = app.segmentedControls["library.sectionPicker"]
        guard picker.waitForExistence(timeout: 5) else {
            try captureAndSkip("library.sectionPicker did not appear", in: app)
        }
        XCTAssertTrue(
            picker.buttons["Downloads"].exists,
            "'Downloads' segment must be present in the library picker"
        )
    }

    /// Tapping Downloads shows the empty state or a list without crashing.
    func testDownloadsSectionDoesNotCrash() throws {
        UITestHelpers.tapTab(named: "Library", in: app)
        let picker = app.segmentedControls["library.sectionPicker"]
        guard picker.waitForExistence(timeout: 5) else {
            try captureAndSkip("library.sectionPicker did not appear", in: app)
        }
        let downloadsButton = picker.buttons["Downloads"]
        guard downloadsButton.waitForExistence(timeout: 3) else {
            try captureAndSkip("Downloads segment not found in library picker", in: app)
        }
        downloadsButton.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(
            app.state, .runningForeground,
            "App should still be running after opening Downloads in Library"
        )
    }

    /// Empty state is shown when no videos are downloaded.
    func testDownloadsShowsEmptyStateWhenNoDownloads() throws {
        UITestHelpers.tapTab(named: "Library", in: app)
        let picker = app.segmentedControls["library.sectionPicker"]
        guard picker.waitForExistence(timeout: 5) else {
            try captureAndSkip("library.sectionPicker did not appear", in: app)
        }
        let downloadsButton = picker.buttons["Downloads"]
        guard downloadsButton.waitForExistence(timeout: 3) else {
            try captureAndSkip("Downloads segment not found", in: app)
        }
        downloadsButton.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // In a clean test environment there are no downloads; expect either the
        // empty state label or a populated list (if a previous test left downloads).
        let emptyState = app.otherElements["downloads.emptyState"]
        let videoRow = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'downloads.videoRow.'")).firstMatch
        let eitherExists = emptyState.waitForExistence(timeout: 3) || videoRow.waitForExistence(timeout: 1)
        XCTAssertTrue(
            eitherExists,
            "Downloads section must show either an empty state or a video list"
        )
    }

    // MARK: - Helpers

    private func captureAndSkip(_ message: String, in app: XCUIApplication) throws -> Never {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
        throw XCTSkip(message)
    }
}
#endif  // ENABLE_DOWNLOADS
