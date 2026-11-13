#if os(iOS)
import SwiftUI
import Testing
import UIKit

@testable import SmartTubeIOS

// The Home Shorts placeholder row once sized itself to its nine cards (~1,180 pt).
// Home stacks it above the video grid, so the whole stack — grid and chips — grew
// past the screen and showed zoomed-in, off-centre cards until the Shorts arrived.

@Suite("Shorts row placeholder layout")
@MainActor
struct ShortsRowPlaceholderLayoutTests {
    private let phoneWidth: CGFloat = 393

    @Test("the placeholder never asks for more width than it is offered")
    func staysWithinOfferedWidth() {
        let size = UIHostingController(rootView: ShortsRowPlaceholder())
            .sizeThatFits(in: CGSize(width: phoneWidth, height: 1_000))
        #expect(size.width <= phoneWidth)
    }

    @Test("a stack holding the placeholder keeps the screen's width")
    func keepsStackWidth() {
        let stack = VStack(spacing: 0) {
            ShortsRowPlaceholder()
            Color.clear.frame(height: 100)
        }
        let size = UIHostingController(rootView: stack)
            .sizeThatFits(in: CGSize(width: phoneWidth, height: 1_000))
        #expect(size.width <= phoneWidth)
    }

    @Test("the placeholder is as tall as the real row: card plus 4 pt above and 12 pt below")
    func matchesRowHeight() {
        let size = UIHostingController(rootView: ShortsRowPlaceholder())
            .sizeThatFits(in: CGSize(width: phoneWidth, height: 1_000))
        let rowHeight = ShortsRowSection.cardWidth * 16 / 9 + 16
        // Hosting rounds to whole pixels.
        #expect(abs(size.height - rowHeight) < 1, "placeholder \(size.height) pt, row \(rowHeight) pt")
    }
}
#endif
