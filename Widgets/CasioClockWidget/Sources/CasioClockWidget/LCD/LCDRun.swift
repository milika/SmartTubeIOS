import CoreGraphics

/// One measured line of LCD characters - a weekday, a date, the time, the seconds: how tall the
/// glyphs are, which edge is anchored where, the baseline, and how the module's characters differ
/// from DSEG's (narrower or wider: `xScale`; closer or further apart: `tracking`, and for the time
/// `colonGap`). Points before `xScale`, in the display's canvas coordinates. A display declares its
/// runs as a table (`LCDModuleDisplay.runs`) and passes them to LCDText, LiveHoursMinutes and
/// LiveSeconds.
struct LCDRun {
    var glyph: CGFloat
    var edge: LCDText.Edge
    var baseline: CGFloat
    var xScale: CGFloat = 1
    var tracking: CGFloat = 0
    /// Extra space around the time's colon (LiveHoursMinutes).
    var colonGap: CGFloat = 0
    /// Width of LCDText's frame (long enough for the run's text).
    var width: CGFloat = 200

    /// The same run anchored at another trailing edge (a row of digit groups, like a year and a date).
    func trailing(_ x: CGFloat) -> LCDRun {
        var run = self
        run.edge = .trailing(x)
        return run
    }

    /// The anchored x (the leading or trailing edge).
    var x: CGFloat {
        switch edge {
        case .leading(let x), .trailing(let x): x
        }
    }
}

extension LCDText {
    init(text: String, font: LCDFont, run: LCDRun, style: LCDStyle) {
        self.init(
            text: text, font: font, glyph: run.glyph, edge: run.edge, baseline: run.baseline, width: run.width,
            tracking: run.tracking, xScale: run.xScale, style: style)
    }
}

extension LiveHoursMinutes {
    /// `run.edge` must be trailing.
    init(context: CasioFaceContext, font: LCDFont, run: LCDRun, style: LCDStyle) {
        self.init(
            context: context, font: font, glyph: run.glyph, trailing: run.x, baseline: run.baseline,
            xScale: run.xScale, colonGap: run.colonGap, tracking: run.tracking, style: style)
    }
}

extension LiveSeconds {
    /// `run.edge` must be trailing.
    init(context: CasioFaceContext, run: LCDRun, style: LCDStyle) {
        self.init(
            context: context, glyph: run.glyph, trailing: run.x, baseline: run.baseline, xScale: run.xScale,
            tracking: run.tracking, style: style)
    }
}
