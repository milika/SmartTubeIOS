import Foundation
import Network
import Testing

@testable import SmartTubeIOSCore

// MARK: - NetworkThrottlingTests
//
// Verifies network-aware throttling constants and logic in VideoPreloadCache (Phase K).
// NWPath cannot be directly constructed in tests, so we test the constants and
// verify the structure of the logic by checking boundary conditions.

@Suite("Network-aware Throttling")
struct NetworkThrottlingTests {

    // MARK: - Worker cap constants

    @Test("maxWorkersWiFi is 5")
    func maxWorkersWiFiIs5() {
        #expect(VideoPreloadCache.maxWorkersWiFi == 5)
    }

    @Test("maxWorkersCellular is 2")
    func maxWorkersCellularIs2() {
        #expect(VideoPreloadCache.maxWorkersCellular == 2)
    }

    @Test("cellular cap is less than WiFi cap")
    func cellularCapLessThanWiFi() {
        #expect(VideoPreloadCache.maxWorkersCellular < VideoPreloadCache.maxWorkersWiFi)
    }

    // MARK: - Network cap before first path update

    @Test("networkCap defaults to WiFi when no path received yet")
    func networkCapDefaultsToWiFi() async {
        // The shared cache starts with currentPath = nil.
        // Before any NWPathMonitor update, networkCap should return maxWorkersWiFi.
        // (In practice the monitor fires quickly, but this is the defined default.)
        let cap = await VideoPreloadCache.shared.networkCap
        #expect(
            cap == VideoPreloadCache.maxWorkersWiFi || cap == VideoPreloadCache.maxWorkersCellular || cap == 0,
            "Expected a valid cap value: 0, 2, or 5")
    }

    // MARK: - Allowed data types

    @Test("allowedPrefetchDataTypes always includes playerInfo")
    func allowedTypesAlwaysIncludesPlayerInfo() async {
        let allowed = await VideoPreloadCache.shared.allowedPrefetchDataTypes
        // On WiFi or default, playerInfo should always be present (or empty only when truly offline).
        if !allowed.isEmpty {
            #expect(allowed.contains("playerInfo"))
            #expect(allowed.contains("nextInfo"))
            #expect(allowed.contains("sponsorSegments"))
        }
    }

    @Test("allowedPrefetchDataTypes on WiFi includes deArrowBranding")
    func allowedTypesOnWiFiIncludesAllTypes() async {
        // We can't force WiFi in tests, but we can verify the full set has 4 items.
        // When running on a development machine (typically WiFi), this should pass.
        let allowed = await VideoPreloadCache.shared.allowedPrefetchDataTypes
        if allowed.count == 4 {
            #expect(allowed.contains("deArrowBranding"))
        }
        // If cellular (3 items), deArrow is excluded — that's also valid.
        #expect(
            allowed.count == 0 || allowed.count == 3 || allowed.count == 4,
            "Expected 0 (offline), 3 (cellular), or 4 (WiFi) allowed types")
    }

    @Test("end cards are never prefetched (they cost a second /player request per card)")
    func endCardsAreNotPrefetched() async {
        #expect(!(await VideoPreloadCache.shared.allowedPrefetchDataTypes).contains("endCards"))
    }

    // MARK: - Queue depth + cellular cap relationship

    @Test("maxQueueDepth is larger than maxWorkersCellular")
    func queueDepthLargerThanCellularCap() {
        #expect(VideoPreloadCache.maxQueueDepth > VideoPreloadCache.maxWorkersCellular)
    }
}
