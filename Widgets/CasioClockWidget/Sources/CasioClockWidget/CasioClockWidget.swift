import SwiftUI
import WidgetKit

// MARK: - CasioClockWidget (experimental)
//
// A small Home Screen widget that is a live clock drawn as a Casio F-91W.
//
// How it stays live:
// - Hours and minutes come from a timeline with one entry per minute (an hour of entries,
//   then WidgetKit asks for the next hour), so the display changes exactly on the minute.
// - Widgets can't redraw every second, so the seconds are WidgetKit's own running timer
//   text counting up from the start of the minute, clipped to its last two digits ("0:23"
//   shows as "23"). Even if a minute entry arrives late, the last two digits stay right.

public struct CasioClockWidget: Widget {
    public static let kind = "CasioClockWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CasioClockProvider()) { entry in
            CasioWatchFace(date: entry.date)
                .containerBackground(for: .widget) { CasioWatchFace.resin }
        }
        .configurationDisplayName("Casio F-91W")
        .description("A live digital clock in the style of the Casio F-91W.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct CasioClockEntry: TimelineEntry {
    let date: Date
}

struct CasioClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> CasioClockEntry { CasioClockEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CasioClockEntry) -> Void) {
        completion(CasioClockEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CasioClockEntry>) -> Void) {
        completion(Timeline(entries: Self.minuteEntries(from: Date()), policy: .atEnd))
    }

    /// One entry at the start of the current minute and at each of the next 59.
    static func minuteEntries(from now: Date, count: Int = 60, calendar: Calendar = .current) -> [CasioClockEntry] {
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        return (0..<count).map { CasioClockEntry(date: minuteStart.addingTimeInterval(Double($0) * 60)) }
    }
}

// MARK: - Watch face

struct CasioWatchFace: View {
    let date: Date
    var calendar: Calendar = .current
    var uses12HourClock: Bool = CasioWatchFace.localeUses12HourClock

