import Foundation

/// Hands the seedless Shorts first page that a Home/Browse Shorts shelf requested to
/// the Shorts tab, so opening the tab doesn't wait for the same two sequential
/// requests again (`InnerTubeAPI.fetchShortsFeed(seedVideoId:)`).
///
/// The shelf `offer`s its request as soon as it starts — before it fetches every
/// Short's title — and the tab `take`s it, finished or still in flight, together with
/// its continuation. A page is handed out once, only to the account it was fetched
/// for, and only while it is fresh; otherwise the tab fetches its own.
struct ShortsFirstPageShare: Sendable {
    /// Who the page was personalised for: the Bearer token and the Brand Account.
    /// A token refresh counts as another account — the tab then just fetches anew.
    struct Account: Equatable, Sendable {
        let token: String?
        let pageId: String?
    }

    /// Older pages are dropped: the tab should open on a current feed.
    static let maxAge: TimeInterval = 10 * 60

    private struct Entry: Sendable {
        let account: Account
        let startedAt: Date
        let request: Task<ShortsFeedPage, any Error>
    }

    private var entry: Entry?

    /// Keeps `request` (replacing any earlier one) for the next `take`.
    mutating func offer(_ request: Task<ShortsFeedPage, any Error>, for account: Account, at now: Date = Date()) {
        entry = Entry(account: account, startedAt: now, request: request)
    }

    /// The offered request, if it was made for `account` and is still fresh. Either
    /// way the share is empty afterwards: a retry or a later feed fetches anew.
    mutating func take(for account: Account, at now: Date = Date()) -> Task<ShortsFeedPage, any Error>? {
        defer { entry = nil }
        guard let entry, entry.account == account, now.timeIntervalSince(entry.startedAt) < Self.maxAge
        else { return nil }
        return entry.request
    }
}
