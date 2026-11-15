import AVFoundation
import SmartTubeIOSCore
import os

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - Stats for Nerds

extension PlaybackViewModel {

    public func toggleStatsForNerds() {
        statsForNerdsVisible.toggle()
        if statsForNerdsVisible { updateStatsSnapshot() }
    }

    func updateStatsSnapshot() {
        guard let item = player.currentItem else {
            statsSnapshot = .empty
            return
        }
        let logEvent = item.accessLog()?.events.last
        let videoId = playerInfo?.video.id ?? currentVideo?.id ?? ""

        // Resolution — always derived from AVPlayer's presentationSize (the actual decoded
        // video dimensions). This is the ground truth: if a quality switch is in flight the
        // old resolution is shown until the new composition becomes readyToPlay, which is
        // honest. Showing selectedFormat metadata here caused stats to report 256×144 while
        // the player was actually decoding 640×360 (the VP9 WebM quality-switch failure).
        let presentationSize = item.presentationSize
        let res: String
        if presentationSize.width > 0 && presentationSize.height > 0 {
            res = "\(Int(presentationSize.width))×\(Int(presentationSize.height))"
        } else {
            res = "—"
        }

        let fps = selectedFormat?.fps ?? 0

        // Codec: reflect the stream type in the stats overlay.
        // All quality is delivered via HLS; use the selected format's mimeType when available.
        let codec: String
        if let fmt = selectedFormat {
            codec = Self.extractCodec(from: fmt.mimeType)
        } else if playerInfo?.hlsURL != nil {
            codec = "HLS"
        } else if playerInfo?.dashURL != nil {
            codec = "DASH"
        } else if let fmt = playerInfo?.formats.first {
            codec = Self.extractCodec(from: fmt.mimeType)
        } else {
            codec = "—"
        }

        let nominalBitrate: String
        if let br = selectedFormat?.bitrate, br > 0 {
            nominalBitrate = Self.formatBitrate(br)
        } else if playerInfo?.hlsURL != nil || playerInfo?.dashURL != nil {
            nominalBitrate = L10n.string("Adaptive")
        } else if let br = playerInfo?.formats.first?.bitrate, br > 0 {
            nominalBitrate = Self.formatBitrate(br)
        } else {
            nominalBitrate = "—"
        }

        let observedBitrate: String
        if let br = logEvent?.observedBitrate, br > 0 {
            observedBitrate = Self.formatBitrate(Int(br))
        } else {
            observedBitrate = "—"
        }

        let droppedFrames = logEvent.map { $0.numberOfDroppedVideoFrames } ?? 0
        let stalls = logEvent.map { $0.numberOfStalls } ?? 0

        let resSource = selectedFormat != nil ? "selectedFormat(\(selectedFormat!.qualityLabel))" : "presentationSize"
        // Only forward to Crashlytics breadcrumbs when something meaningful changed.
        // Silent 0.5 s ticks otherwise saturate the 64 KB breadcrumb buffer and push
        // critical events (load, quality switch, errors) out of the window.
        let prevSnap = statsSnapshot
        let codecChanged = codec != prevSnap.codec && prevSnap.codec != "—"
        let resChanged = res != prevSnap.displayResolution && prevSnap.displayResolution != "—"
        let isFirstSnap = prevSnap.videoId != videoId
        if isFirstSnap || codecChanged || resChanged {
            playerLog.notice(
                "[stats] snapshot — res=\(res) codec=\(codec) source=\(resSource)\(codecChanged ? " ⚠️codec-changed" : "")\(resChanged ? " ⚠️res-changed" : "")"
            )
        } else {
            playerLog.debug("[stats] snapshot — res=\(res) codec=\(codec) source=\(resSource)")
        }

        statsSnapshot = StatsForNerdsSnapshot(
            videoId: videoId,
            displayResolution: res,
            fps: fps,
            codec: codec,
            nominalBitrate: nominalBitrate,
            observedBitrate: observedBitrate,
            droppedFrames: droppedFrames,
            stalls: stalls,
            pendingQualityLabel: qualityManager.pendingQualityLabel,
            reportID: CrashlyticsLogger.sessionReportID,
            timeToPlayMs: timeToPlayMs,
            timeToHighQualityMs: timeToHighQualityMs,
            cacheStatus: cacheStatusSummary,
            streamURL: lastAttemptedStreamURL.map {
                let host = $0.host ?? ""
                let components = $0.pathComponents.filter { $0 != "/" }.prefix(3)
                let path = components.isEmpty ? "" : "/" + components.joined(separator: "/")
                return host + path
            } ?? "—",
            streamType: lastSuccessfulStreamType
        )
    }

    static func extractCodec(from mimeType: String) -> String {
        if mimeType.contains("mpegURL") || mimeType.contains("m3u8") { return "HLS" }
        if let range = mimeType.range(of: #"codecs="([^"]+)""#, options: .regularExpression) {
            let matched = String(mimeType[range])
            if let valueRange = matched.range(of: #"(?<==)[^"]+"#, options: .regularExpression) {
                let codecs = String(matched[valueRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let first =
                    codecs.components(separatedBy: ",").first?
                    .trimmingCharacters(in: .whitespaces) ?? codecs
                return first.components(separatedBy: ".").first ?? first
            }
        }
        if mimeType.contains("mp4") { return "mp4" }
        if mimeType.contains("webm") { return "webm" }
        return mimeType.isEmpty ? "—" : mimeType
    }

    static func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 { return String(format: "%.1f Mbps", Double(bps) / 1_000_000) }
        if bps >= 1_000 { return String(format: "%.0f kbps", Double(bps) / 1_000) }
        return "\(bps) bps"
    }
}

// MARK: - StatsForNerdsSnapshot

/// Snapshot of playback diagnostics for the "Stats for Nerds" overlay.
public struct StatsForNerdsSnapshot: Sendable {
    public var videoId: String
    public var displayResolution: String
    public var fps: Int
    public var codec: String
    public var nominalBitrate: String
    public var observedBitrate: String
    public var droppedFrames: Int
    public var stalls: Int
    /// Quality label most recently selected by the user — persists after CDN failures
    /// so Stats for Nerds can show user intent vs actual delivery.
    public var pendingQualityLabel: String
    /// Session report ID — matches the `report_id` custom key stamped on Crashlytics
    /// reports. Quote this when sending a diagnostic report so the developer can
    /// locate the exact session in Firebase.
    public var reportID: String
    /// Elapsed ms from `load()` to the first `readyToPlay` (low-quality fast-start frame). 0 = not yet measured.
    public var timeToPlayMs: Int
    /// Elapsed ms from `load()` to the quality-ramp task firing (~readyToPlay + 800 ms). 0 = not yet measured.
    public var timeToHighQualityMs: Int
    /// Cache hit/miss summary at load time (e.g. "pi:HIT wkHLS:MISS").
    public var cacheStatus: String
    /// Host + path of the stream URL handed to AVPlayer (no query string). Empty when not yet loaded.
    public var streamURL: String
    /// Which loading path produced the current stream (e.g. "primaryHLS", "webView/HLS").
    public var streamType: String

    public static let empty = StatsForNerdsSnapshot(
        videoId: "",
        displayResolution: "",
        fps: 0,
        codec: "",
        nominalBitrate: "",
        observedBitrate: "",
        droppedFrames: 0,
        stalls: 0,
        pendingQualityLabel: "",
        reportID: CrashlyticsLogger.sessionReportID,
        timeToPlayMs: 0,
        timeToHighQualityMs: 0,
        cacheStatus: "",
        streamURL: "",
        streamType: ""
    )
}
