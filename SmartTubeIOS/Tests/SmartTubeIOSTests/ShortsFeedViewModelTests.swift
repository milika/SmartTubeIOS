import Foundation
import Testing

@testable import SmartTubeIOSCore

private func short(_ id: String) -> Video { Video(id: id, title: "", channelTitle: "", isShort: true) }

private struct FakeError: Error {}

/// Records calls and serves scripted pages. All state is touched only from the
/// main actor (the view model is `@MainActor`), hence `@unchecked Sendable`.
private final class FakeShortsProvider: ShortsFeedProviding, @unchecked Sendable {
    var firstPage: Result<ShortsFeedPage, Error> = .success(
        ShortsFeedPage(videos: [], continuation: nil, isPersonalized: false))
    var morePages: [String: ShortsFeedPage] = [:]
    var searchGroup = VideoGroup(title: "Shorts", videos: [])
    var metadataResult: Result<ShortMetadata, Error>?
    var likeShouldFail = false
    private(set) var seeds: [String?] = []
    private(set) var continuations: [String] = []
    private(set) var searchCalls = 0
    private(set) var likeCalls: [String] = []

    func fetchShortsFeed(seedVideoId: String?) throws -> ShortsFeedPage {
        seeds.append(seedVideoId)
        return try firstPage.get()
    }
    func fetchShortsFeedMore(continuation: String) throws -> ShortsFeedPage {
        continuations.append(continuation)
        guard let page = morePages[continuation] else { throw FakeError() }
        return page
    }
    func fetchShortMetadata(videoId: String) throws -> ShortMetadata {
        guard let metadataResult else { throw FakeError() }
        return try metadataResult.get()
    }
    func fetchShorts() throws -> VideoGroup {
        searchCalls += 1
        return searchGroup
    }
    func fetchShortsMore(continuationToken: String) throws -> VideoGroup { VideoGroup(title: "", videos: []) }
    func like(videoId: String) throws {
        likeCalls.append("like")
        if likeShouldFail { throw FakeError() }
    }
    func dislike(videoId: String) throws { likeCalls.append("dislike") }
    func removeLike(videoId: String) throws { likeCalls.append("remove") }
    func subscribe(channelId: String) throws {}
    func unsubscribe(channelId: String) throws {}
}

@MainActor
@Suite("Shorts feed view model")
struct ShortsFeedViewModelTests {

    @Test("Seeded feed keeps the tapped Short first and seeds the algorithm with it")
    func seededFeed() async {
        let provider = FakeShortsProvider()
        provider.firstPage = .success(
            ShortsFeedPage(videos: [short("b"), short("tapped"), short("c")], continuation: "C1", isPersonalized: true))
        let vm = ShortsFeedViewModel(source: .algorithm(seed: short("tapped")), provider: provider)
        #expect(vm.videos.map(\.id) == ["tapped"])

        await vm.start()

        #expect(provider.seeds == ["tapped"])
        #expect(vm.videos.map(\.id) == ["tapped", "b", "c"])  // duplicate of the seed dropped
        #expect(vm.isPersonalized)
    }

    @Test("Seedless feed (Shorts tab) passes no seed and starts empty")
    func seedlessFeed() async {
        let provider = FakeShortsProvider()
        provider.firstPage = .success(ShortsFeedPage(videos: [short("a")], continuation: nil, isPersonalized: false))
        let vm = ShortsFeedViewModel(source: .algorithm(seed: nil), provider: provider)
        #expect(vm.videos.isEmpty)

        await vm.start()
        await vm.start()  // idempotent

        #expect(provider.seeds == [nil])
        #expect(vm.videos.map(\.id) == ["a"])
    }

