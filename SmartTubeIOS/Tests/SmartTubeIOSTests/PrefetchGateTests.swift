import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - PrefetchGateTests
//
// Background prefetch must stop asking YouTube about videos while the network is blocked,
// and must not re-ask about videos that just failed.

@Suite("Prefetch gate")
struct PrefetchGateTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("a fresh gate allows every video")
    func allowsByDefault() {
        let gate = PrefetchGate()
        #expect(gate.allows(videoId: "a", now: start))
        #expect(!gate.isPaused(now: start))
    }

    @Test("a network block stops all prefetching for the pause, then allows it again")
    func networkBlockPauses() {
        var gate = PrefetchGate()
        gate.noteNetworkBlock(now: start)
        #expect(gate.isPaused(now: start))
        #expect(!gate.allows(videoId: "a", now: start.addingTimeInterval(PrefetchGate.networkBlockPause - 1)))
        #expect(gate.allows(videoId: "a", now: start.addingTimeInterval(PrefetchGate.networkBlockPause)))
    }

    @Test("a failed video is skipped until its failure expires; other videos are not")
    func failedVideoIsSkipped() {
        var gate = PrefetchGate()
        gate.noteFailure(videoId: "a", now: start)
        #expect(!gate.allows(videoId: "a", now: start.addingTimeInterval(PrefetchGate.failedVideoTTL - 1)))
        #expect(gate.allows(videoId: "b", now: start))
        #expect(gate.allows(videoId: "a", now: start.addingTimeInterval(PrefetchGate.failedVideoTTL)))
    }

    @Test("a later success clears the failure")
    func successClearsFailure() {
        var gate = PrefetchGate()
        gate.noteFailure(videoId: "a", now: start)
        gate.noteSuccess(videoId: "a")
        #expect(gate.allows(videoId: "a", now: start))
    }
}