    static let resin = LinearGradient(
        colors: [Color(white: 0.16), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
    static let bezelBlue = Color(red: 0.17, green: 0.33, blue: 0.70)
    static let gold = Color(red: 0.86, green: 0.70, blue: 0.36)
    static let label = Color(white: 0.88)
    static let lcdInk = Color(red: 0.11, green: 0.13, blue: 0.10)
    static let wrRed = Color(red: 0.86, green: 0.18, blue: 0.16)

    static var localeUses12HourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                CasioWatchFace.resin
                // The blue line framing the face.
                RoundedRectangle(cornerRadius: s * 0.08, style: .continuous)
                    .strokeBorder(Self.bezelBlue, lineWidth: s * 0.014)
                    .padding(s * 0.065)
                VStack(spacing: s * 0.018) {
                    header(s)
                    lcd(s)
                    footer(s)
                }
                .padding(.horizontal, s * 0.11)
                .padding(.vertical, s * 0.1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Printed labels

    private func header(_ s: CGFloat) -> some View {
        VStack(spacing: s * 0.012) {
            HStack(alignment: .firstTextBaseline) {
                Text("CASIO")
                    .font(.system(size: s * 0.085, weight: .heavy))
                    .tracking(s * 0.004)
                    .foregroundStyle(Self.label)
                Spacer(minLength: 0)
                Text("F-91W")
                    .font(.system(size: s * 0.062, weight: .heavy).italic())
                    .foregroundStyle(Self.gold)
            }
            HStack {
                Text("LIGHT")
                Spacer(minLength: 0)
                Text("ALARM CHRONOGRAPH")
            }
            .font(.system(size: s * 0.036, weight: .semibold))
            .foregroundStyle(Self.gold)
        }
    }

    private func footer(_ s: CGFloat) -> some View {
        VStack(spacing: s * 0.016) {
            HStack {
                Text("MODE")
                Spacer(minLength: 0)
                Text("ALARM ON·OFF/24HR")
            }
            .font(.system(size: s * 0.033, weight: .semibold))
            .foregroundStyle(Self.label.opacity(0.8))
            HStack(spacing: s * 0.03) {
                Text("WATER")
                Text("WR")
                    .font(.system(size: s * 0.05, weight: .heavy).italic())
                    .foregroundStyle(Self.wrRed)
                    .padding(.horizontal, s * 0.025)
                    .overlay(
                        Capsule().strokeBorder(Self.wrRed, lineWidth: s * 0.008)
                    )
                Text("RESIST")
            }
            .font(.system(size: s * 0.046, weight: .bold))
            .foregroundStyle(Self.label)
        }
    }

    // MARK: LCD

    private func lcd(_ s: CGFloat) -> some View {
        let parts = Self.displayParts(for: date, calendar: calendar, twelveHour: uses12HourClock)
        let digitHeight = s * 0.21
        let digitWidth = digitHeight * 0.53
        let small = s * 0.07

        return VStack(alignment: .leading, spacing: s * 0.015) {
            // Top row: PM marker, day of week, date.
            HStack(alignment: .firstTextBaseline, spacing: s * 0.03) {
                Text(parts.isPM ? "PM" : " ")
                    .font(.system(size: small * 0.62, weight: .bold, design: .rounded))
                    .frame(width: small, alignment: .leading)
                Spacer(minLength: 0)
                Text(parts.weekday)
                    .font(.system(size: small, weight: .semibold, design: .monospaced))
                Text(parts.day)
                    .font(.system(size: small, weight: .semibold, design: .monospaced))
            }
            // Time: H H : M M  ss
            HStack(alignment: .bottom, spacing: digitWidth * 0.14) {
                SevenSegmentDigit(digit: parts.hourTens, color: Self.lcdInk)
                    .frame(width: digitWidth, height: digitHeight)
                SevenSegmentDigit(digit: parts.hourOnes, color: Self.lcdInk)
                    .frame(width: digitWidth, height: digitHeight)
                SevenSegmentColon(color: Self.lcdInk)
                    .frame(width: digitHeight * 0.1, height: digitHeight * 0.62)
                    .padding(.bottom, digitHeight * 0.15)
                SevenSegmentDigit(digit: parts.minuteTens, color: Self.lcdInk)
                    .frame(width: digitWidth, height: digitHeight)
                SevenSegmentDigit(digit: parts.minuteOnes, color: Self.lcdInk)
                    .frame(width: digitWidth, height: digitHeight)
                seconds(height: digitHeight * 0.55)
            }
        }
        .foregroundStyle(Self.lcdInk)
        .padding(.horizontal, s * 0.035)
        .padding(.vertical, s * 0.025)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: s * 0.02, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.70, green: 0.74, blue: 0.65),
                            Color(red: 0.62, green: 0.66, blue: 0.57),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .black.opacity(0.5), radius: s * 0.01, x: 0, y: s * 0.004)
        )
    }

    /// Live seconds: WidgetKit's running timer text, counting up from the start of this
    /// minute ("0:23"), clipped to its last two digits.
    private func seconds(height: CGFloat) -> some View {
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let fontSize = height * 0.95
        return Text(minuteStart, style: .timer)
            .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            // A frame wide enough for the whole timer ("0:23") so it isn't truncated, shown
            // through a narrower right-aligned window that keeps only the last two digits.
            .frame(width: fontSize * 3, alignment: .trailing)
            .frame(width: fontSize * 1.25, height: height, alignment: .trailing)
            .clipped()
    }

    // MARK: Formatting

    struct DisplayParts: Equatable {
        let hourTens: Int?
        let hourOnes: Int
        let minuteTens: Int
        let minuteOnes: Int
        let isPM: Bool
        let weekday: String
        let day: String
    }

    static let weekdays = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    static func displayParts(for date: Date, calendar: Calendar, twelveHour: Bool) -> DisplayParts {
        let c = calendar.dateComponents([.hour, .minute, .weekday, .day], from: date)
        let hour24 = c.hour ?? 0
        let hour = twelveHour ? (hour24 % 12 == 0 ? 12 : hour24 % 12) : hour24
        let minute = c.minute ?? 0
        return DisplayParts(
            // Like the watch, a 12-hour time has no leading zero ("4:20", not "04:20").
            hourTens: hour >= 10 ? hour / 10 : (twelveHour ? nil : 0),
            hourOnes: hour % 10,
            minuteTens: minute / 10,
            minuteOnes: minute % 10,
            isPM: twelveHour && hour24 >= 12,
            weekday: weekdays[((c.weekday ?? 1) - 1) % 7],
            day: String(format: "%2d", c.day ?? 1)
        )
    }
}
