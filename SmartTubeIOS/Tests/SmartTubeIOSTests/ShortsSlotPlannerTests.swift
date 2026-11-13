import Testing

@testable import SmartTubeIOSCore

@Suite("Shorts slot planner")
struct ShortsSlotPlannerTests {

    @Test("Empty slots are filled in priority order")
    func fillsEmptySlots() {
        let plan = ShortsSlotPlanner.plan(held: [nil, nil, nil], wanted: ["live", "next", "prev"])
        #expect(plan == ["live", "next", "prev"])
    }

    @Test("Swiping forward keeps the preloaded next Short in its slot")
    func forwardSwipeReusesNext() {
        // Was on B (slot 1) with C preloaded in slot 2 and A in slot 0; now on C.
        let plan = ShortsSlotPlanner.plan(held: ["A", "B", "C"], wanted: ["C", "D", "B"])
        #expect(plan == ["D", "B", "C"])
    }

    @Test("Swiping back keeps the retired Short in its slot")
    func backwardSwipeReusesPrevious() {
        let plan = ShortsSlotPlanner.plan(held: ["D", "B", "C"], wanted: ["B", "C", "A"])
        #expect(plan == ["A", "B", "C"])
    }

    @Test("Slots that aren't needed keep nothing assigned")
    func unneededSlotsStayUnassigned() {
        // First Short of the feed: no previous.
        let plan = ShortsSlotPlanner.plan(held: ["A", "B", "Z"], wanted: ["A", "B"])
        #expect(plan == ["A", "B", nil])
    }

    @Test("Duplicate wanted ids and duplicate held ids are each placed once")
    func duplicates() {
        let plan = ShortsSlotPlanner.plan(held: ["A", "A", nil], wanted: ["A", "A", "B"])
        #expect(plan == ["A", "B", nil])
    }

    @Test("More wanted Shorts than slots drops the lowest priority")
    func tooManyWanted() {
        let plan = ShortsSlotPlanner.plan(held: [nil, nil], wanted: ["live", "next", "prev"])
        #expect(plan == ["live", "next"])
    }
}
