// Downloading is compiled out (App Store guideline 5.2.3). Define ENABLE_DOWNLOADS to build it.
#if ENABLE_DOWNLOADS
import AVFoundation
import Foundation
import Observation
import SmartTubeIOSCore
import os

#if os(iOS)
import Photos
#endif
#if os(iOS)
@preconcurrency import ActivityKit
#endif

private let downloadLog = CrashlyticsLogger(category: "Download")

// MARK: - VideoDownloadService
//
// Downloads a YouTube video stream to the device's Photos library.
// Uses InnerTubeAPI to resolve the best stream URL, then downloads the
// file to a temp location before saving it via PHPhotoLibrary.

@MainActor
@Observable
public final class VideoDownloadService {

    // MARK: - State

    public enum DownloadState: Equatable {
        case idle
        case fetching
        case downloading(progress: Double)
        case saving
        case done
        case failed(String)

        public var isActive: Bool {
            switch self {
            case .fetching, .downloading, .saving: return true
            default: return false
            }
        }
    }

    public private(set) var state: DownloadState = .idle

    // MARK: - Private

    private let api: InnerTubeAPI
    private var downloadTask: Task<Void, Never>?

    #if os(iOS)
    @available(iOS 16.1, *)
    @ObservationIgnored
    private var liveActivity: Activity<DownloadActivityAttributes>?
    #endif

    /// URLSession used for all YouTube CDN downloads.
    /// httpAdditionalHeaders cannot override User-Agent on iOS — must use URLRequest.setValue.
    private static let cdnSession = URLSession(configuration: .default)

