import CoreGraphics
import SwiftUI

/// Where a Short's video sits on a pager page.
///
/// The video gets the part of the page below the status bar / Dynamic Island and
/// above the progress bar (`box`). It fills that box, cropping a little off two
/// edges, as long as the crop stays small: on every Face ID iPhone the box is only
/// slightly taller than 9:16, so filling leaves no black band above or below the
/// video. Where filling would cut off too much (iPhone SE in the Shorts tab, iPad)
/// the video fits instead, centered in the box.
///
/// With `fillsScreen` (Settings › Shorts › Fill Screen) the box starts at the top of
/// the page, behind the status bar, as in the official app, and a box narrower than
/// 9:16 is always filled however much that crops off the sides.
struct ShortsVideoLayout: Equatable {
    /// Shorts are 9:16.
    static let videoAspect: CGFloat = 9.0 / 16.0
    /// Largest share of the video's width or height that filling may crop.
    static let maxFillCrop: CGFloat = 0.1

    /// The pager page.
    let page: CGSize
    /// The area the video may use, in page coordinates.
    let box: CGRect
    /// The video's size, centered on `box`. Larger than `box` in one dimension when
    /// it fills (clip it to `box`); never larger in either when it fits.
    let videoSize: CGSize

    /// `page` is the pager page (its top runs under the status bar, as the pager
    /// ignores the top safe area). `safeArea` is how far the controls sit inside it:
    /// the top inset keeps the video below the status bar, the bottom one (full-screen
    /// player only) keeps it above the home indicator, where the progress bar sits.
    /// `fillsScreen` ignores the top inset and fills the box (see the type's doc).
    init(page: CGSize, safeArea: EdgeInsets, fillsScreen: Bool = false) {
        self.page = page
        let top = fillsScreen ? 0 : min(max(safeArea.top, 0), page.height)
        let bottom = min(max(safeArea.bottom, 0), page.height - top)
        box = CGRect(x: 0, y: top, width: page.width, height: page.height - top - bottom)
        videoSize = Self.videoSize(in: box.size, fillsScreen: fillsScreen)
    }

    /// `pageFrame` is the pager page and `controlsFrame` the player's safe-area frame
    /// (where the overlay with the progress bar sits), both in one coordinate space.
    /// The page's own safe-area insets can't be used: it ignores the top one, and in
    /// the Shorts tab it reports the tab bar as a bottom inset although it already
    /// ends above it. An unmeasured `controlsFrame` (empty) means no insets.
    init(pageFrame: CGRect, controlsFrame: CGRect, fillsScreen: Bool = false) {
        let insets =
            controlsFrame.isEmpty
            ? EdgeInsets()
            : EdgeInsets(
                top: max(0, controlsFrame.minY - pageFrame.minY), leading: 0,
                bottom: max(0, pageFrame.maxY - controlsFrame.maxY), trailing: 0)
        self.init(page: pageFrame.size, safeArea: insets, fillsScreen: fillsScreen)
    }

    /// Vertical offset that moves a view centered on the page to the center of `box`.
    var boxCenterOffset: CGFloat { box.midY - page.height / 2 }

    private static func videoSize(in box: CGSize, fillsScreen: Bool) -> CGSize {
        guard box.width > 0, box.height > 0 else { return .zero }
        let widthBound = box.width / videoAspect <= box.height
        let fit =
            widthBound
            ? CGSize(width: box.width, height: box.width / videoAspect)
            : CGSize(width: box.height * videoAspect, height: box.height)
        let fill =
            widthBound
            ? CGSize(width: box.height * videoAspect, height: box.height)
            : CGSize(width: box.width, height: box.width / videoAspect)
        // Filling a box narrower than 9:16 crops the sides only.
        if fillsScreen && widthBound { return fill }
        let crop = 1 - fit.width / fill.width
        return crop <= maxFillCrop ? fill : fit
    }
}
