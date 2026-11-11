import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Shorts End-of-Video Decision")
struct ShortsEndOfVideoDecisionTests {

    @Test("Auto-scroll is off by default, so a Short loops")
    func defaultLoops() {
        let result = ShortsEndOfVideoDecision.decide(settings: AppSettings(), currentIndex: 0, count: 3)
        #expect(result == .replay)
    }

    @Test("Auto-scroll on, not at the end → advance to next index")
    func advancesToNextIndex() {
        var settings = AppSettings()
        settings.shortsAutoScroll = true
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 0, count: 3)
        #expect(result == .advance(to: 1))
    }

    @Test("Auto-scroll on, at the last index → freeze until more Shorts arrive")
    func freezesAtLastIndex() {
        var settings = AppSettings()
        settings.shortsAutoScroll = true
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 2, count: 3)
        #expect(result == .freeze)
    }

    @Test("Auto-scroll off → replay even at the last index")
    func autoScrollOffReplaysAtEnd() {
        var settings = AppSettings()
        settings.shortsAutoScroll = false
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 2, count: 3)
        #expect(result == .replay)
    }

    @Test("The global loop setting does not affect Shorts")
    func globalLoopIgnored() {
        var settings = AppSettings()
        settings.loopEnabled = true
        settings.shortsAutoScroll = true
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 0, count: 2)
        #expect(result == .advance(to: 1))
    }

    @Test("shortsAutoScroll survives an encode/decode round-trip and defaults to off for old JSON")
    func persistence() throws {
        var settings = AppSettings()
        settings.shortsAutoScroll = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.shortsAutoScroll == true)

        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(legacy.shortsAutoScroll == false)
    }

    @Test("shortsSponsorBlock defaults to on (also for old JSON) and survives a round-trip when off")
    func sponsorBlockPersistence() throws {
        #expect(AppSettings().shortsSponsorBlock == true)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(legacy.shortsSponsorBlock == true)

        var settings = AppSettings()
        settings.shortsSponsorBlock = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.shortsSponsorBlock == false)
    }
}
