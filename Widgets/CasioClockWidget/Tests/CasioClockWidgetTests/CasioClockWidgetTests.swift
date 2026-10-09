import Foundation
import Testing

@testable import CasioClockWidget

@Suite("Casio clock widget")
struct CasioClockWidgetTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    @Test("12-hour: 16:20 on Saturday the 2nd reads 4:20 PM, SA 2 — no leading zero")
    func twelveHourAfternoon() {
        let parts = CasioWatchFace.displayParts(for: date(2026, 5, 2, 16, 20), calendar: calendar, twelveHour: true)
        #expect(parts.hourTens == nil)
        #expect(parts.hourOnes == 4)
        #expect((parts.minuteTens, parts.minuteOnes) == (2, 0))
        #expect(parts.isPM)
        #expect(parts.weekday == "SA")
        #expect(parts.day == " 2")
    }

    @Test("12-hour: midnight and noon read 12")
    func twelveHourMidnightNoon() {
        let midnight = CasioWatchFace.displayParts(for: date(2026, 5, 2, 0, 5), calendar: calendar, twelveHour: true)
        #expect((midnight.hourTens, midnight.hourOnes, midnight.isPM) == (1, 2, false))
        let noon = CasioWatchFace.displayParts(for: date(2026, 5, 2, 12, 5), calendar: calendar, twelveHour: true)
        #expect((noon.hourTens, noon.hourOnes, noon.isPM) == (1, 2, true))
    }

    @Test("24-hour: 09:07 keeps the leading zero and no PM")
    func twentyFourHour() {
        let parts = CasioWatchFace.displayParts(for: date(2026, 5, 4, 9, 7), calendar: calendar, twelveHour: false)
        #expect((parts.hourTens, parts.hourOnes, parts.minuteTens, parts.minuteOnes) == (0, 9, 0, 7))
        #expect(!parts.isPM)
        #expect(parts.weekday == "MO")
    }

    @Test("timeline: one entry per minute, starting at the current minute")
    func minuteEntries() {
        let entries = CasioClockProvider.minuteEntries(from: date(2026, 5, 2, 16, 20, 37), count: 60, calendar: calendar)
        #expect(entries.count == 60)
        #expect(entries.first?.date == date(2026, 5, 2, 16, 20))
        #expect(entries.last?.date == date(2026, 5, 2, 17, 19))
    }
}
