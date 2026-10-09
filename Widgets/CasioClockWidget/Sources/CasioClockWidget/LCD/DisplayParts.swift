import Foundation

/// The LCD's time and date, formatted like the watch.
struct DisplayParts: Equatable {
    /// "H:MM" with a figure space for a blank leading hour digit ("\u{2007}6:04").
    let hoursMinutes: String
    let isPM: Bool
    /// "PM", "24H" or nil (morning on a 12-hour clock).
    let marker: String?
    let weekday: String
    /// Right-aligned day of month ("\u{2007}9", "26").
    let day: String

    static let weekdays = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    static let figureSpace = "\u{2007}"

    static var localeUses12HourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
    }

    /// A day or month right-aligned in two digit cells, `blank` filling the empty one ("\u{2007}9",
    /// "26"), as the LCDs show dates.
    static func twoCells(_ number: Int, blank: String) -> String {
        number < 10 ? blank + "\(number)" : "\(number)"
    }

    /// A weekday in Casio's 7-segment letter shapes for a DSEG7 font: S is drawn as a full "5", U as
    /// a full-height U (DSEG7's "V") and O as a full "0"; DSEG7's own S, U and O are small lower-case.
    static func sevenSegmentLetters(_ weekday: String) -> String {
        String(weekday.map { ["S": "5", "U": "V", "O": "0"][$0] ?? $0 })
    }

    static func make(
        for date: Date, calendar: Calendar, twelveHour: Bool, blankDigit: String = figureSpace
    ) -> DisplayParts {
        let components = calendar.dateComponents([.hour, .minute, .weekday, .day], from: date)
        let hour24 = components.hour ?? 0
        let hour = twelveHour ? (hour24 % 12 == 0 ? 12 : hour24 % 12) : hour24
        // Like the watch, a 12-hour time has no leading zero ("6:04", not "06:04").
        let hourText = hour < 10 ? (twelveHour ? blankDigit : "0") + "\(hour)" : "\(hour)"
        let minute = components.minute ?? 0
        let dayOfMonth = components.day ?? 1
        return DisplayParts(
            hoursMinutes: hourText + ":" + (minute < 10 ? "0" : "") + "\(minute)",
            isPM: twelveHour && hour24 >= 12,
            marker: twelveHour ? (hour24 >= 12 ? "PM" : nil) : "24H",
            weekday: weekdays[((components.weekday ?? 1) - 1) % 7],
            day: twoCells(dayOfMonth, blank: blankDigit)
        )
    }
}

extension CasioFaceContext {
    /// The display's strings for this context's time and clock style (`blankDigit`: the LCD
    /// font's empty digit cell).
    func displayParts(blankDigit: String) -> DisplayParts {
        DisplayParts.make(for: date, calendar: calendar, twelveHour: uses12HourClock, blankDigit: blankDigit)
    }
}
