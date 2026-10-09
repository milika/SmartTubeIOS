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

    static func make(
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

extension CasioFaceContext {
    /// The display's strings for this context's time and clock style (`blankDigit`: the LCD
    /// font's empty digit cell).
    func displayParts(blankDigit: String) -> DisplayParts {
        DisplayParts.make(for: date, calendar: calendar, twelveHour: uses12HourClock, blankDigit: blankDigit)
    }
}
