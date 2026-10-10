import SwiftUI

// The AE-1200WH's four LCD windows (named after the watch; its module number is not checked here),
// each an LCDModuleDisplay measured on a front-on product image of the AE-1200WH, in that face's
// canvas coordinates (`canvasOrigin` is where each glass sits on that canvas).

/// The main window: the weekday and month-date above a rule, PM, a large H:MM and the seconds, in
/// slanted segments. The window is L-shaped; the face covers its upper-left corner.
struct AE1200WHDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 334, height: 141.5)
    static let canvasOrigin = CGPoint(x: 163.5, y: 362)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        let date = context.calendar.dateComponents([.month, .day], from: context.date)
        inGlass(style: style) {
            Rectangle().fill(style.ink).frame(width: 175.5, height: 1.5).offset(x: 322, y: 406.25)
            Rectangle().fill(style.ink).frame(width: 1.5, height: 44).offset(x: 409.5, y: 362)
            LCDText(
                text: DisplayParts.weekday3(for: context.date, calendar: context.calendar), font: style.letters,
                run: Self.weekday, style: style)
            LCDText(text: String(date.month ?? 1), font: style.digits, run: Self.month, style: style)
            Rectangle().fill(style.ink).frame(width: 6.5, height: 4).offset(x: 446, y: 379.5)
            LCDText(
                text: DisplayParts.twoCells(date.day ?? 1, blank: style.digits.blankDigit), font: style.digits,
                run: Self.day, style: style)
            if parts.isPM {
                InkText(text: "PM", font: CaseFont.michroma)
                    .placed(in: CGRect(x: 172, y: 429.5, width: 37, height: 11.5), color: style.ink, bold: 1)
            }
            LiveHoursMinutes(context: context, font: style.digits, run: Self.time, style: style)
            LiveSeconds(context: context, run: Self.seconds, style: style)
        }
    }

    // Measured on the AE-1200WH image (canvas points).
    static let weekday = LCDRun(glyph: 31.5, edge: .trailing(406), baseline: 398, xScale: 0.8)
    static let month = LCDRun(glyph: 31.5, edge: .trailing(446), baseline: 398, xScale: 0.76)
    static let day = LCDRun(glyph: 31.5, edge: .trailing(492.5), baseline: 398, xScale: 0.76, tracking: -1.3)
    static let time = LCDRun(
        glyph: 79, edge: .trailing(407), baseline: 494.5, xScale: 0.855, tracking: -4.9, colonGap: 11.8)
    static let seconds = LCDRun(glyph: 56.5, edge: .trailing(490), baseline: 494.5, xScale: 0.8)
    static let runs = [weekday, month, day, time, seconds]
}

/// The round window: an LCD dial with a ring, a crosshair and a centre disc. The watch's hands
/// (hour and minute, and the seconds on the ring) are left out: a widget redraws only at its
/// timeline entries, once an hour, so they could not keep time.
struct AE1200WHDialDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 126, height: 126)
    static let canvasOrigin = CGPoint(x: 172.5, y: 221)
    static let runs: [LCDRun] = []
    /// The centre of the ring of ticks and numerals around the window.
    static let center = CGPoint(x: 236, y: 282.25)
    /// The window's centre and the crosshair's: on the image they sit a little off the ring's.
    static let window = CGPoint(x: 235.5, y: 284)
    static let hub = CGPoint(x: 237, y: 282.25)

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let hub = Self.hub
        inGlass(style: style) {
            Circle().stroke(style.ink, lineWidth: 1.5).frame(width: 107, height: 107)
                .offset(x: hub.x - 53.5, y: hub.y - 53.5)
            Rectangle().fill(style.ink).frame(width: 2.5, height: 126).offset(x: hub.x - 0.75, y: Self.window.y - 63)
            Rectangle().fill(style.ink).frame(width: 126, height: 2).offset(x: Self.window.x - 63, y: hub.y - 1)
            Circle().fill(style.ink).frame(width: 42, height: 42).offset(x: hub.x - 21, y: hub.y - 21)
        }
    }
}

/// MUTE above a rule, ALM and SIG below it.
struct AE1200WHIndicatorDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 153.5, height: 38)
    static let canvasOrigin = CGPoint(x: 344.5, y: 204.5)
    static let runs: [LCDRun] = []

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        inGlass(style: style) {
            Rectangle().fill(style.ink).frame(width: 153.5, height: 2.5).offset(x: 344.5, y: 221)
            word("MUTE", CGRect(x: 381, y: 207.5, width: 80.5, height: 10))
            word("ALM", CGRect(x: 356, y: 226, width: 57, height: 11))
            word("SIG", CGRect(x: 434.5, y: 225.5, width: 52, height: 11))
        }
    }

    private func word(_ text: String, _ box: CGRect) -> some View {
        InkText(text: text, font: CaseFont.michroma).placed(in: box, color: style.ink, bold: 0.5)
    }
}

