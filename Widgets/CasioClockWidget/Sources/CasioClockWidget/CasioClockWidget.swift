import AppIntents
import CoreText
import SwiftUI
import WidgetKit

// MARK: - CasioClockWidget (experimental)
//
// A small Home Screen widget that is a live clock drawn as a Casio F-91W.
//
// How it stays live:
// - Hours and minutes come from a timeline with one entry per minute (an hour of entries,
//   then WidgetKit asks for the next hour), so the display changes exactly on the minute.
// - Widgets can't redraw every second, so the seconds are WidgetKit's own timer text
//   counting up from the start of the minute, clipped to its last two digits ("0:23" shows
//   as "23"). All LCD characters use the bundled DSEG fonts so the live seconds match the
//   rest of the display.
// - Tapping the widget runs CasioBacklightIntent: like pressing LIGHT on the watch, the LCD
//   glows green for a few seconds.

public struct CasioClockWidget: Widget {
    public static let kind = "CasioClockWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CasioClockProvider()) { entry in
            Button(intent: CasioBacklightIntent()) {
                CasioWatchFace(date: entry.date, backlit: entry.backlit)
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { CasioWatchFace.resin }
        }
        .configurationDisplayName("Casio F-91W")
        .description("A live digital clock in the style of the Casio F-91W. Tap it for the light.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Backlight

/// Turns the LCD light on for a few seconds, like the watch's LIGHT button.
public struct CasioBacklightIntent: AppIntent {
    public static let title: LocalizedStringResource = "Casio Light"
    public static let description = IntentDescription("Lights up the Casio F-91W widget for a few seconds.")
    public static let isDiscoverable = false

    static let duration: TimeInterval = 3
    static let defaultsKey = "CasioClockWidget.backlightUntil"

    public init() {}

    public func perform() async throws -> some IntentResult {
        // WidgetKit reloads the widget's timeline after a widget intent runs.
        UserDefaults.standard.set(Date().addingTimeInterval(Self.duration), forKey: Self.defaultsKey)
        return .result()
    }

    static func backlightUntil(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: defaultsKey) as? Date
    }
}

// MARK: - Timeline

struct CasioClockEntry: TimelineEntry {
    let date: Date
    var backlit = false
}

struct CasioClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> CasioClockEntry { CasioClockEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CasioClockEntry) -> Void) {
        completion(CasioClockEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CasioClockEntry>) -> Void) {
        let entries = Self.entries(from: Date(), backlightUntil: CasioBacklightIntent.backlightUntil())
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// The minute entries, preceded by a lit entry while the light is on.
    static func entries(from now: Date, backlightUntil: Date?, calendar: Calendar = .current) -> [CasioClockEntry] {
        guard let until = backlightUntil, until > now else { return minuteEntries(from: now, calendar: calendar) }
        return [CasioClockEntry(date: now, backlit: true), CasioClockEntry(date: until)]
            + minuteEntries(from: until, calendar: calendar).filter { $0.date > until }
    }

    /// One entry at the start of the current minute and at each of the next 59.
    static func minuteEntries(from now: Date, count: Int = 60, calendar: Calendar = .current) -> [CasioClockEntry] {
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        return (0..<count).map { CasioClockEntry(date: minuteStart.addingTimeInterval(Double($0) * 60)) }
    }
}

// MARK: - LCD fonts
//
// DSEG7 / DSEG14 Classic Bold Italic by Keshikan (SIL OFL 1.1, Resources/DSEG-LICENSE.txt)
// for digits and letters.

struct LCDFont: Equatable {
    let postScriptName: String
    /// Glyph height as a fraction of the em.
    let glyphToEm: CGFloat
    /// Baseline position from the top of the line box, in ems.
    let baselineFromTop: CGFloat
    /// Advance of one digit, in ems.
    let digitAdvance: CGFloat
    /// A character with every segment lit ("8" / "~"), for the faint unlit segments; nil if none.
    let allSegments: Character?
    /// A digit-wide blank ("!" in DSEG), for an empty leading hour digit.
    let blankDigit: String

