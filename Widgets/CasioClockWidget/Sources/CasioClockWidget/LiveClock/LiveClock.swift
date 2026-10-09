import CoreGraphics
import Foundation
import WidgetKit

// The live clock: how a widget shows the current time to the second while WidgetKit redraws it
// only when the timeline says so. One contract, kept here:
//
// - The timeline has an entry at the start of every hour (and, after a tap, a lit entry now and an
//   unlit one when the light ends). The hours digits, date, weekday and PM / 24H come from the
//   entry on screen, so they are right because an entry starts every hour.
// - Minutes and seconds come from one WidgetKit timer text that animates itself. It starts 10 hours
//   before the hour of the entry on screen, so at any instant of that hour it reads "10:MM:SS" with
//   the instant's minutes and seconds; LiveHoursMinutes cuts out MM, LiveSeconds SS. The views lay
//   the whole timer text out in a frame at least as wide as "10:59:59" (the widths below), then
//   clip it, so nothing is truncated.
//
// Why not one entry per minute: WidgetKit stores every entry fully drawn; an hour of detailed faces
// grew past its limit (36 MB, rejected), and a separate seconds timer drifted from the minutes.
// Tests: TimelineTests check the contract at every minute of the timeline, and that the frames fit.

/// One timeline entry: the time it starts showing and whether the light is on.
struct CasioClockEntry: TimelineEntry {
    let date: Date
    var backlit = false
}

enum LiveClock {
    // MARK: Entry schedule

    /// Hour entries after the light goes off; the timeline then ends and WidgetKit reloads.
    static let litTimelineHours = 2

    /// The hour entries, preceded by a lit entry while the light is on. WidgetKit renders every
    /// entry before it shows the timeline, so the lit timeline is kept short, and the light lasts
    /// its full duration from now rather than from the tap.
    static func entries(from now: Date, backlightUntil: Date?, calendar: Calendar = .current) -> [CasioClockEntry] {
        guard let requested = backlightUntil, requested > now else { return hourEntries(from: now, calendar: calendar) }
        let until = max(requested, now.addingTimeInterval(CasioBacklightIntent.duration))
        return [CasioClockEntry(date: now, backlit: true), CasioClockEntry(date: until)]
            + hourEntries(from: until, count: litTimelineHours + 1, calendar: calendar).filter { $0.date > until }
            .prefix(litTimelineHours)
    }

    /// One entry at the start of the current hour and at each of the next 11 (minutes and seconds
    /// are live); WidgetKit reloads after 12 hours.
    static func hourEntries(from now: Date, count: Int = 12, calendar: Calendar = .current) -> [CasioClockEntry] {
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return (0..<count).map { CasioClockEntry(date: hourStart.addingTimeInterval(Double($0) * 3600)) }
    }

    // MARK: Timer

    /// The timer's start: 10 hours before the current hour, so it always reads "10:MM:SS" (two-digit
    /// hours, zero-padded minutes and seconds) and the minutes are the two digits before the last colon.
    static func timerStart(for date: Date, calendar: Calendar) -> Date {
        let hourStart = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return hourStart.addingTimeInterval(-10 * 3600)
    }

    /// Width LiveHoursMinutes lays the timer text out in, for a font of `em` points.
    static func minutesTimerWidth(em: CGFloat) -> CGFloat { 8 * em }

    /// Width LiveSeconds lays the timer text out in, for digits `digitAdvance` points apart.
    static func secondsTimerWidth(digitAdvance: CGFloat) -> CGFloat { digitAdvance * 10 }
}
