import SwiftUI

/// The display of Casio's module 593 (F-91W, A158W, A168W, …): PM / 24H, weekday, date, H:MM and
/// live seconds. Measured once, from the F-91W photo, in its 389.5 × 184.5 glass; every model with
/// this module places it in its own glass (`placed(in:)`), so they all show the same layout.
struct Module593Display: View {
    /// The glass the layout was measured in.
    static let glass = CGSize(width: 389.5, height: 184.5)
    /// Width of the big digits relative to DSEG's (the module's digits are narrower).
    static let digitSqueeze: CGFloat = 0.9

    let context: CasioFaceContext
    let style: LCDStyle

    var body: some View {
        let parts = context.displayParts(blankDigit: style.digits.blankDigit)
        ZStack(alignment: .topLeading) {
            // PM in the afternoon on a 12-hour clock (measured on the F-91W photo); 24H on a 24-hour
            // clock, a smaller mark further right (measured on the A158W photo).
            if parts.marker == "PM" {
                Text("PM")
                    .font(.system(size: 29.3, weight: .bold))
                    .foregroundStyle(style.ink)
                    .place(centerX: 37, centerY: 52)
            } else if parts.marker == "24H" {
                Text("24H")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(style.ink)
                    .place(centerX: 87.3, centerY: 53.1)
            }
            // Day of week and date share the top row.
            LCDText(
                text: parts.weekday, font: style.letters, glyph: 43, edge: .leading(130), baseline: 55.5, tracking: 7.5,
                style: style)
            LCDText(
                text: parts.day, font: style.digits, glyph: 47.5, edge: .trailing(380.7), baseline: 60, width: 120,
                tracking: 4.5, style: style)
            LiveHoursMinutes(
                context: context, font: style.digits, glyph: 88.5, trailing: 279, baseline: 166,
                xScale: Self.digitSqueeze, style: style)
            LiveSeconds(
                context: context, glyph: 67, trailing: 382, baseline: 166, xScale: Self.digitSqueeze, style: style)
        }
        .lcdSegmentShadow(style)
        .frame(width: Self.glass.width, height: Self.glass.height, alignment: .topLeading)
    }

    /// The display in a model's glass (canvas coordinates): scaled to the glass's width and centred
    /// vertically, so a taller glass (a case extended to fill the widget) gets even margins.
    /// `shift` moves it down: each case's window frames the same LCD at a slightly different spot.
    static func placed(
        in glass: CGRect, shift: CGFloat = 0, context: CasioFaceContext, style: LCDStyle
    )
        -> some View
    {
        let scale = glass.width / Self.glass.width
        return Module593Display(context: context, style: style)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: glass.minX, y: glass.minY + (glass.height - Self.glass.height * scale) / 2 + shift)
    }
}