    static func dseg7(_ style: String) -> LCDFont {
        LCDFont(
            postScriptName: "DSEG7Classic-\(style)", glyphToEm: 1, baselineFromTop: 1, digitAdvance: 0.816,
            allSegments: "8", blankDigit: "!")
    }
    static func dseg14(_ style: String) -> LCDFont {
        LCDFont(
            postScriptName: "DSEG14Classic-\(style)", glyphToEm: 1, baselineFromTop: 1, digitAdvance: 0.816,
            allSegments: "~", blankDigit: "!")
    }

    static func registerBundledFonts() { _ = registered }

    private static let registered: Bool = {
        for url in Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    /// The font whose glyphs are `height` points tall.
    func font(height: CGFloat) -> Font {
        _ = Self.registered
        return .custom(postScriptName, fixedSize: height / glyphToEm)
    }

    /// `text` with every character replaced by the all-segments glyph (digits by `allSegments`,
    /// keeping colons), for the unlit-segment layer.
    func allLit(_ text: String) -> String? {
        guard let allSegments else { return nil }
        return String(text.map { $0 == ":" ? ":" : allSegments })
    }
}

/// The printed case text fonts (registered with the LCD fonts).
enum CaseFont {
    static func michroma(_ size: CGFloat) -> Font { custom("Michroma-Regular", size) }
    static func archivoBlack(_ size: CGFloat) -> Font { custom("ArchivoExpanded-Black", size) }
    static func saira(_ size: CGFloat) -> Font { custom("Saira-Medium", size) }
    static func sairaExpanded(_ size: CGFloat) -> Font { custom("SairaExpanded-SemiBold", size) }

    private static func custom(_ name: String, _ size: CGFloat) -> Font {
        LCDFont.registerBundledFonts()
        return .custom(name, fixedSize: size)
    }
}

/// Look options for the face; the widget uses `.standard` (chosen from prototypes: DSEG Bold
/// Italic with unlit segments on grey-green glass).
struct CasioFaceStyle {
    var digits: LCDFont = .dseg7("BoldItalic")
    var letters: LCDFont = .dseg14("BoldItalic")
    /// Opacity of the unlit segments behind the digits; 0 = off.
    var unlitOpacity: Double = 0.055
    var glass: Color = Color(red: 0.67, green: 0.74, blue: 0.68)
    var ink: Color = Color(red: 0.11, green: 0.16, blue: 0.19)

    static let standard = CasioFaceStyle()
}

// MARK: - Watch face
//
// Laid out on a fixed 594×530 canvas whose coordinates were measured from a front-on photo of
// an F-91W (Wikimedia Commons, Casio_F-91W_5051.jpg), then scaled to the widget.
// Typefaces per Fonts In Use (fontsinuse.com/uses/74290): CASIO logo Microgramma; "F-91W"
// Neue Helvetica Extended Black; "ALARM CHRONOGRAPH" regular-width Medium; the other labels
// Eurostile Extended Regular / Medium. Free look-alikes (SIL OFL, Google Fonts) stand in:
// Michroma for Microgramma / Eurostile Extended, Archivo Expanded Black (an instance of
// Archivo's variable font) for Neue Helvetica Extended Black, Saira Medium for Eurostile Medium,
// Saira Expanded SemiBold (an instance of Saira's variable font) for the WR mark.

struct CasioWatchFace: View {
    let date: Date
    var calendar: Calendar = .current
    var uses12HourClock: Bool = CasioWatchFace.localeUses12HourClock
    var style: CasioFaceStyle = .standard
    /// The LIGHT button's green backlight.
    var backlit = false
    /// Fixed seconds instead of the live timer (static previews; the timer only animates
    /// inside a widget).
    var previewSeconds: Int? = nil

    static let canvas = CGSize(width: 594, height: 530)

