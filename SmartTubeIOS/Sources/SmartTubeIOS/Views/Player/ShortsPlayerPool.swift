#if os(iOS)
import Foundation
import SmartTubeIOSCore
import os

private let poolLog = Logger(subsystem: "com.void.smarttube.app", category: "ShortsPlayer")

/// A fixed set of Shorts embed players: the live Short plus its next and previous
/// neighbours, each in its own `WKWebView`.
///
/// Neighbours load in "held" mode — muted and paused on their first decoded frame
/// with their stream buffered — so a swipe slides the real video in and it starts
/// at once, instead of pointing one web view at a new Short after the swipe.
///
/// Every player keeps its own slot in `ShortsPlayerView` for its whole life; only the
/// slot's offset changes while paging. Moving a WKWebView to another container
/// leaves it black (#279), so the pool never does that — it changes *which Short*
/// a slot holds instead (`ShortsSlotPlanner`).
@MainActor
@Observable
final class ShortsPlayerPool {
    /// Live, next and previous.
    static let slotCount = 3

    let players: [ShortsEmbedPlayerViewModel]
    private(set) var liveSlot = 0

    /// The player showing the current Short.
    var live: ShortsEmbedPlayerViewModel { players[liveSlot] }

    init(api: InnerTubeAPI) {
        players = (0..<Self.slotCount).map { _ in ShortsEmbedPlayerViewModel(api: api) }
    }

    /// The player holding `videoId`, if any.
    func player(holding videoId: String) -> ShortsEmbedPlayerViewModel? {
        players.first { $0.video?.id == videoId }
    }

    /// Makes `video` the playing Short and preloads `neighbours` (most important
    /// first) in the other slots. A Short that is already preloaded starts from its
    /// buffered first frame; the Short it replaces goes back on hold.
    func show(live video: Video, neighbours: [Video], settings: AppSettings) {
        let plan = plan(live: video, neighbours: neighbours)
        guard let newLive = plan.firstIndex(of: video.id) else { return }
        if newLive != liveSlot { live.deactivate() }
        liveSlot = newLive
        load(plan, from: [video] + neighbours, settings: settings)

        let player = players[newLive]
        if !player.isLive {
            player.updateSettings(settings)
            player.activate()
        }
        poolLog.notice(
            "[pool] live=\(player.logTag, privacy: .public) videoId=\(video.id, privacy: .public) slots=\(self.summary, privacy: .public)"
        )
    }

    /// Preloads `neighbours` around the live Short without touching it (the feed
    /// grew or dropped Shorts around it).
    func preload(neighbours: [Video], settings: AppSettings) {
        guard let liveVideo = live.video else { return }
        let plan = plan(live: liveVideo, neighbours: neighbours)
        guard plan.firstIndex(of: liveVideo.id) == liveSlot else { return }
        load(plan, from: neighbours, settings: settings)
    }

    func updateSettings(_ settings: AppSettings) {
        for player in players { player.updateSettings(settings) }
    }

    /// `updateSettings(_:)` that also reloads SponsorBlock segments affected by it.
    func syncSettings(_ settings: AppSettings) {
        for player in players { player.syncSettings(settings) }
    }

    func updateChannelId(_ channelId: String?, for videoId: String) {
        for player in players { player.updateChannelId(channelId, for: videoId) }
    }

    // MARK: - Private

    private func plan(live video: Video, neighbours: [Video]) -> [String?] {
        ShortsSlotPlanner.plan(
            held: players.map { $0.video?.id },
            wanted: [video.id] + neighbours.map(\.id))
    }

    /// Loads every slot whose planned Short differs from the one it holds.
    private func load(_ plan: [String?], from videos: [Video], settings: AppSettings) {
        for (slot, videoId) in plan.enumerated() {
            let player = players[slot]
            guard let videoId, player.video?.id != videoId,
                let video = videos.first(where: { $0.id == videoId })
            else { continue }
            player.updateSettings(settings)
            player.loadShort(video: video, live: slot == liveSlot)
        }
    }

    private var summary: String {
        players.enumerated()
            .map { "\($0.offset):\($0.element.video?.id ?? "-")\($0.offset == liveSlot ? "*" : "")" }
            .joined(separator: " ")
    }
}
#endif
