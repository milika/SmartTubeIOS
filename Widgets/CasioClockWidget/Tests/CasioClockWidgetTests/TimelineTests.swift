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
        let entries = try CasioClockProvider.hourEntries(
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
        let entries = CasioClockProvider.entries(
            from: now, backlightUntil: now.addingTimeInterval(3), calendar: calendar)
        #expect(entries[0].backlit && entries[0].date == now)
        #expect(!entries[1].backlit && entries[1].date == now.addingTimeInterval(3))
        #expect(try entries[2].date == date(2026, 5, 2, 17, 0))
        #expect(entries.dropFirst().allSatisfy { !$0.backlit })
        // Short, so WidgetKit renders the lit timeline quickly; it reloads at the end.
        #expect(entries.count == 2 + CasioClockProvider.litTimelineHours)
    }

    @Test("backlight: a late reload still lights the LCD for the full duration")
    func backlightLateReload() throws {
        // The tap set the light until now + 1 s, but WidgetKit only rebuilt the timeline 2 s later.
        let now = try date(2026, 5, 2, 16, 20, 37)
        let entries = CasioClockProvider.entries(
            from: now, backlightUntil: now.addingTimeInterval(1), calendar: calendar)
        #expect(entries[0].backlit && entries[0].date == now)
        #expect(!entries[1].backlit && entries[1].date == now.addingTimeInterval(CasioBacklightIntent.duration))
    }

    @Test("backlight: an expired light time gives the plain hour entries")
    func backlightExpired() throws {
        let now = try date(2026, 5, 2, 16, 20, 37)
        let entries = CasioClockProvider.entries(
            from: now, backlightUntil: now.addingTimeInterval(-1), calendar: calendar)
        #expect(try entries.first?.date == date(2026, 5, 2, 16, 0))
        #expect(entries.allSatisfy { !$0.backlit })
    }
}
