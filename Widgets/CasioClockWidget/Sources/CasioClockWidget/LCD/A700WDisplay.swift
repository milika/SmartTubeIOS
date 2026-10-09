import SwiftUI

/// Where the A700W's display shows its characters and marks (signal and alarm marks, PM, weekday and
/// day of month, H:MM and seconds), measured on one version's image: the A700WE (A700WDisplay) and
/// the negative version (A700WNegativeDisplay) frame the same layout a little differently.
struct A700WLayout {
    var signal: CGRect
    var bell: CGRect
    var pm: CGRect
    var weekday: LCDRun
    var day: LCDRun
    var time: LCDRun
    var seconds: LCDRun

    var runs: [LCDRun] { [weekday, day, time, seconds] }

    @ViewBuilder
    func characters(context: CasioFaceContext, style: LCDStyle) -> some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        SignalMark().fill(style.ink).frame(width: signal.width, height: signal.height)
            .offset(x: signal.minX, y: signal.minY)
        BellMark().fill(style.ink).frame(width: bell.width, height: bell.height).offset(x: bell.minX, y: bell.minY)
        if parts.isPM {
            InkText(text: "PM", font: CaseFont.michroma).placed(in: pm, color: style.ink, bold: 0.6)
        }
        LCDText(text: parts.weekday, font: style.letters, run: weekday, style: style)
        LCDText(text: parts.day, font: style.digits, run: day, style: style)
        LiveHoursMinutes(context: context, font: style.digits, run: time, style: style)
        LiveSeconds(context: context, run: seconds, style: style)
    }
}

/// The A700W's display (named after the watch; its module number is not checked here), measured on
/// a front-on product image of the A700WE-1A, in that face's canvas coordinates; `canvasOrigin` is
/// where its 354 × 176.5 glass sits on that canvas (`placed(in:)`). The marks are shown on, as in
/// the image.
struct A700WDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 354, height: 176.5)
    /// The glass's top-left corner on the A700W canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 128, y: 257)

    let context: CasioFaceContext
    let style: LCDStyle

    // Measured on the A700W image (canvas points).
    static let layout = A700WLayout(
        signal: CGRect(x: 143.5, y: 274.5, width: 38.5, height: 15),
        bell: CGRect(x: 193, y: 269.5, width: 23.5, height: 27.5),
        pm: CGRect(x: 143, y: 301, width: 35.5, height: 18.5),
        weekday: LCDRun(glyph: 38.5, edge: .leading(245.8), baseline: 314, xScale: 1.058, tracking: 5),
        day: LCDRun(glyph: 44, edge: .trailing(470.8), baseline: 319.5, xScale: 0.98, tracking: 2.3, width: 120),
        time: LCDRun(glyph: 83.5, edge: .trailing(385), baseline: 418.5, xScale: 0.8, tracking: 7.5, colonGap: -4.2),
        seconds: LCDRun(glyph: 63, edge: .trailing(473.6), baseline: 419, xScale: 0.762, tracking: 6.3))
    static let runs = layout.runs

    var body: some View {
        inGlass(style: style) { Self.layout.characters(context: context, style: style) }
    }
}

/// The A700W negative version's display: the same layout, measured on its image (light segments on
/// dark glass), in the A700W canvas coordinates; `canvasOrigin` is where its 348.5 × 171.5 glass
/// sits on that canvas.
struct A700WNegativeDisplay: LCDModuleDisplay {
    static let glass = CGSize(width: 348.5, height: 171.5)
    /// The glass's top-left corner on the A700W canvas the numbers below were measured on.
    static let canvasOrigin = CGPoint(x: 128, y: 258)

    let context: CasioFaceContext
    let style: LCDStyle

    // Measured on the negative version's image (canvas points).
    static let layout = A700WLayout(
        signal: CGRect(x: 149.5, y: 275.7, width: 37.1, height: 14.4),
        bell: CGRect(x: 200, y: 273.5, width: 18.5, height: 22),
        pm: CGRect(x: 149, y: 301.3, width: 34.2, height: 17.8),
        weekday: LCDRun(glyph: 37.1, edge: .leading(248), baseline: 313.8, xScale: 1.058, tracking: 4.8),
        day: LCDRun(glyph: 42.4, edge: .trailing(464.7), baseline: 319.1, xScale: 0.98, tracking: 2.2, width: 120),
        time: LCDRun(glyph: 80.4, edge: .trailing(384.1), baseline: 414.4, xScale: 0.8, tracking: 7.2, colonGap: -4),
        seconds: LCDRun(glyph: 60.7, edge: .trailing(467.4), baseline: 414.9, xScale: 0.762, tracking: 6.1))
    static let runs = layout.runs

    var body: some View {
        inGlass(style: style) { Self.layout.characters(context: context, style: style) }
    }
}
