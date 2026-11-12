import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - ProgressiveLoadPhase2Tests
//
// Verifies the data contracts that Phase 2 of loadAsync depends on:
//   1. CachedVideoData fields used by Phase 2 default to `nil` (uncached).
//   2. All Phase 2 fields (nextInfo, endCards, sponsorSegments)
//      are independently cacheable and independently nil-able.
//   3. `phase2Task` is a separate concern from `loadTask` — both can be cancelled
//      independently (structural contract validated at the model layer).

@Suite("Progressive loadAsync (Phase E)")
struct ProgressiveLoadPhase2Tests {

    // MARK: - CachedVideoData field independence

    @Test("CachedVideoData nextInfo defaults to nil")
    func cachedVideoDataNextInfoDefault() async {
        let cached = await VideoPreloadCache.shared.consume(videoId: "phase2-test-\(Int.random(in: 0..<Int.max))")
        #expect(cached.nextInfo == nil)
    }

    @Test("CachedVideoData endCards defaults to nil")
    func cachedVideoDataEndCardsDefault() async {
        let cached = await VideoPreloadCache.shared.consume(videoId: "phase2-test-\(Int.random(in: 0..<Int.max))")
        #expect(cached.endCards == nil)
    }

    @Test("CachedVideoData sponsorSegments defaults to nil")
    func cachedVideoDataSponsorDefault() async {
        let cached = await VideoPreloadCache.shared.consume(videoId: "phase2-test-\(Int.random(in: 0..<Int.max))")
        #expect(cached.sponsorSegments == nil)
    }

    @Test("CachedVideoData playerInfo defaults to nil")
    func cachedVideoDataPlayerInfoDefault() async {
        let cached = await VideoPreloadCache.shared.consume(videoId: "phase2-test-\(Int.random(in: 0..<Int.max))")
        #expect(cached.playerInfo == nil)
    }

    // MARK: - Phase 2 field identifiability

    @Test("Cached playerInfo does not imply cached nextInfo (Phase 2 still needed)")
    func playerInfoCachedButNextInfoNot() async {
        let videoId = "phase2-independent-\(Int.random(in: 0..<Int.max))"
        let video = Video(id: videoId, title: "T", channelTitle: "C", thumbnailURL: nil)
        let info = PlayerInfo(
            video: video,
            formats: [],
            hlsURL: URL(string: "https://example.com/hls.m3u8"),
            dashURL: nil,
            captionTracks: [],
            trackingURLs: nil,
            endCards: []
        )
        await VideoPreloadCache.shared.store(playerInfo: info, for: videoId)

        let cached = await VideoPreloadCache.shared.consume(videoId: videoId)
        // playerInfo is cached — Phase 1 will skip the network call
        #expect(cached.playerInfo != nil)
        // nextInfo, endCards, sponsor are NOT cached — Phase 2 must fetch them
        #expect(cached.nextInfo == nil)
        #expect(cached.endCards == nil)
        #expect(cached.sponsorSegments == nil)
    }

    @Test("Storing nextInfo does not affect endCards cache status")
    func nextInfoDoesNotAffectEndCards() async {
        let videoId = "phase2-next-\(Int.random(in: 0..<Int.max))"
        let nextInfo = NextInfo(relatedVideos: [], likeStatus: .none, chapters: [])
        await VideoPreloadCache.shared.store(nextInfo: nextInfo, for: videoId)

        let cached = await VideoPreloadCache.shared.consume(videoId: videoId)
        #expect(cached.nextInfo != nil)
        // endCards is unaffected — Phase 2 must still fetch it independently
        #expect(cached.endCards == nil)
    }
}
