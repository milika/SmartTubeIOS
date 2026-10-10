import Foundation
import Testing

@testable import CasioClockWidget

@Suite("Steps")
struct StepsTests {
    private func freshDefaults() throws -> UserDefaults {
        let name = "CasioStepsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("progress runs from 0 to 1 at the 10,000-step goal and stays there")
    func progress() {
        #expect(CasioSteps.goal == 10_000)
        #expect(CasioSteps.progress(nil) == 0)
        #expect(CasioSteps.progress(0) == 0)
        #expect(CasioSteps.progress(5_000) == 0.5)
        #expect(CasioSteps.progress(10_000) == 1)
        #expect(CasioSteps.progress(25_000) == 1)
    }

    @Test("the ABL-100WE lights one of 17 bars per full 1/17 of the goal")
    func ablSegments() {
        #expect(ABL100WEDisplay.litSegments(steps: nil) == 0)
        #expect(ABL100WEDisplay.litSegments(steps: 587) == 0)
        #expect(ABL100WEDisplay.litSegments(steps: 589) == 1)
        #expect(ABL100WEDisplay.litSegments(steps: 5_000) == 8)
        #expect(ABL100WEDisplay.litSegments(steps: 9_999) == 16)
        #expect(ABL100WEDisplay.litSegments(steps: 10_000) == 17)
        #expect(ABL100WEDisplay.litSegments(steps: 40_000) == 17)
    }

    @Test("a stored count is used the same day only (a locked iPhone can't read Health)")
    func cache() throws {
        let defaults = try freshDefaults()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let morning = Date(timeIntervalSince1970: 1_782_000_000)
        #expect(CasioSteps.cached(now: morning, calendar: calendar, defaults: defaults) == nil)
        CasioSteps.store(4_321, at: morning, defaults: defaults)
        #expect(
            CasioSteps.cached(now: morning.addingTimeInterval(3600), calendar: calendar, defaults: defaults) == 4_321)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: morning)))
        #expect(CasioSteps.cached(now: tomorrow, calendar: calendar, defaults: defaults) == nil)
    }

    @Test("only the ABL-100WE reads steps")
    func stepModels() {
        #expect(CasioModels.all.filter { $0.usesSteps }.map { $0.kind } == ["CasioABL100WE"])
    }
}