    /// Builds a URLRequest for a YouTube CDN URL.
    /// - `alr=yes` signals the CDN to respond with the full stream rather than an
    ///   initial probe chunk. Without it, adaptive-stream URLs often return 403.
    /// - `userAgent` must match the client that signed the URL (`c=` parameter):
    ///   Web → desktop Chrome, TV-auth → Cobalt, iOS → native iOS app UA.
    nonisolated private static func cdnRequest(
        for url: URL, userAgent: String = InnerTubeClients.iOS.userAgent
    ) -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "alr" }) {
            queryItems.append(URLQueryItem(name: "alr", value: "yes"))
        }
        components?.queryItems = queryItems
        let finalURL = components?.url ?? url
        var req = URLRequest(url: finalURL)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    // MARK: - Init

    public init(api: InnerTubeAPI = InnerTubeAPI()) {
        self.api = api
    }

    // MARK: - Public

    public func download(video: Video) {
        guard !state.isActive else { return }
        state = .fetching
        #if os(iOS)
        if #available(iOS 16.1, *) {
            startLiveActivity(video: video)
        }
        #endif
        downloadTask = Task { await performDownload(video: video) }
    }

    public func reset() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    // MARK: - Private implementation

    // MARK: Live Activity helpers

    #if os(iOS)
    @available(iOS 16.1, *)
    private func startLiveActivity(video: Video) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = DownloadActivityAttributes(videoTitle: video.title)
        let state = DownloadActivityAttributes.DownloadContentState(progress: 0, phase: .fetching)
        do {
            liveActivity = try Activity<DownloadActivityAttributes>.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            downloadLog.notice("[download] Live Activity unavailable: \(error.localizedDescription)")
        }
    }

    @available(iOS 16.1, *)
    private func updateLiveActivity(
        phase: DownloadActivityAttributes.DownloadContentState.Phase,
        progress: Double = 0
    ) async {
        guard let activity = liveActivity else { return }
        let newState = DownloadActivityAttributes.DownloadContentState(progress: progress, phase: phase)
        // Activity<T> is a Sendable struct; dispatch the await via a nonisolated helper to
        // satisfy Swift 6 region isolation — the value is safely copied out of the @MainActor region.
        await Self.sendActivityUpdate(activity, state: newState)
    }

    @available(iOS 16.1, *)
    private func endLiveActivity(phase: DownloadActivityAttributes.DownloadContentState.Phase) async {
        guard let activity = liveActivity else { return }
        let finalState = DownloadActivityAttributes.DownloadContentState(progress: 1, phase: phase)
        liveActivity = nil  // nil out on @MainActor before sending the value across the boundary
        await Self.sendActivityEnd(activity, state: finalState)
    }

    /// Dispatches `Activity.update` from a nonisolated context.
    /// `Activity<T>` is a `Sendable` struct so transferring it via `sending` is safe.
    @available(iOS 16.1, *)
    nonisolated private static func sendActivityUpdate(
        _ activity: sending Activity<DownloadActivityAttributes>,
        state: DownloadActivityAttributes.DownloadContentState
    ) async {
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    /// Dispatches `Activity.end` from a nonisolated context. See `sendActivityUpdate` for rationale.
    @available(iOS 16.1, *)
    nonisolated private static func sendActivityEnd(
        _ activity: sending Activity<DownloadActivityAttributes>,
        state: DownloadActivityAttributes.DownloadContentState
    ) async {
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 4))
    }
    #endif

    // MARK: Download orchestration

    private func performDownload(video: Video) async {
        do {
            guard await requestPhotoAddAccess() else {
                state = .failed("Photo library access is required to save the video")
                #if os(iOS)
                if #available(iOS 16.1, *) { await endLiveActivity(phase: .failed) }
                #endif
                return
            }

            if let tempURL = await tryDirectDownload(videoId: video.id) {
                downloadLog.notice("[download] remuxing for Photos compatibility")
                #if os(iOS)
                if #available(iOS 16.1, *) { await updateLiveActivity(phase: .saving, progress: 1) }
                #endif
                let photosURL = try await passthroughRemux(inputURL: tempURL, videoId: video.id, suffix: "muxed")
                try? FileManager.default.removeItem(at: tempURL)
                state = .saving
                try await saveToPhotoLibrary(fileURL: photosURL)
                storeInDownloadStore(video: video, mergedFileURL: photosURL)
                try? FileManager.default.removeItem(at: photosURL)
                downloadLog.notice("[download] ✅ saved to Photos \(video.id)")
                state = .done
                #if os(iOS)
                if #available(iOS 16.1, *) { await endLiveActivity(phase: .done) }
                #endif
                return
            }

            downloadLog.notice("[download] direct download failed, trying adaptive merge fallback")
            #if os(iOS)
            if #available(iOS 16.1, *) { await updateLiveActivity(phase: .downloading, progress: 0.1) }
            #endif
            let androidInfo = try await api.fetchPlayerInfoAndroid(videoId: video.id)
            downloadLog.notice("[download] adaptive fallback formats=\(androidInfo.formats.count)")
            for (i, fmt) in androidInfo.formats.enumerated() {
                downloadLog.notice(
                    "[download]   [\(i)] mime=\(fmt.mimeType) label=\(fmt.label) hasURL=\(fmt.url != nil) bitrate=\(fmt.bitrate ?? 0)"
                )
            }
            guard let videoURL = androidInfo.bestAdaptiveVideoURL,
                let audioURL = androidInfo.bestAdaptiveAudioURL
            else {
                downloadLog.error("[download] ❌ no adaptive video/audio streams found")
                state = .failed("No downloadable stream found for this video")
                #if os(iOS)
                if #available(iOS 16.1, *) { await endLiveActivity(phase: .failed) }
                #endif
                return
            }
            downloadLog.notice("[download] merging adaptive videoURL prefix=\(videoURL.absoluteString.prefix(60))")
            downloadLog.notice("[download] merging adaptive audioURL prefix=\(audioURL.absoluteString.prefix(60))")
            state = .downloading(progress: 0)
            let mergedURL = try await mergeAdaptiveStreams(
                videoURL: videoURL, audioURL: audioURL, videoId: video.id,
                userAgent: InnerTubeClients.Android.userAgent)
            state = .saving
            #if os(iOS)
            if #available(iOS 16.1, *) { await updateLiveActivity(phase: .saving, progress: 1) }
            #endif
            try await saveToPhotoLibrary(fileURL: mergedURL)
            storeInDownloadStore(video: video, mergedFileURL: mergedURL)
            try? FileManager.default.removeItem(at: mergedURL)
            downloadLog.notice("[download] ✅ adaptive merge saved to Photos \(video.id)")
            state = .done
            #if os(iOS)
            if #available(iOS 16.1, *) { await endLiveActivity(phase: .done) }
            #endif
        } catch is CancellationError {
            state = .idle
            #if os(iOS)
            if #available(iOS 16.1, *) { await endLiveActivity(phase: .failed) }
            #endif
        } catch {
            let nsErr = error as NSError
            downloadLog.error(
                "[download] ❌ failed: domain=\(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription)")
            let userMessage: String
            if nsErr.domain == "PHPhotosErrorDomain" {
                userMessage =
                    "Could not save to Photos. Please check Settings → Privacy & Security → Photos and allow SmartTube to add photos."
            } else if let urlErr = error as? URLError, urlErr.code == .fileDoesNotExist {
                userMessage = "Download failed — the video file was removed before saving. Please try again."
            } else {
                userMessage = error.localizedDescription
            }
            state = .failed(userMessage)
            #if os(iOS)
            if #available(iOS 16.1, *) { await endLiveActivity(phase: .failed) }
            #endif
        }
    }

    /// Tries Web client then Android client for a direct muxed MP4 download.
    /// Returns the temp file URL on success, nil if no muxed stream could be found.
    /// Note: TVHTML5-signed CDN URLs always return 403 when fetched without session cookies,
    /// so the Android client (c=ANDROID URLs) is used as the reliable fallback.
    private func tryDirectDownload(videoId: String) async -> URL? {
        let candidates: [(String, String, () async throws -> PlayerInfo)] = [
            (
                "Web", InnerTubeClients.Web.userAgent,
                { [self] in try await api.fetchPlayerInfoForDownload(videoId: videoId) }
            ),
            (
                "Android", InnerTubeClients.Android.userAgent,
                { [self] in try await api.fetchPlayerInfoAndroid(videoId: videoId) }
            ),
        ]
        for (label, clientUA, fetch) in candidates {
            guard let info = try? await fetch() else {
                downloadLog.notice("[download] \(label) client failed or UNPLAYABLE, trying next")
                continue
            }
            downloadLog.notice("[download] \(label) formats=\(info.formats.count) hlsURL=\(info.hlsURL != nil)")
            for (i, fmt) in info.formats.enumerated() {
                downloadLog.notice(
                    "[download]   [\(i)] mime=\(fmt.mimeType) label=\(fmt.label) hasURL=\(fmt.url != nil) bitrate=\(fmt.bitrate ?? 0)"
                )
            }
            guard let muxedURL = info.bestMuxedDownloadURL else {
                downloadLog.notice("[download] \(label) — no muxed MP4, trying next")
                continue
            }
            downloadLog.notice("[download] \(label) ✅ muxed URL found, downloading")
            state = .downloading(progress: 0)
            #if os(iOS)
            if #available(iOS 16.1, *) { await updateLiveActivity(phase: .downloading, progress: 0) }
            #endif
            if let tempURL = try? await downloadToTemp(url: muxedURL, videoId: videoId, userAgent: clientUA) {
                let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
                downloadLog.notice("[download] \(label) download complete bytes=\(size)")
                guard size > 0 else {
                    downloadLog.notice("[download] \(label) — 0 bytes, YouTube rejected URL, trying next")
                    try? FileManager.default.removeItem(at: tempURL)
                    continue
                }
                return tempURL
            }
        }
        return nil
    }

    /// Remuxes an MP4 file into a new container using passthrough (no re-encoding).
    /// Fixes PHPhotosErrorDomain 3302 caused by moov-at-end MP4 containers from YouTube.
    private nonisolated func passthroughRemux(inputURL: URL, videoId: String, suffix: String) async throws -> URL {
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(videoId)-\(suffix)-remux.mp4")
        try? FileManager.default.removeItem(at: destURL)
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw URLError(.badServerResponse)
        }
        session.outputURL = destURL
        session.outputFileType = .mp4
        await session.export()
        if let error = session.error {
            downloadLog.error("[download] passthrough remux error: \(error.localizedDescription)")
            throw error
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int) ?? 0
        downloadLog.notice("[download] passthrough remux done bytes=\(size)")
        return destURL
    }

    /// Downloads best adaptive video-only and audio-only MP4 streams concurrently,
    /// then merges them into a single MP4 using AVAssetWriter for true passthrough
    /// (sample-level copy, no re-encode of codec data).
    private nonisolated func mergeAdaptiveStreams(
        videoURL: URL, audioURL: URL, videoId: String,
        userAgent: String = InnerTubeClients.iOS.userAgent
    ) async throws -> URL {
        // Download both streams concurrently with explicit UA per-request
        let videoReq = VideoDownloadService.cdnRequest(for: videoURL, userAgent: userAgent)
        let audioReq = VideoDownloadService.cdnRequest(for: audioURL, userAgent: userAgent)
        async let videoTemp = VideoDownloadService.cdnSession.download(for: videoReq)
        async let audioTemp = VideoDownloadService.cdnSession.download(for: audioReq)
        let (videoResult, audioResult) = try await (videoTemp, audioTemp)

        let videoStatus = (videoResult.1 as? HTTPURLResponse)?.statusCode ?? 0
        let audioStatus = (audioResult.1 as? HTTPURLResponse)?.statusCode ?? 0
        let videoFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(videoId)-vid.mp4")
        let audioFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(videoId)-aud.mp4")
        try? FileManager.default.removeItem(at: videoFile)
        try? FileManager.default.removeItem(at: audioFile)
        try FileManager.default.moveItem(at: videoResult.0, to: videoFile)
        try FileManager.default.moveItem(at: audioResult.0, to: audioFile)

        let videoSize = (try? FileManager.default.attributesOfItem(atPath: videoFile.path)[.size] as? Int) ?? 0
        let audioSize = (try? FileManager.default.attributesOfItem(atPath: audioFile.path)[.size] as? Int) ?? 0
        downloadLog.notice(
            "[download] adaptive downloaded videoStatus=\(videoStatus) video=\(videoSize)B audioStatus=\(audioStatus) audio=\(audioSize)B"
        )

        defer {
            try? FileManager.default.removeItem(at: videoFile)
            try? FileManager.default.removeItem(at: audioFile)
        }

        guard videoSize > 0, audioSize > 0 else {
            throw URLError(.zeroByteResource)
        }

        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(videoId)-merged.mp4")
        try? FileManager.default.removeItem(at: destURL)

        // Use AVAssetWriter for true passthrough mux — reads compressed samples directly
        // from the source tracks and writes them to the new container without decoding.
        let videoAsset = AVURLAsset(url: videoFile)
        let audioAsset = AVURLAsset(url: audioFile)

        let videoTrackSrc = try await videoAsset.loadTracks(withMediaType: .video).first
        let audioTrackSrc = try await audioAsset.loadTracks(withMediaType: .audio).first
        guard let videoTrackSrc, let audioTrackSrc else {
            throw URLError(.badServerResponse)
        }

        let videoFmt = try await videoTrackSrc.load(.formatDescriptions).first!
        let audioFmt = try await audioTrackSrc.load(.formatDescriptions).first!
        let duration = try await videoAsset.load(.duration)

        let writer = try AVAssetWriter(outputURL: destURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFmt)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFmt)
        videoInput.expectsMediaDataInRealTime = false
        audioInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)
        writer.add(audioInput)

        let videoReader = try AVAssetReader(asset: videoAsset)
        let audioReader = try AVAssetReader(asset: audioAsset)
        let videoOut = AVAssetReaderTrackOutput(track: videoTrackSrc, outputSettings: nil)
        let audioOut = AVAssetReaderTrackOutput(track: audioTrackSrc, outputSettings: nil)
        videoOut.alwaysCopiesSampleData = false
        audioOut.alwaysCopiesSampleData = false
        videoReader.add(videoOut)
        audioReader.add(audioOut)

        writer.startWriting()
        videoReader.startReading()
        audioReader.startReading()
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "com.smarttube.merge", qos: .userInitiated)
            nonisolated(unsafe) let videoInput = videoInput
            nonisolated(unsafe) let videoOut = videoOut
            nonisolated(unsafe) let audioInput = audioInput
            nonisolated(unsafe) let audioOut = audioOut
            nonisolated(unsafe) let writer = writer

            group.enter()
            videoInput.requestMediaDataWhenReady(on: queue) {
                while videoInput.isReadyForMoreMediaData {
                    if let buf = videoOut.copyNextSampleBuffer() {
                        videoInput.append(buf)
                    } else {
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }

            group.enter()
            audioInput.requestMediaDataWhenReady(on: queue) {
                while audioInput.isReadyForMoreMediaData {
                    if let buf = audioOut.copyNextSampleBuffer() {
                        audioInput.append(buf)
                    } else {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }

            group.notify(queue: queue) {
                writer.finishWriting {
                    if let err = writer.error {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume()
                    }
                }
            }
        }

        let mergedSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int) ?? 0
        downloadLog.notice("[download] adaptive merge done bytes=\(mergedSize)")
        _ = duration  // suppress unused warning
        return destURL
    }

    private func requestPhotoAddAccess() async -> Bool {
        #if os(iOS)
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .authorized, .limited:
            downloadLog.notice("[download] Photos access already authorized")
            return true
        case .notDetermined:
            downloadLog.notice("[download] Requesting Photos add-only permission")
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            let result = granted == .authorized || granted == .limited
            downloadLog.notice("[download] Photos permission result: \(result ? "granted" : "denied")")
            return result
        case .denied:
            downloadLog.error(
                "[download] ❌ Photos access denied — user must enable in Settings → Privacy & Security → Photos")
            return false
        case .restricted:
            downloadLog.error("[download] ❌ Photos access restricted by device policy")
            return false
        @unknown default:
            downloadLog.error("[download] ❌ Unknown Photos authorization status")
            return false
        }
        #else
        return false
        #endif
    }

    /// Copies `mergedFileURL` to the DownloadStore destination and registers the download.
    /// If the copy fails (e.g. disk full) the Photos save is unaffected — this is best-effort.
    private func storeInDownloadStore(video: Video, mergedFileURL: URL) {
        let destURL = DownloadStore.shared.destinationURL(for: video.id)
        let fm = FileManager.default
        try? fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            // Remove a stale file from a previous download of the same video.
            try? fm.removeItem(at: destURL)
            try fm.copyItem(at: mergedFileURL, to: destURL)
        } catch {
            downloadLog.notice("[download] DownloadStore copy failed for \(video.id): \(error.localizedDescription)")
            return
        }
        DownloadStore.shared.add(
            DownloadedVideo(
                videoId: video.id,
                title: video.title,
                channelTitle: video.channelTitle,
                thumbnailURL: video.thumbnailURL,
                duration: video.duration ?? 0,
                fileURL: destURL,
                downloadedAt: Date()
            ))
        downloadLog.notice("[download] registered in DownloadStore \(video.id)")
    }

    private func downloadToTemp(
        url: URL, videoId: String, userAgent: String = InnerTubeClients.iOS.userAgent
    ) async throws -> URL {
        let req = VideoDownloadService.cdnRequest(for: url, userAgent: userAgent)
        let (tempURL, response) = try await VideoDownloadService.cdnSession.download(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
        downloadLog.notice("[download] downloadToTemp status=\(status) bytes=\(size)")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(videoId).mp4")
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    // nonisolated so the closures passed to performChanges carry no @MainActor
    // isolation — Photos calls them on its own serial queue and would crash if
    // the closures were actor-isolated (libdispatch queue assertion).
    private nonisolated func saveToPhotoLibrary(fileURL: URL) async throws {
        #if os(iOS)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let desc = "Video file was removed before saving to Photos: \(fileURL.lastPathComponent)"
            downloadLog.error("[download] ❌ \(desc)")
            throw URLError(.fileDoesNotExist, userInfo: [NSLocalizedDescriptionKey: desc])
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(
                {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                },
                completionHandler: { success, error in
                    if let error {
                        let nsErr = error as NSError
                        downloadLog.error(
                            "[download] ❌ PHPhotoLibrary save error: domain=\(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription)"
                        )
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        // success=false, error=nil means permission was denied or restricted at save time
                        let desc =
                            "Could not save to Photos. Please check Settings → Privacy & Security → Photos and allow SmartTube to add photos."
                        downloadLog.error(
                            "[download] ❌ PHPhotoLibrary performChanges returned success=false with no error — likely permission denied"
                        )
                        let permissionError = NSError(
                            domain: "PHPhotosErrorDomain",
                            code: PHPhotosError.accessRestricted.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: desc]
                        )
                        continuation.resume(throwing: permissionError)
                    }
                })
        }
        #else
        throw URLError(.unsupportedURL)
        #endif
    }
}
#endif  // ENABLE_DOWNLOADS
