import CoreText
import Foundation
import Testing

@testable import CasioClockWidget

@Suite("Casio timeline")
struct TimelineTests {
    private var calendar: Calendar {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        return utc
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0
    ) throws -> Date {
        try #require(
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)))
    }

    @Test("timeline: one entry per hour, starting at the current hour (minutes and seconds are live)")
    func hourEntries() throws {
        let entries = try LiveClock.hourEntries(
            from: date(2026, 5, 2, 16, 20, 37), count: 12, calendar: calendar)
        #expect(entries.count == 12)
        #expect(try entries.first?.date == date(2026, 5, 2, 16, 0))
        #expect(try entries.last?.date == date(2026, 5, 3, 3, 0))
    }

    @Test("live clock: the timer starts 10 h before the hour, so it always reads 10:MM:SS")
    func timerStart() throws {
        let start = try LiveClock.timerStart(for: date(2026, 5, 2, 16, 20, 37), calendar: calendar)
        #expect(try start == date(2026, 5, 2, 6, 0))
        // 16:20:37 is 10 h 20 min 37 s after the start: the timer shows "10:20:37".
        #expect(try date(2026, 5, 2, 16, 20, 37).timeIntervalSince(start) == 10 * 3600 + 20 * 60 + 37)
    }

    @Test("backlight: a lit entry now, unlit when the light ends, then the hour entries")
    func backlightEntries() throws {
        let now = try date(2026, 5, 2, 16, 20, 37)
        let entries = LiveClock.entries(
            from: now, backlightUntil: now.addingTimeInterval(3), calendar: calendar)
        #expect(entries[0].backlit && entries[0].date == now)
        #expect(!entries[1].backlit && entries[1].date == now.addingTimeInterval(3))
        #expect(try entries[2].date == date(2026, 5, 2, 17, 0))
        #expect(entries.dropFirst().allSatisfy { !$0.backlit })
        // Short, so WidgetKit renders the lit timeline quickly; it reloads at the end.
        #expect(entries.count == 2 + LiveClock.litTimelineHours)
    }

    @Test("backlight: a late reload still lights the LCD for the full duration")
    func backlightLateReload() throws {
        // The tap set the light until now + 1 s, but WidgetKit only rebuilt the timeline 2 s later.
        let now = try date(2026, 5, 2, 16, 20, 37)
        let entries = LiveClock.entries(
            from: now, backlightUntil: now.addingTimeInterval(1), calendar: calendar)
        #expect(entries[0].backlit && entries[0].date == now)
        #expect(!entries[1].backlit && entries[1].date == now.addingTimeInterval(CasioBacklightIntent.duration))
    }

    @Test("backlight: an expired light time gives the plain hour entries")
    func backlightExpired() throws {
        let now = try date(2026, 5, 2, 16, 20, 37)
        let entries = LiveClock.entries(
            from: now, backlightUntil: now.addingTimeInterval(-1), calendar: calendar)
        #expect(try entries.first?.date == date(2026, 5, 2, 16, 0))
        #expect(entries.allSatisfy { !$0.backlit })
    }

    // MARK: The live-clock contract (LiveClock.swift)

    /// The entry WidgetKit shows at `instant`: the last one that has started.
    private func entryShown(at instant: Date, in entries: [CasioClockEntry]) -> CasioClockEntry? {
        entries.last { $0.date <= instant }
    }

    private func checkContract(entries: [CasioClockEntry], from now: Date, calendar: Calendar) throws {
        let last = try #require(entries.last).date
        var instant = now
        while instant <= last {
            let entry = try #require(entryShown(at: instant, in: entries), "\(instant)")
            // Hours digits come from the entry: same hour as the instant.
            let shown = calendar.dateInterval(of: .hour, for: entry.date)?.start
            #expect(shown == calendar.dateInterval(of: .hour, for: instant)?.start, "hour at \(instant)")
            // The timer reads "10:MM:SS" with the instant's minutes and seconds.
            let elapsed = Int(instant.timeIntervalSince(LiveClock.timerStart(for: entry.date, calendar: calendar)))
            let parts = calendar.dateComponents([.minute, .second], from: instant)
            #expect(elapsed / 3600 == 10, "timer hours at \(instant)")
            #expect(elapsed % 3600 == (parts.minute ?? 0) * 60 + (parts.second ?? 0), "timer MM:SS at \(instant)")
            instant = instant.addingTimeInterval(60)
        }
    }

    @Test(
        "contract: at every minute of the timeline the entry shows the right hour and the timer reads 10:MM:SS",
        arguments: ["UTC", "Europe/Berlin", "Australia/Lord_Howe"])
    func contract(timeZone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        // Saturday evening before the October 2026 European clock change (Sunday 03:00 -> 02:00), which
        // the 12-hour timeline crosses in Berlin; Lord Howe Island has a half-hour UTC offset.
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 20, minute: 17, second: 31)))
        try checkContract(
            entries: LiveClock.entries(from: now, backlightUntil: nil, calendar: calendar), from: now,
            calendar: calendar)
        let lit = LiveClock.entries(from: now, backlightUntil: now.addingTimeInterval(3), calendar: calendar)
        try checkContract(entries: lit, from: now, calendar: calendar)
    }

    @Test("contract: the timer frames fit the widest timer text, \"10:59:59\", so it isn't truncated")
    func timerFramesFit() throws {
        BundledFonts.register()
        let digits = LCDStyle().digits
        let em: CGFloat = 100
        let font = CTFontCreateWithName(digits.postScriptName as CFString, em, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: "10:59:59", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        #expect(width > 0)
        #expect(LiveClock.minutesTimerWidth(em: em) >= width)
        #expect(LiveClock.secondsTimerWidth(digitAdvance: digits.digitAdvance * em) >= width)
    }

    @Test("tracked layouts: each timer digit's window hides exactly the characters to its right in 10:MM:SS")
    func timerDigitWindows() {
        let font = LCDFont.dseg7("Bold")
        let em: CGFloat = 100
        let digit = font.digitAdvance * em, colon = font.colonAdvance * em
        // seconds units
        #expect(abs(TimerDigit.hiddenWidth(charactersAfter: 0, font: font, em: em) - 0) < 0.001)
        // seconds tens
        #expect(abs(TimerDigit.hiddenWidth(charactersAfter: 1, font: font, em: em) - digit) < 0.001)
        // minutes units
        #expect(abs(TimerDigit.hiddenWidth(charactersAfter: 3, font: font, em: em) - (colon + 2 * digit)) < 0.001)
        // minutes tens
        #expect(abs(TimerDigit.hiddenWidth(charactersAfter: 4, font: font, em: em) - (colon + 3 * digit)) < 0.001)
    }
}