    static let resin = LinearGradient(
        colors: [Color(white: 0.13), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
    // Colours sampled from the photo, white-balanced so the white print is neutral.
    static let blue = Color(red: 0.04, green: 0.45, blue: 0.95)
    static let silver = Color(white: 0.86)
    static let gold = Color(red: 0.90, green: 0.78, blue: 0.40)
    static let printWhite = Color(white: 0.94)
    static let red = Color(red: 0.95, green: 0.13, blue: 0.13)
    static let backlight = Color(red: 0.36, green: 0.86, blue: 0.62)

    static var localeUses12HourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.canvas.width, geo.size.height / Self.canvas.height)
            ZStack(alignment: .topLeading) {
                bezel
                printedFace
                lcd
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Bezel and frame lines

    private var bezel: some View {
        ZStack(alignment: .topLeading) {
            // Thin outer blue line, wide blue band, white line framing the printed face; all three
            // are octagons with the watch's cut corners.
            frameLine(x: 23.5, y: 31.5, width: 548.5, height: 472, lineWidth: 3, radius: 24, color: Self.blue)
            frameLine(x: 36, y: 45.5, width: 520.5, height: 445, lineWidth: 10.5, radius: 22, color: Self.blue)
            frameLine(x: 50, y: 60, width: 492, height: 417, lineWidth: 2, radius: 18, color: Self.silver)
        }
    }

    /// A frame line stroked along the given centerline rectangle.
    private func frameLine(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, lineWidth: CGFloat, radius: CGFloat, color: Color
    ) -> some View {
        CutCornerRect(cut: CGSize(width: 40, height: 64), radius: radius)
            .stroke(color, lineWidth: lineWidth)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }

    // MARK: Printed text and bars

    private var printedFace: some View {
        ZStack(alignment: .topLeading) {
            // CASIO / F-91W
            Text("CASIO")
                .font(CaseFont.michroma(25.5))
                .tracking(4)
                .foregroundStyle(Self.printWhite)
                .emboldened(1.6)
                .place(centerX: 199.5, centerY: 91.75)
            Text("F-91W")
                .font(CaseFont.archivoBlack(23.6))
                .tracking(5.6)
                .foregroundStyle(Self.gold)
                .emboldened(0.6)
                .oblique()
                .place(centerX: 398, centerY: 93.5)
            bar(x: 70, y: 125, width: 453)

            // ◀ LIGHT   ALARM  CHRONOGRAPH
            Pointer(left: true).fill(Self.red).frame(width: 21, height: 7).position(x: 96.75, y: 157.75)
            Text("LIGHT")
                .font(CaseFont.michroma(12.4))
                .tracking(1)
                .foregroundStyle(Self.printWhite)
                .emboldened(0.25)
                .place(leading: 116.5, centerY: 157)
            Text("ALARM")
                .font(CaseFont.saira(21.7))
                .tracking(1.6)
                .foregroundStyle(Self.gold)
                .emboldened(0.25)
                .place(leading: 227.5, centerY: 154.75, width: 100)
            Text("CHRONOGRAPH")
                .font(CaseFont.saira(21.7))
                .tracking(1.6)
                .foregroundStyle(Self.gold)
                .emboldened(0.25)
                .place(trailing: 504.5, centerY: 154.75, width: 200)

            // ◀ MODE   ALARM  ON · OFF / 24HR ▶
            Pointer(left: true).fill(Self.red).frame(width: 20, height: 6.5).position(x: 98, y: 404.5)
            Text("MODE")
                .font(CaseFont.michroma(12.8))
                .tracking(1.1)
                .foregroundStyle(Self.printWhite)
                .emboldened(0.25)
                .place(leading: 116.5, centerY: 402.75)
            Text("ALARM")
                .font(CaseFont.michroma(12.8))
                .tracking(0.85)
                .foregroundStyle(Self.printWhite)
                .emboldened(0.25)
                .place(leading: 242.75, centerY: 402.75, width: 90)
            Text("ON · OFF / 24HR")
                .font(CaseFont.michroma(12.8))
                .tracking(0.65)
                .foregroundStyle(Self.printWhite)
                .emboldened(0.25)
                .place(trailing: 476.3, centerY: 402.75, width: 170)
            Pointer(left: false).fill(Self.red).frame(width: 20.5, height: 7).position(x: 497.25, y: 404.25)

            // WATER [WR] RESIST
            bar(x: 70, y: 419, width: 144.5, height: 5.5)
            bar(x: 375, y: 419, width: 148.5, height: 5.5)
            // The WR box: round top corners, cut bottom corners.
            CutCornerRect(cut: CGSize(width: 11, height: 11), bottomCut: CGSize(width: 15, height: 15), radius: 8)
                .stroke(Self.blue, lineWidth: 3.75)
                .frame(width: 140.6, height: 47)
                .offset(x: 226.6, y: 417.6)
            // The watch's WR is wider than any free extended face; Saira Expanded is stretched.
            Text("WR")
                .font(CaseFont.sairaExpanded(33.8))
                .foregroundStyle(Self.red)
                .oblique()
                .scaleEffect(x: 1.6, y: 1)
                .place(centerX: 295.25, centerY: 441.75)
            Text("WATER")
                .font(CaseFont.michroma(17))
                .tracking(3.35)
                .foregroundStyle(Self.printWhite)
                .emboldened(1.3)
                .place(centerX: 158, centerY: 441.5, width: 130)
            Text("RESIST")
                .font(CaseFont.michroma(17))
                .tracking(4.2)
                .foregroundStyle(Self.printWhite)
                .emboldened(1.5)
                .place(centerX: 441, centerY: 441.5, width: 130)
            Text("u")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Self.printWhite.opacity(0.85))
                .place(centerX: 459.5, centerY: 463)
        }
    }

    private func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 6) -> some View {
        Rectangle().fill(Self.blue).frame(width: width, height: height).offset(x: x, y: y)
    }