    @Test("Near the end, the next page is fetched with the continuation token")
    func paging() async {
        let provider = FakeShortsProvider()
        provider.firstPage = .success(
            ShortsFeedPage(videos: [short("a"), short("b")], continuation: "C1", isPersonalized: false))
        provider.morePages["C1"] = ShortsFeedPage(videos: [short("c")], continuation: nil, isPersonalized: false)
        let vm = ShortsFeedViewModel(source: .algorithm(seed: nil), provider: provider)
        await vm.start()

        await vm.loadMoreIfNeeded(currentIndex: 0)
        #expect(provider.continuations == ["C1"])
        #expect(vm.videos.map(\.id) == ["a", "b", "c"])

        await vm.loadMoreIfNeeded(currentIndex: 2)  // exhausted → no further calls
        #expect(provider.continuations == ["C1"])
        #expect(provider.searchCalls == 0)
    }

    @Test("Far from the end, nothing is fetched")
    func noPrefetchFarFromEnd() async {
        let provider = FakeShortsProvider()
        let list = (0..<10).map { short("v\($0)") }
        let vm = ShortsFeedViewModel(source: .list(list, startIndex: 2), provider: provider)
        await vm.loadMoreIfNeeded(currentIndex: 2)
        #expect(provider.seeds.isEmpty)
        #expect(vm.startIndex == 2)
    }

    @Test("A fixed list continues with the algorithm seeded from its last Short")
    func listContinuesWithAlgorithm() async {
        let provider = FakeShortsProvider()
        provider.firstPage = .success(ShortsFeedPage(videos: [short("x")], continuation: "C1", isPersonalized: false))
        let vm = ShortsFeedViewModel(source: .list([short("a"), short("b")], startIndex: 0), provider: provider)

        await vm.start()  // no-op for lists
        #expect(provider.seeds.isEmpty)

        await vm.loadMoreIfNeeded(currentIndex: 1)
        #expect(provider.seeds == ["b"])
        #expect(vm.videos.map(\.id) == ["a", "b", "x"])
    }

    @Test("When the reel endpoints fail, the #shorts search is the fallback")
    func searchFallback() async {
        let provider = FakeShortsProvider()
        provider.firstPage = .failure(FakeError())
        provider.searchGroup = VideoGroup(title: "Shorts", videos: [short("s1")])
        let vm = ShortsFeedViewModel(source: .algorithm(seed: nil), provider: provider)

        await vm.start()

        #expect(provider.searchCalls == 1)
        #expect(vm.videos.map(\.id) == ["s1"])
        #expect(vm.loadError == nil)
    }

    @Test("Metadata fills in the Short's title and channel")
    func metadataMerge() async {
        let provider = FakeShortsProvider()
        provider.metadataResult = .success(
            ShortMetadata(videoId: "a", title: "Title", channelTitle: "@chan", channelId: "UC1"))
        let vm = ShortsFeedViewModel(source: .algorithm(seed: short("a")), provider: provider)

        await vm.loadMetadata(for: "a", signedIn: true)

        #expect(vm.metadata["a"]?.title == "Title")
        #expect(vm.videos.first?.title == "Title")
        #expect(vm.videos.first?.channelId == "UC1")
    }

    @Test("Like is optimistic and reverts when the request fails")
    func likeRevertsOnFailure() async {
        let provider = FakeShortsProvider()
        provider.metadataResult = .success(ShortMetadata(videoId: "a", title: "", channelTitle: ""))
        let vm = ShortsFeedViewModel(source: .algorithm(seed: short("a")), provider: provider)
        await vm.loadMetadata(for: "a", signedIn: true)

        await vm.toggleLike(videoId: "a")
        #expect(vm.metadata["a"]?.likeStatus == .like)

        await vm.toggleLike(videoId: "a")
        #expect(vm.metadata["a"]?.likeStatus == LikeStatus.none)
        #expect(provider.likeCalls == ["like", "remove"])

        provider.likeShouldFail = true
        await vm.toggleLike(videoId: "a")
        #expect(vm.metadata["a"]?.likeStatus == LikeStatus.none)
    }
}
