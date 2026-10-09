import Foundation
import Testing

@testable import CasioClockWidget

@Suite("Casio LCD formatting")
struct DisplayPartsTests {
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

    private let fs = DisplayParts.figureSpace

    @Test("12-hour: 16:20 on Saturday the 2nd reads 4:20 PM, SA 2 — no leading zero")
    func twelveHourAfternoon() throws {
        let parts = try DisplayParts.make(for: date(2026, 5, 2, 16, 20), calendar: calendar, twelveHour: true)
        #expect(parts.hoursMinutes == fs + "4:20")
        #expect(parts.isPM)
        #expect(parts.marker == "PM")
        #expect(parts.weekday == "SA")
        #expect(parts.day == fs + "2")
    }

    @Test("12-hour: midnight and noon read 12")
    func twelveHourMidnightNoon() throws {
        let midnight = try DisplayParts.make(for: date(2026, 5, 2, 0, 5), calendar: calendar, twelveHour: true)
        #expect(midnight.hoursMinutes == "12:05")
        #expect(!midnight.isPM)
        #expect(midnight.marker == nil)
        let noon = try DisplayParts.make(for: date(2026, 5, 2, 12, 5), calendar: calendar, twelveHour: true)
        #expect(noon.hoursMinutes == "12:05")
        #expect(noon.isPM)
    }

    @Test("24-hour: 09:07 keeps the leading zero and no PM; two-digit day")
    func twentyFourHour() throws {
        let parts = try DisplayParts.make(for: date(2026, 5, 26, 9, 7), calendar: calendar, twelveHour: false)
        #expect(parts.hoursMinutes == "09:07")
        #expect(!parts.isPM)
        #expect(parts.marker == "24H")
        #expect(parts.weekday == "TU")
        #expect(parts.day == "26")
    }
}