    // MARK: LCD

    private var lcd: some View {
        let parts = Self.displayParts(
            for: date, calendar: calendar, twelveHour: uses12HourClock, blankDigit: style.digits.blankDigit)
        return ZStack(alignment: .topLeading) {
            // Silver frame, dark surround, grey-green glass.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Self.silver, lineWidth: 1.75)
                )
                .frame(width: 414.5, height: 214)
                .offset(x: 89, y: 174)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [style.glass, style.glass.opacity(0.9)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay {
                    if backlit {
                        // The F-91W's light is one green LED at the left edge, so the glow is
                        // strongest on the left and fades toward the right.
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Self.backlight, Self.backlight.opacity(0.75), Self.backlight.opacity(0.45)],
                                    startPoint: .leading, endPoint: .trailing)
                            )
                    }
                }
                .frame(width: 389.5, height: 184.5)
                .offset(x: 104, y: 191.5)

            // PM in the afternoon on a 12-hour clock; 24H on a 24-hour clock, like the watch.
            if let marker = parts.marker {
                Text(marker)
                    .font(.system(size: 29.3, weight: .bold))
                    .foregroundStyle(style.ink)
                    .place(centerX: 141, centerY: 243.5)
            }
            // Day of week and date share the top row.
            lcdText(parts.weekday, font: style.letters, glyph: 43, leading: 234, baseline: 247, tracking: 7.5)
            lcdText(parts.day, font: style.digits, glyph: 47.5, trailing: 484.7, baseline: 251.5, width: 120, tracking: 4.5)
            // H:MM; the watch's digits are narrower than DSEG's.
            lcdText(
                parts.hoursMinutes, font: style.digits, glyph: 88.5, trailing: 383, baseline: 357.5, width: 320,
                xScale: Self.digitSqueeze)
            seconds
        }
    }

    /// Width of the big digits relative to DSEG's (measured from the photo).
    static let digitSqueeze: CGFloat = 0.9

    /// LCD text with its unlit segments faintly behind it.
    @ViewBuilder
    private func lcdText(
        _ text: String, font: LCDFont, glyph: CGFloat, leading: CGFloat? = nil, trailing: CGFloat? = nil,
        baseline: CGFloat, width: CGFloat = 200, tracking: CGFloat = 0, xScale: CGFloat = 1
    ) -> some View {
        let layers: [(String, Double)] =
            [(font.allLit(text), style.unlitOpacity), (text, 1)].compactMap { item in
                guard let t = item.0, item.1 > 0 else { return nil }
                return (t, item.1)
            }
        ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
            let view = Text(layer.0).font(font.font(height: glyph)).tracking(tracking)
                .foregroundStyle(style.ink.opacity(layer.1))
                .scaleEffect(x: xScale, y: 1, anchor: leading != nil ? .leading : .trailing)
            if let leading {
                view.place(leading: leading, baseline: baseline, glyphHeight: glyph, font: font, width: width)
            } else if let trailing {
                view.place(trailing: trailing, baseline: baseline, glyphHeight: glyph, font: font, width: width)
            }
        }
    }

    /// Live seconds: timer text counting up from the start of this minute ("0:23"), shown
    /// through a right-aligned window that keeps only the last two digits.
    private var seconds: some View {
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let glyph: CGFloat = 67
        let font = style.digits
        let digitAdvance = glyph / font.glyphToEm * font.digitAdvance
        let live: Text =
            previewSeconds.map { Text(String(format: "%02d", $0)) } ?? Text(minuteStart, style: .timer)
        return ZStack(alignment: .topLeading) {
            if style.unlitOpacity > 0, let lit = font.allLit("00") {
                Text(lit).font(font.font(height: glyph))
                    .foregroundStyle(style.ink.opacity(style.unlitOpacity))
                    .scaleEffect(x: Self.digitSqueeze, y: 1, anchor: .trailing)
                    .place(trailing: 486, baseline: 357.5, glyphHeight: glyph, font: font, width: digitAdvance * 2.02)
            }
            live
                .font(font.font(height: glyph))
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: digitAdvance * 6, alignment: .trailing)
                .frame(width: digitAdvance * 2.02, alignment: .trailing)
                .clipped()
                .scaleEffect(x: Self.digitSqueeze, y: 1, anchor: .trailing)
                .place(trailing: 486, baseline: 357.5, glyphHeight: glyph, font: font, width: digitAdvance * 2.02)
        }
    }

    // MARK: Formatting

    struct DisplayParts: Equatable {
        /// "H:MM" with a figure space for a blank leading hour digit ("\u{2007}6:04").
        let hoursMinutes: String
        let isPM: Bool
        /// "PM", "24H" or nil (morning on a 12-hour clock).
        let marker: String?
        let weekday: String
        /// Right-aligned day of month ("\u{2007}9", "26").
        let day: String
    }

    static let weekdays = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    static let figureSpace = "\u{2007}"

    static func displayParts(
        for date: Date, calendar: Calendar, twelveHour: Bool, blankDigit: String = figureSpace
    ) -> DisplayParts {
        let c = calendar.dateComponents([.hour, .minute, .weekday, .day], from: date)
        let hour24 = c.hour ?? 0
        let hour = twelveHour ? (hour24 % 12 == 0 ? 12 : hour24 % 12) : hour24
        // Like the watch, a 12-hour time has no leading zero ("6:04", not "06:04").
        let hourText = hour < 10 ? (twelveHour ? blankDigit : "0") + "\(hour)" : "\(hour)"
        let minute = c.minute ?? 0
        let dayOfMonth = c.day ?? 1
        return DisplayParts(
            hoursMinutes: hourText + ":" + (minute < 10 ? "0" : "") + "\(minute)",
            isPM: twelveHour && hour24 >= 12,
            marker: twelveHour ? (hour24 >= 12 ? "PM" : nil) : "24H",
            weekday: weekdays[((c.weekday ?? 1) - 1) % 7],
            day: (dayOfMonth < 10 ? blankDigit : "") + "\(dayOfMonth)"
        )
    }
}

