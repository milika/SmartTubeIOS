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

    @Test("A failed Short moves on after waiting even with auto-scroll off; an ended one loops")
    func failedShortAdvancesAfterWaiting() {
        let settings = AppSettings()  // auto-scroll off
        #expect(ShortsEndOfVideoDecision.advancesAfterWaiting(settings: settings, failed: true))
        #expect(ShortsEndOfVideoDecision.advancesAfterWaiting(settings: settings, failed: false) == false)

        var autoScroll = AppSettings()
        autoScroll.shortsAutoScroll = true
        #expect(ShortsEndOfVideoDecision.advancesAfterWaiting(settings: autoScroll, failed: false))
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

    @Test("SponsorBlock for Shorts reads off while SponsorBlock is off and comes back with it")
    func sponsorBlockFollowsGlobalSwitch() {
        var settings = AppSettings()
        settings.sponsorBlockEnabled = true
        settings.shortsSponsorBlock = true
        #expect(settings.shortsSponsorBlockActive)

        settings.sponsorBlockEnabled = false
        #expect(!settings.shortsSponsorBlockActive)
        #expect(settings.shortsSponsorBlock)

        settings.sponsorBlockEnabled = true
        #expect(settings.shortsSponsorBlockActive)

        settings.shortsSponsorBlock = false
        #expect(!settings.shortsSponsorBlockActive)
    }

    @Test("shortsFillScreen defaults to off (also for old JSON) and survives a round-trip when on")
    func fillScreenPersistence() throws {
        #expect(AppSettings().shortsFillScreen == false)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(legacy.shortsFillScreen == false)

        var settings = AppSettings()
        settings.shortsFillScreen = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.shortsFillScreen == true)
    }
}
