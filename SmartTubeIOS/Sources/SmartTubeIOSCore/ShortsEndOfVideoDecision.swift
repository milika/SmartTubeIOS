import Foundation

/// Pure end-of-video decision for the Shorts player — what to do when the current
/// Short reports `ended`.
///
/// Driven only by `settings.shortsAutoScroll` (the global `loopEnabled` does not
/// apply to Shorts):
/// - auto-scroll off (default, like the official app) → the Short loops;
/// - auto-scroll on → advance to the next Short, or wait at the end of the list
///   until the feed delivers more.
public enum ShortsEndOfVideoDecision: Equatable {
    /// Auto-scroll is off — seek the current Short back to 0 and replay.
    case replay
    /// Advance to `videos[to]` — same path as a swipe-up (`goTo(to)`).
    case advance(to: Int)
    /// Auto-scroll is on but this is the last loaded Short — hold on the last frame
    /// (`videoEnded = true`); the player advances once more Shorts are appended.
    case freeze

    /// - Parameters:
    ///   - settings: Only `settings.shortsAutoScroll` is consulted.
    ///   - currentIndex: Index of the Short that just ended.
    ///   - count: `videos.count`.
    public static func decide(settings: AppSettings, currentIndex: Int, count: Int) -> ShortsEndOfVideoDecision {
        guard settings.shortsAutoScroll else { return .replay }
        let next = currentIndex + 1
        return next < count ? .advance(to: next) : .freeze
    }

    /// A Short that ended or failed while the player had to wait (for the feed's next
    /// page, or for a sheet to close) moves on once it can: after a failure always —
    /// an unplayable Short can't loop — and after a normal end only with auto-scroll on.
    public static func advancesAfterWaiting(settings: AppSettings, failed: Bool) -> Bool {
        failed || settings.shortsAutoScroll
    }
}
