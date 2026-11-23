import Foundation

/// Decides whether `VideoPreloadCache` may prefetch a video, so a network YouTube is
/// refusing is not sent dozens of background `/player` requests.
///
/// - After a network block (`APIError.ipBlocked`, e.g. YouTube's "confirm you're not a
///   bot" check) all prefetching stops for `networkBlockPause`. Each request from a
///   flagged network can extend the block.
/// - A video whose prefetch failed is skipped for `failedVideoTTL`, so a feed reload
///   does not ask about the same videos again right away.
struct PrefetchGate: Sendable {
    static let networkBlockPause: TimeInterval = 15 * 60
    static let failedVideoTTL: TimeInterval = 10 * 60

    private(set) var pausedUntil: Date?
    private var failedAt: [String: Date] = [:]

    func allows(videoId: String, now: Date) -> Bool {
        if isPaused(now: now) { return false }
        if let failed = failedAt[videoId], now.timeIntervalSince(failed) < Self.failedVideoTTL { return false }
        return true
    }

    func isPaused(now: Date) -> Bool {
        pausedUntil.map { now < $0 } ?? false
    }

    mutating func noteNetworkBlock(now: Date) {
        pausedUntil = now.addingTimeInterval(Self.networkBlockPause)
    }

    mutating func noteFailure(videoId: String, now: Date) {
        failedAt = failedAt.filter { now.timeIntervalSince($0.value) < Self.failedVideoTTL }
        failedAt[videoId] = now
    }

    mutating func noteSuccess(videoId: String) {
        failedAt.removeValue(forKey: videoId)
    }
}
