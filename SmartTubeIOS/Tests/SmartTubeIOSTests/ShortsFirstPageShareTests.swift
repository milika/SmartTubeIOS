import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Shorts first-page share")
struct ShortsFirstPageShareTests {

    private let alice = ShortsFirstPageShare.Account(token: "token-a", pageId: nil)
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func request(_ ids: [String], continuation: String? = "C1") -> Task<ShortsFeedPage, any Error> {
        let videos = ids.map { Video(id: $0, title: "", channelTitle: "", isShort: true) }
        return Task { ShortsFeedPage(videos: videos, continuation: continuation, isPersonalized: true) }
    }

    @Test("The Shorts tab gets the shelf's page, continuation included, once")
    func handsOutOnce() async throws {
        var share = ShortsFirstPageShare()
        share.offer(request(["a", "b"]), for: alice, at: start)

        let shared = share.take(for: alice, at: start.addingTimeInterval(5))
        let page = try await #require(shared).value
        #expect(page.videos.map(\.id) == ["a", "b"])
        #expect(page.continuation == "C1")

        let taken = share.take(for: alice, at: start.addingTimeInterval(6))
        #expect(taken == nil)
    }

    @Test("Another account (or Brand Account) doesn't get the page")
    func scopedToAccount() {
        var share = ShortsFirstPageShare()
        share.offer(request(["a"]), for: alice, at: start)
        let brand = share.take(for: .init(token: "token-a", pageId: "brand"), at: start)
        #expect(brand == nil)

        share.offer(request(["a"]), for: alice, at: start)
        let signedOut = share.take(for: .init(token: nil, pageId: nil), at: start)
        #expect(signedOut == nil)
    }

    @Test("A stale page isn't handed out")
    func dropsStalePage() {
        var share = ShortsFirstPageShare()
        share.offer(request(["a"]), for: alice, at: start)

        let taken = share.take(for: alice, at: start.addingTimeInterval(ShortsFirstPageShare.maxAge))
        #expect(taken == nil)
    }

    @Test("A newer shelf request replaces the older one")
    func newerOfferWins() async throws {
        var share = ShortsFirstPageShare()
        share.offer(request(["old"]), for: alice, at: start)
        share.offer(request(["new"]), for: alice, at: start)

        let shared = share.take(for: alice, at: start)
        let page = try await #require(shared).value
        #expect(page.videos.map(\.id) == ["new"])
    }
}