/// A rectangle with its four corners cut off diagonally (`cut` across and down) and the joints
/// rounded, like the frame lines printed on the F-91W.
struct CutCornerRect: Shape {
    let cut: CGSize
    /// The bottom corners' cut, if different from the top ones.
    var bottomCut: CGSize? = nil
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = CGSize(width: min(cut.width, rect.width / 2), height: min(cut.height, rect.height / 2))
        let b = bottomCut ?? cut
        let bottom = CGSize(width: min(b.width, rect.width / 2), height: min(b.height, rect.height / 2))
        let corners = [
            CGPoint(x: rect.minX + top.width, y: rect.minY), CGPoint(x: rect.maxX - top.width, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + top.height), CGPoint(x: rect.maxX, y: rect.maxY - bottom.height),
            CGPoint(x: rect.maxX - bottom.width, y: rect.maxY), CGPoint(x: rect.minX + bottom.width, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - bottom.height), CGPoint(x: rect.minX, y: rect.minY + top.height),
        ]
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        for i in 1...corners.count {
            p.addArc(tangent1End: corners[i % corners.count], tangent2End: corners[(i + 1) % corners.count], radius: radius)
        }
        p.closeSubpath()
        return p
    }
}

/// The small red triangles beside LIGHT, MODE and 24HR.
private struct Pointer: Shape {
    let left: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if left {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Placement on the canvas

extension View {
    /// Michroma has a single weight; the watch prints CASIO, WATER and RESIST bold. Overlaying
    /// copies shifted by `amount` points thickens the strokes.
    fileprivate func emboldened(_ amount: CGFloat) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                self.offset(x: amount * cos(angle), y: amount * sin(angle))
            }
            self
        }
    }

    /// Slants the view like the printed italics ("F-91W", "WR"). SF Pro Expanded has no
    /// italic face, so `.italic()` would draw it upright.
    fileprivate func oblique() -> some View {
        self.transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.21, d: 1, tx: 6, ty: 0))
    }

    /// Centers the view at a canvas point.
    fileprivate func place(centerX: CGFloat, centerY: CGFloat, width: CGFloat? = nil) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width)
            .fixedSize(horizontal: width == nil, vertical: true)
            .position(x: centerX, y: centerY)
    }

    /// Text starting at `leading`, vertically centered on `centerY`.
    fileprivate func place(leading: CGFloat, centerY: CGFloat, width: CGFloat = 200) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: .leading)
            .position(x: leading + width / 2, y: centerY)
    }

    /// Text ending at `trailing`, vertically centered on `centerY`.
    fileprivate func place(trailing: CGFloat, centerY: CGFloat, width: CGFloat) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: .trailing)
            .position(x: trailing - width / 2, y: centerY)
    }

    /// LCD text starting at `leading` with its baseline at `baseline`.
    fileprivate func place(leading: CGFloat, baseline: CGFloat, glyphHeight: CGFloat, font: LCDFont, width: CGFloat)
        -> some View
    {
        let em = glyphHeight / font.glyphToEm
        return self.lineLimit(1)
            .frame(width: width, height: em, alignment: .leading)
            .position(x: leading + width / 2, y: baseline - font.baselineFromTop * em + em / 2)
    }

    /// LCD text ending at `trailing` with its baseline at `baseline`.
    fileprivate func place(trailing: CGFloat, baseline: CGFloat, glyphHeight: CGFloat, font: LCDFont, width: CGFloat)
        -> some View
    {
        let em = glyphHeight / font.glyphToEm
        return self.lineLimit(1)
            .frame(width: width, height: em, alignment: .trailing)
            .position(x: trailing - width / 2, y: baseline - font.baselineFromTop * em + em / 2)
    }
}
