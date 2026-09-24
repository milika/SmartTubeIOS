import Testing

@testable import SmartTubeIOS

// MARK: - GestureEdgeZoneTests (#148)

@Suite("GestureEdgeZone.zone(forStartX:viewWidth:)")
struct GestureEdgeZoneTests {

    @Test("touch in the left 20% is the brightness zone")
    func leftEdge() {
        #expect(GestureEdgeZone.zone(forStartX: 10, viewWidth: 400) == .left)
        #expect(GestureEdgeZone.zone(forStartX: 80, viewWidth: 400) == .left)  // exactly 20%
    }

    @Test("touch in the right 20% is the volume zone")
    func rightEdge() {
        #expect(GestureEdgeZone.zone(forStartX: 390, viewWidth: 400) == .right)
        #expect(GestureEdgeZone.zone(forStartX: 320, viewWidth: 400) == .right)  // exactly 80%
    }

    @Test("touch in the middle 60% is no zone")
    func middle() {
        #expect(GestureEdgeZone.zone(forStartX: 200, viewWidth: 400) == nil)
        #expect(GestureEdgeZone.zone(forStartX: 81, viewWidth: 400) == nil)
        #expect(GestureEdgeZone.zone(forStartX: 319, viewWidth: 400) == nil)
    }

    @Test("zero or negative width yields no zone")
    func unusableWidth() {
        #expect(GestureEdgeZone.zone(forStartX: 0, viewWidth: 0) == nil)
        #expect(GestureEdgeZone.zone(forStartX: 0, viewWidth: -10) == nil)
    }

    @Test("custom edge fraction is honored")
    func customFraction() {
        #expect(GestureEdgeZone.zone(forStartX: 90, viewWidth: 400, edgeFraction: 0.25) == .left)
        #expect(GestureEdgeZone.zone(forStartX: 90, viewWidth: 400, edgeFraction: 0.1) == nil)
    }
}
