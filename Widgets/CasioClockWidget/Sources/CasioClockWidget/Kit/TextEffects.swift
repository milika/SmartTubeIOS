import SwiftUI

extension View {
    /// Thickens the strokes by overlaying copies shifted by `amount` points, for print that is
    /// bolder than any weight of the stand-in font (Michroma has a single weight).
    func emboldened(_ amount: CGFloat) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                self.offset(x: amount * cos(angle), y: amount * sin(angle))
            }
            self
        }
    }

    /// Slants the view like printed italics ("F-91W", "WR") for fonts without an italic face,
    /// where `.italic()` would draw them upright.
    func oblique() -> some View {
        self.transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.21, d: 1, tx: 6, ty: 0))
    }
}
