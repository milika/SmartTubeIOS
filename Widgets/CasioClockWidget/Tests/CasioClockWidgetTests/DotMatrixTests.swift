import Foundation
import Testing

@testable import CasioClockWidget

@Suite("Dot-matrix LCD characters")
struct DotMatrixTests {
    @Test("digits, dot and dash are 5×7 bitmaps; unknown characters are blank")
    func glyphs() {
        for ch in "0123456789.-" {
            let rows = DotMatrixText.glyph(ch)
            #expect(rows.count == 7, "\(ch)")
            #expect(rows.allSatisfy { $0.count == 5 }, "\(ch)")
            #expect(rows.joined().contains("#"), "\(ch)")
        }
        #expect(DotMatrixText.glyph(" ").joined().contains("#") == false)
    }

    @Test("G-Shock date: day first ('28. 6') or month first (' 6-28') like the locale")
    func dateText() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 28))!
        #expect(GMWB5000Face.dateText(d, calendar: cal, dayFirst: true) == "28. 6")
        #expect(GMWB5000Face.dateText(d, calendar: cal, dayFirst: false) == " 6-28")
        let d2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        #expect(GMWB5000Face.dateText(d2, calendar: cal, dayFirst: true) == " 3.11")
    }
}
