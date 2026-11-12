import CoreGraphics
import SwiftUI
import Testing

@testable import SmartTubeIOS

@Suite("Shorts video layout")
struct ShortsVideoLayoutTests {

    /// Shorts tab on an iPhone 17/18 Pro: the page runs from the top of the screen
    /// (under the Dynamic Island) down to the tab bar.
    @Test("Shorts tab on a Dynamic Island iPhone: video starts below the status bar and reaches the progress bar")
    func dynamicIslandTab() {
        let layout = ShortsVideoLayout(
            page: CGSize(width: 402, height: 791), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 0, trailing: 0))

        #expect(layout.box.minY == 62)
        #expect(layout.box.maxY == 791)
        // Fills the box: no black band above or below the video.
        #expect(layout.videoSize.height == layout.box.height)
        #expect(layout.videoSize.width >= layout.box.width)
        // Only a sliver is cropped off the sides.
        #expect(layout.videoSize.width - layout.box.width < 10)
        #expect(layout.boxCenterOffset == 31)
    }

    @Test("Full-screen player keeps the video above the home indicator")
    func presentedFullScreen() {
        let layout = ShortsVideoLayout(
            page: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))

        #expect(layout.box.minY == 62)
        #expect(layout.box.maxY == 840)
        #expect(layout.videoSize.height == layout.box.height)
        #expect(layout.videoSize.width >= layout.box.width)
    }

    @Test("Large iPhone fills the box too")
    func proMaxTab() {
        let layout = ShortsVideoLayout(
            page: CGSize(width: 440, height: 873), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 0, trailing: 0))

        #expect(layout.videoSize.height == layout.box.height)
        #expect(layout.videoSize.width >= layout.box.width)
    }

    /// iPhone SE: the box is shorter than 9:16, and filling would cut ~10 % off the
    /// top and bottom, so the video fits with narrow bars at the sides.
    @Test("iPhone SE fits the video instead of cropping it")
    func homeButtonIPhoneFits() {
        let layout = ShortsVideoLayout(
            page: CGSize(width: 375, height: 618), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))

        #expect(layout.box.minY == 20)
        #expect(layout.box.maxY == 618)
        #expect(layout.videoSize.height == layout.box.height)
        #expect(layout.videoSize.width < layout.box.width)
        #expect(abs(layout.videoSize.width / layout.videoSize.height - ShortsVideoLayout.videoAspect) < 0.001)
    }

    @Test("iPad fits the video between bars at the sides")
    func iPadFits() {
        let layout = ShortsVideoLayout(
            page: CGSize(width: 820, height: 1115), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 0, trailing: 0))

        #expect(layout.videoSize.height == layout.box.height)
        #expect(layout.videoSize.width < layout.box.width)
    }

    /// Measured in the Shorts tab on an iPhone 18 Pro: the page starts at the top of
    /// the screen, the controls 62 pt lower, and both end at the tab bar.
    @Test("Insets come from where the controls sit on the page")
    func insetsFromControlsFrame() {
        let layout = ShortsVideoLayout(
            pageFrame: CGRect(x: 0, y: 0, width: 402, height: 791),
            controlsFrame: CGRect(x: 0, y: 62, width: 402, height: 729))

        #expect(layout.box == CGRect(x: 0, y: 62, width: 402, height: 729))
        #expect(layout.videoSize.height == 729)
    }

    @Test("Full-screen player: the controls stop above the home indicator")
    func insetsFromControlsFramePresented() {
        let layout = ShortsVideoLayout(
            pageFrame: CGRect(x: 0, y: 0, width: 402, height: 874),
            controlsFrame: CGRect(x: 0, y: 62, width: 402, height: 778))

        #expect(layout.box == CGRect(x: 0, y: 62, width: 402, height: 778))
    }

    @Test("Before the controls are measured the video uses the whole page")
    func unmeasuredControlsFrame() {
        let layout = ShortsVideoLayout(
            pageFrame: CGRect(x: 0, y: 0, width: 402, height: 791), controlsFrame: .zero)

        #expect(layout.box == CGRect(x: 0, y: 0, width: 402, height: 791))
    }

    @Test("An empty page has no video size")
    func emptyPage() {
        let layout = ShortsVideoLayout(page: .zero, safeArea: EdgeInsets())
        #expect(layout.videoSize == .zero)
    }
}
