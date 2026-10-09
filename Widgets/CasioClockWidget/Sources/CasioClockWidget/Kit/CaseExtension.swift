import CoreGraphics
import SwiftUI

/// How a face that is wider than tall is stretched to fill the square widget: its case is made
/// `amount` points taller, every element keeps its measured size, and the extra height is shared
/// out by band, top to bottom:
///
/// - the case, plate and lines grow by the full amount (`caseGrowth`);
/// - the LCD window and glass grow by half (`windowGrowth`) and move down a quarter, so the extra
///   space above and below the window is equal;
/// - the side labels next to the window's upper half move down a quarter, those centred beside it
///   half, those next to its lower half three quarters;
/// - the print below the window moves down the full amount.
///
/// Faces draw in their reference image's coordinates and place each group in its band.
struct CaseExtension {
    let amount: CGFloat

    /// Set while rendering a face to compare it with its reference image (ReferenceRenderTests):
    /// the case is not extended, so every element sits where it was measured.
    @TaskLocal static var referenceLayout = false

    init(amount: CGFloat) {
        self.amount = Self.referenceLayout ? 0 : amount
    }

    enum Band {
        case top, upperSides, display, middleSides, lowerSides, bottom
    }

    func offset(_ band: Band) -> CGFloat {
        switch band {
        case .top: 0
        case .upperSides, .display: amount / 4
        case .middleSides: amount / 2
        case .lowerSides: 3 * amount / 4
        case .bottom: amount
        }
    }

    /// Extra height of the case, the plate and its lines.
    var caseGrowth: CGFloat { amount }
    /// Extra height of the LCD window and its glass.
    var windowGrowth: CGFloat { amount / 2 }
}

extension View {
    /// Moves a group of a face into its band of the case extension.
    func band(_ band: CaseExtension.Band, of stretch: CaseExtension) -> some View {
        offset(y: stretch.offset(band))
    }
}