/// The world map: the continents in grey, a dotted grid, a solid line and the dark segments of
/// the zone shown (as on the image).
struct AE1200WHMapDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 153.5, height: 85.5)
    static let canvasOrigin = CGPoint(x: 344.5, y: 259.5)
    static let runs: [LCDRun] = []

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        inGlass(style: style) {
            MapShape().fill(style.ink.opacity(0.5))
            GridDots().fill(style.ink)
            Rectangle().fill(style.ink).frame(width: 153.5, height: 2).offset(x: 344.5, y: 311.5)
            ZoneShape().fill(style.ink)
        }
    }

    /// The continents, traced from the image in 1 pt rows.
    private struct MapShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            for row in AE1200WHMapDisplay.continents {
                path.addRect(CGRect(x: rect.minX + row[1], y: rect.minY + row[0], width: row[2], height: 1))
            }
            return path
        }
    }

    /// The zone's dark segments, traced from the image in 1 pt rows.
    private struct ZoneShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            for row in AE1200WHMapDisplay.zone {
                path.addRect(CGRect(x: rect.minX + row[1], y: rect.minY + row[0], width: row[2], height: 1))
            }
            return path
        }
    }

    /// The zone's dark segments in 1 pt rows: [y, x, width].
    static let zone: [[CGFloat]] = [
        [269, 457, 2], [270, 456, 4], [271, 456, 4], [272, 456, 5], [273, 456, 5], [274, 456, 5], [275, 456, 5],
        [276, 456, 5], [277, 456, 6], [278, 456, 7], [279, 458, 5], [280, 458, 5], [281, 458, 6], [282, 458, 7],
        [283, 458, 7], [284, 458, 6], [285, 458, 3], [286, 458, 2], [289, 472, 2], [290, 472, 2], [291, 472, 2],
        [292, 472, 2], [293, 471, 3], [294, 471, 2], [295, 469, 4], [296, 470, 1], [310, 473, 4], [311, 473, 4],
        [314, 471, 3], [315, 471, 4], [316, 470, 6], [317, 470, 6], [318, 470, 6], [319, 470, 6], [320, 470, 6],
        [321, 470, 5.5], [322, 470, 5.5], [323, 470, 5.5], [324, 470, 5.5], [325, 470, 5.5], [326, 470, 5.5],
        [327, 470, 5.5],
        [328, 471, 4.5], [329, 474, 2],
    ]

    /// Dotted grid lines: four meridians and three parallels.
    private struct GridDots: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let pitch: CGFloat = 3.2
            let dot: CGFloat = 1.2
            for x: CGFloat in [365, 407.5, 444.75, 481.25] {
                var y: CGFloat = 263
                while y < 343 {
                    path.addRect(CGRect(x: rect.minX + x - dot / 2, y: rect.minY + y, width: dot, height: dot))
                    y += pitch
                }
            }
            for y: CGFloat in [278.25, 295.5, 326.25] {
                var x: CGFloat = 347
                while x < 495 {
                    path.addRect(CGRect(x: rect.minX + x, y: rect.minY + y - dot / 2, width: dot, height: dot))
                    x += pitch
                }
            }
            return path
        }
    }

    /// The continents in 1 pt rows: [y, x, width].
    static let continents: [[CGFloat]] = [
        [265, 364, 2], [265, 391, 10], [266, 364, 2], [266, 391, 10], [267, 393, 8], [267, 446, 6], [268, 393, 8],
        [268, 420, 4],
        [268, 445, 10], [269, 393, 8], [269, 420, 4], [269, 440, 16], [270, 385, 4], [270, 393, 8], [270, 419, 8],
        [270, 438, 18],
        [270, 461, 7], [271, 385, 4], [271, 393, 8], [271, 416, 12], [271, 433, 2], [271, 436, 20], [271, 460, 10],
        [272, 355, 6],
        [272, 369, 3], [272, 386, 5], [272, 394, 6], [272, 416, 40], [272, 461, 10], [273, 355, 23], [273, 386, 5],
        [273, 395, 5],
        [273, 415, 41], [273, 461, 11], [274, 354, 28], [274, 386, 5], [274, 395, 4], [274, 415, 41], [274, 461, 13],
        [275, 352, 30],
        [275, 396, 2], [275, 415, 41], [275, 461, 14], [276, 352, 30], [276, 415, 41], [276, 462, 13], [277, 354, 23],
        [277, 415, 5],
        [277, 422, 34], [277, 462, 13], [278, 357, 20], [278, 423, 33], [278, 463, 9], [279, 357, 20], [279, 384, 8],
        [279, 423, 34],
        [279, 463, 8], [280, 357, 21], [280, 384, 9], [280, 408, 3], [280, 423, 35], [280, 463, 8], [281, 357, 36],
        [281, 408, 3],
        [281, 416, 42], [281, 465, 6], [282, 359, 34], [282, 408, 3], [282, 414, 44], [282, 465, 6], [283, 359, 33],
        [283, 408, 3],
        [283, 414, 44], [283, 465, 6], [284, 359, 33], [284, 413, 45], [284, 462, 9], [285, 359, 18], [285, 379, 13],
        [285, 412, 46],
        [285, 461, 10], [286, 359, 18], [286, 383, 9], [286, 412, 46], [286, 461, 10], [287, 360, 17], [287, 383, 7],
        [287, 412, 59],
        [288, 361, 15], [288, 383, 5], [288, 410, 60], [289, 361, 27], [289, 408, 27], [289, 438, 32], [290, 361, 25],
        [290, 408, 27],
        [290, 438, 31], [291, 360, 26], [291, 408, 26], [291, 438, 31], [292, 360, 26], [292, 408, 15], [292, 438, 26],
        [293, 360, 24],
        [293, 408, 15], [293, 438, 26], [294, 360, 24], [294, 408, 7], [294, 419, 3], [294, 438, 26], [295, 366, 13],
        [295, 438, 26],
        [296, 366, 13], [296, 432, 33], [297, 362, 17], [297, 415, 4], [297, 431, 36], [298, 362, 17], [298, 414, 5],
        [298, 428, 39],
        [299, 362, 14], [299, 412, 55], [300, 365, 7], [300, 408, 22], [300, 433, 4], [300, 445, 21], [301, 365, 7],
        [301, 408, 22],
        [301, 433, 6], [301, 445, 19], [302, 365, 7], [302, 408, 23], [302, 433, 8], [302, 446, 8], [302, 455, 7],
        [303, 365, 7],
        [303, 408, 23], [303, 434, 7], [303, 447, 6], [303, 456, 6], [304, 369, 3], [304, 408, 24], [304, 434, 3],
        [304, 447, 4],
        [304, 457, 6], [305, 408, 24], [305, 447, 4], [305, 457, 6], [306, 378, 7], [306, 405, 27], [306, 448, 2],
        [306, 458, 5],
        [307, 377, 10], [307, 404, 29], [307, 459, 1], [308, 376, 12], [308, 405, 28], [309, 376, 13], [309, 405, 35],
        [309, 465, 2],
        [310, 376, 14], [310, 408, 32], [310, 465, 2], [311, 378, 11], [311, 409, 30], [311, 465, 2], [314, 374, 22],
        [314, 418, 19],
        [315, 374, 23], [315, 418, 19], [315, 476, 5], [316, 374, 23], [316, 418, 18], [316, 476, 5], [316, 489, 2],
        [317, 374, 21],
        [317, 419, 17], [317, 468, 2], [317, 476, 8], [317, 489, 2], [318, 374, 21], [318, 420, 16], [318, 467, 3],
        [318, 476, 9],
        [318, 489, 2], [319, 375, 19], [319, 420, 16], [319, 467, 3], [319, 476, 9], [320, 376, 17], [320, 420, 16],
        [320, 465, 5],
        [320, 477, 8], [321, 378, 12], [321, 420, 16], [321, 464, 6], [321, 477, 8], [322, 378, 11], [322, 420, 16],
        [322, 464, 6],
        [322, 477, 8], [323, 378, 10], [323, 420, 16], [323, 464, 6], [323, 477, 7], [324, 378, 9], [324, 420, 16],
        [324, 465, 5],
        [324, 477, 7], [325, 379, 6], [325, 421, 15], [325, 465, 5], [325, 478, 6], [326, 380, 5], [326, 421, 14],
        [327, 380, 5],
        [327, 421, 14], [328, 380, 5], [328, 421, 14], [329, 380, 5], [329, 421, 14], [330, 380, 5], [330, 421, 14],
        [331, 380, 5],
        [331, 421, 13], [332, 380, 5], [332, 421, 12], [333, 379, 5], [333, 421, 11], [334, 378, 5], [334, 422, 10],
        [335, 378, 5],
        [335, 423, 7], [336, 379, 4],
    ]
}
