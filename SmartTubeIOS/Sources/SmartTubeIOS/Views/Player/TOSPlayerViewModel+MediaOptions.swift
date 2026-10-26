#if !os(tvOS)
import Foundation
import os
import SmartTubeIOSCore

private let mediaLog = Logger(subsystem: "com.void.smarttube.app", category: "TOSPlayer")

// MARK: - Media option models
//
// Plain presentation models for the TOS pickers. The raw YouTube player
// objects never cross the WKWebView bridge; the JS helper caches them and
// returns indices, which are resolved back inside the iframe.

struct TOSQualityOption: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let height: Int
}

struct TOSAudioOption: Identifiable, Equatable, Sendable {
    let index: Int
    let id: String
    let name: String
    let languageCode: String
    let isOriginal: Bool
    /// Raw track identifier from the embed. Shown as the picker subtitle when
    /// the localized name could not be resolved, so the user (and logs) can
    /// see what the TV embed actually returned.
    let debugIdentifier: String
}

// MARK: - Media options bridge

extension TOSPlayerViewModel {

    var hasQualityOptions: Bool { !availableQualities.isEmpty }
    var hasCaptionOptions: Bool { !availableCaptions.isEmpty }
    var hasMultipleAudioTracks: Bool { availableAudioTracks.count > 1 }

    // Native captions are the source of truth for TOS: the TV embed's
    // captions module is not reliable, so the tracks come from InnerTube and
    // are rendered by `CaptionCueView` over the video.
    var availableCaptions: [CaptionTrack] { captionsManager.availableCaptions }
    var selectedCaption: CaptionTrack? { captionsManager.selectedCaption }
    var currentCaptionCue: CaptionCue? { captionsManager.currentCaptionCue }

    /// The label shown in the quality pill. Always the *actual* quality
    /// reported by the player, never the requested level.
    var qualityLabel: String {
        actualQuality?.label ?? "Auto"
    }

    var captionsLabel: String {
        guard let track = selectedCaption else { return "CC" }
        return track.languageCode.isEmpty ? track.name : track.languageCode.uppercased()
    }

    var audioTrackLabel: String {
        guard let track = selectedAudioTrack else { return "Audio" }
        // Prefer the localized track name ("English", "Deutsch") the embed/InnerTube
        // reports; fall back to the language code, then a generic label.
        if !track.name.isEmpty, !track.name.hasPrefix("Audio ") { return track.name }
        if !track.languageCode.isEmpty { return track.languageCode.uppercased() }
        return "Audio"
    }

    /// Reads the embed player's current quality / caption / audio-track lists.
    /// Called on ready and after each selection. Safe to call repeatedly; the
    /// saved preferences are applied only once per view model.
    func refreshMediaOptions() async {
        guard isReady, embedFrameInfo != nil else { return }
        guard
            let json = await evalMediaOptionJSON(
                "getOptions",
                "window.__stPlayerAPI ? window.__stPlayerAPI.getOptions() : null")
        else { return }

        guard (json["supported"] as? Bool) == true else {
            mediaLog.notice("[mediaOptions] player API not available in this embed")
            return
        }

        let qualities = parseQualities(json)
        availableQualities = qualities
        if let actualID = json["quality"] as? String, !actualID.isEmpty {
            actualQuality =
                qualities.first(where: { $0.id == actualID })
                ?? TOSQualityOption(
                    id: actualID, label: TOSPlayerTransportSupport.prettyQuality(actualID), height: 0)
        } else {
            actualQuality = nil
        }

        availableAudioTracks = parseAudioTracks(json)
        if let selected = selectedAudioTrack,
            !availableAudioTracks.contains(where: { $0.index == selected.index })
        {
            selectedAudioTrack = nil
        }
        if selectedAudioTrack == nil {
            selectedAudioTrack = availableAudioTracks.first(where: { $0.isOriginal })
        }

        mediaLog.notice(
            "[mediaOptions] qualities=\(qualities.count, privacy: .public) actual=\(self.actualQuality?.id ?? "nil", privacy: .public) captions=\(self.availableCaptions.count, privacy: .public) audio=\(self.availableAudioTracks.count, privacy: .public)"
        )
        if let rawAudio = json["rawAudio"] {
            mediaLog.notice(
                "[mediaOptions] rawAudio=\(String(describing: rawAudio), privacy: .public)"
            )
        }
        if let rawCurrentAudio = json["rawCurrentAudio"] {
            mediaLog.notice(
                "[mediaOptions] rawCurrentAudio=\(String(describing: rawCurrentAudio), privacy: .public)"
            )
        }
        if qualities.isEmpty && availableCaptions.isEmpty && availableAudioTracks.isEmpty {
            mediaLog.notice(
                "[mediaOptions] no options exposed by the embed — raw=\(String(describing: json), privacy: .public)"
            )
        }

        if !hasAppliedMediaPreferences {
            hasAppliedMediaPreferences = true
            await applySavedMediaPreferences()
            // Native captions are the source of truth; make a best-effort
            // attempt to turn the embed's own captions off in case
            // `cc_load_policy=1` forced them on.
            _ = await evalMediaOptionJSON(
                "setCaptionOff",
                "window.__stPlayerAPI ? window.__stPlayerAPI.setCaption(-1) : false")
        }
    }

    // MARK: Native captions (InnerTube captionTracks)

    /// Loads caption tracks from InnerTube. The TV embed does not expose a
    /// usable captions module, so selection/rendering is shared with the
    /// direct player via `CaptionsManager`.
    ///
    /// Concurrent callers coalesce onto a single in-flight fetch; pass
    /// `force: true` (the picker's Reload row) to bypass a completed fetch and
    /// reload from scratch.
    func fetchNativeCaptionTracks(force: Bool = false) async {
        if let inFlight = nativeCaptionsTask {
            await inFlight.value
            if !force { return }
        } else if hasFetchedNativeCaptions && !force {
            return
        }

        isLoadingNativeCaptions = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performNativeCaptionFetch()
        }
        nativeCaptionsTask = task
        await task.value
        nativeCaptionsTask = nil
        isLoadingNativeCaptions = false
    }

    /// One-shot fetch of InnerTube caption tracks with an embed fallback. Only
    /// called from `fetchNativeCaptionTracks`, which owns the in-flight task
    /// and the loading flag.
    private func performNativeCaptionFetch() async {
        var tracks: [CaptionTrack] = []
        var failure: String?
        do {
            // Captions-only fetch: `fetchPlayerInfo` throws for videos whose
            // stream URLs are cipher-protected (SABR) *after* parsing the
            // caption tracks, which silently lost captions for most videos.
            tracks = try await api.fetchCaptionTracks(videoId: videoId)
            mediaLog.notice(
                "[captions] innerTube tracks=\(tracks.count, privacy: .public) videoId=\(self.videoId, privacy: .public)"
            )
        } catch {
            failure = error.localizedDescription
            mediaLog.notice(
                "[captions] fetchCaptionTracks failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        if tracks.isEmpty {
            // Fallback: build VTT URLs from the embed's own caption tracklist
            // (available once `cc_load_policy=1` populated it).
            tracks = await embedCaptionTracks()
            mediaLog.notice(
                "[captions] embed fallback tracks=\(tracks.count, privacy: .public) videoId=\(self.videoId, privacy: .public)"
            )
        }
        captionsManager.availableCaptions = tracks
        if tracks.isEmpty {
            captionLoadError = failure ?? "No caption tracks are available for this video."
            // Allow a later retry (e.g. the user taps Reload).
            hasFetchedNativeCaptions = false
        } else {
            captionLoadError = nil
            hasFetchedNativeCaptions = true
            if captionsManager.selectedCaption == nil,
                let code = settings.preferredCaptionLanguage, !code.isEmpty,
                let match = matchCaption(code)
            {
                selectNativeCaption(match)
            }
        }
    }

    /// Fallback caption source: the embed's `getOption('captions','tracklist')`
    /// only gives language metadata (no VTT URL), so construct YouTube's
    /// timedtext URL for each track.
    private func embedCaptionTracks() async -> [CaptionTrack] {
        guard
            let json = await evalMediaOptionJSON(
                "getCaptionTracks",
                "window.__stPlayerAPI ? window.__stPlayerAPI.getOptions() : null")
        else { return [] }
        let caps = (json["captions"] as? [[String: Any]]) ?? []
        mediaLog.notice("[captions] embed raw tracks=\(String(describing: json["captions"]), privacy: .public)")
        return caps.compactMap { dict in
            guard let languageCode = dict["languageCode"] as? String, !languageCode.isEmpty else {
                return nil
            }
            let auto = dict["isAutoGenerated"] as? Bool ?? false
            var url: URL?
            // Prefer the signed baseUrl from the player response; fall back to
            // a constructed timedtext URL when it is unavailable.
            if let baseURLString = dict["baseUrl"] as? String, !baseURLString.isEmpty,
                var comps = URLComponents(string: baseURLString)
            {
                if !(comps.queryItems?.contains(where: { $0.name == "fmt" }) ?? false) {
                    comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "fmt", value: "vtt")]
                }
                url = comps.url
            }
            if url == nil {
                var comps = URLComponents(string: "https://www.youtube.com/api/timedtext")
                comps?.queryItems = [
                    URLQueryItem(name: "v", value: videoId),
                    URLQueryItem(name: "lang", value: languageCode),
                    URLQueryItem(name: "fmt", value: "vtt"),
                ]
                if auto { comps?.queryItems?.append(URLQueryItem(name: "kind", value: "asr")) }
                url = comps?.url
            }
            guard let finalURL = url else { return nil }
            return CaptionTrack(
                id: (dict["id"] as? String) ?? languageCode,
                baseURL: finalURL,
                name: (dict["name"] as? String) ?? languageCode,
                languageCode: languageCode,
                isAutoGenerated: auto
            )
        }
    }

    func selectNativeCaption(_ track: CaptionTrack?) {
        if let track { lastSelectedCaption = track }
        captionsManager.selectCaption(track, currentTime: currentTime)
    }

    // MARK: Selection

    func selectQuality(_ id: String) async {
        selectedQualityID = id
        let escaped = id.replacingOccurrences(of: "'", with: "\\'")
        _ = await evalMediaOptionJSON(
            "setQuality",
            "window.__stPlayerAPI ? window.__stPlayerAPI.setQuality('\(escaped)') : false")
        await refreshAfterSelection()
    }

    /// Selects a native caption track (nil = off).
    func selectCaption(_ track: CaptionTrack?) {
        selectNativeCaption(track)
    }

    /// One-tap CC toggle for the quick-access row. Turning off keeps
    /// `lastSelectedCaption` and the persisted language preference so the next
    /// tap can restore them; only the picker's explicit "Off" row clears the
    /// preference (handled in the view). If tracks have not loaded yet, fetch
    /// them and then select the first track.
    func toggleCaptions() {
        if !captionsManager.availableCaptions.isEmpty {
            if captionsManager.selectedCaption != nil {
                captionsManager.selectCaption(nil, currentTime: currentTime)
                return
            }
            if let last = lastSelectedCaption,
                captionsManager.availableCaptions.contains(where: { $0.id == last.id })
            {
                selectNativeCaption(last)
                return
            }
            if let code = settings.preferredCaptionLanguage, !code.isEmpty,
                let match = matchCaption(code)
            {
                selectNativeCaption(match)
                return
            }
            if let first = captionsManager.availableCaptions.first {
                selectNativeCaption(first)
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Coalesces with any in-flight ready-time fetch, so a tap during
            // loading still turns captions on once the tracks land.
            await self.fetchNativeCaptionTracks()
            guard self.captionsManager.selectedCaption == nil else { return }
            if let last = self.lastSelectedCaption,
                self.captionsManager.availableCaptions.contains(where: { $0.id == last.id })
            {
                self.selectNativeCaption(last)
            } else if let code = self.settings.preferredCaptionLanguage, !code.isEmpty,
                let match = self.matchCaption(code)
            {
                self.selectNativeCaption(match)
            } else if let first = self.captionsManager.availableCaptions.first {
                self.selectNativeCaption(first)
            }
        }
    }

    private func matchCaption(_ code: String) -> CaptionTrack? {
        let base = code.components(separatedBy: "-").first ?? code
        return captionsManager.availableCaptions.first(where: { $0.languageCode == code })
            ?? captionsManager.availableCaptions.first(where: { $0.languageCode.hasPrefix(base) })
    }

    func selectAudioTrack(index: Int) async {
        selectedAudioTrack = availableAudioTracks.first(where: { $0.index == index })
        _ = await evalMediaOptionJSON(
            "setAudioTrack",
            "window.__stPlayerAPI ? window.__stPlayerAPI.setAudioTrack(\(index)) : false")
        await refreshAfterSelection()
    }

    // MARK: Picker option builders

    func qualityPickerOptions() -> [PlayerPickerOption] {
        var options: [PlayerPickerOption] = [
            PlayerPickerOption(
                id: "auto",
                title: "Auto",
                subtitle: "Let YouTube choose",
                isSelected: selectedQualityID == "auto"
            )
        ]
        options.append(
            contentsOf: availableQualities.map { quality in
                PlayerPickerOption(
                    id: quality.id,
                    title: quality.label,
                    subtitle: nil,
                    isSelected: quality.id == actualQuality?.id
                )
            })
        return options
    }

    func captionPickerOptions() -> [PlayerPickerOption] {
        var options: [PlayerPickerOption] = [
            PlayerPickerOption(
                id: "off",
                title: "Off",
                subtitle: nil,
                isSelected: selectedCaption == nil
            )
        ]
        if availableCaptions.isEmpty {
            options.append(
                PlayerPickerOption(
                    id: "captions-refresh",
                    title: isLoadingNativeCaptions ? "Loading captions…" : "Reload caption tracks",
                    subtitle: isLoadingNativeCaptions
                        ? "Fetching available languages…"
                        : captionLoadError
                            ?? "No tracks yet — the video may have none, or the player has not loaded them.",
                    isSelected: false
                ))
            return options
        }
        options.append(
            contentsOf: availableCaptions.map { track in
                PlayerPickerOption(
                    id: "cap-\(track.id)",
                    title: track.name,
                    subtitle: track.isAutoGenerated ? "Auto-generated" : nil,
                    isSelected: selectedCaption?.id == track.id
                )
            })
        return options
    }

    /// Resolves a `PlayerPickerOption.id` produced by `captionPickerOptions()`.
    func captionTrack(withOptionID id: String) -> CaptionTrack? {
        guard id.hasPrefix("cap-") else { return nil }
        let trackID = String(id.dropFirst(4))
        return availableCaptions.first(where: { $0.id == trackID })
    }

    func audioTrackPickerOptions() -> [PlayerPickerOption] {
        if availableAudioTracks.isEmpty {
            return [
                PlayerPickerOption(
                    id: "audio-refresh",
                    title: "Reload audio tracks",
                    subtitle: "No tracks yet — the embed has not exposed alternate audio tracks.",
                    isSelected: false
                )
            ]
        }
        return availableAudioTracks.map { track in
            PlayerPickerOption(
                id: "audio-\(track.index)",
                title: track.name,
                subtitle: audioPickerSubtitle(track),
                isSelected: selectedAudioTrack?.index == track.index
            )
        }
    }

    private func audioPickerSubtitle(_ track: TOSAudioOption) -> String? {
        if track.isOriginal { return "Original" }
        if !track.languageCode.isEmpty { return track.languageCode.uppercased() }
        if track.name.hasPrefix("Audio ") { return track.debugIdentifier }
        return nil
    }

    // MARK: Saved preferences

    private func applySavedMediaPreferences() async {
        if let maxHeight = settings.preferredQuality.maxHeight,
            let bestID = TOSPlayerTransportSupport.bestQualityID(
                forMaxHeight: maxHeight, in: availableQualities),
            bestID != actualQuality?.id
        {
            mediaLog.notice(
                "[mediaOptions] applying preferred quality \(bestID, privacy: .public) (cap=\(maxHeight, privacy: .public))"
            )
            await selectQuality(bestID)
        }

        if let code = settings.preferredCaptionLanguage, !code.isEmpty {
            await fetchNativeCaptionTracks()
            if let match = matchCaption(code) { selectNativeCaption(match) }
        }

        if let code = settings.preferredAudioLanguage, !code.isEmpty,
            let index = TOSPlayerTransportSupport.matchLanguage(
                code, in: availableAudioTracks.map { ($0.languageCode, $0.index) })
        {
            await selectAudioTrack(index: index)
        }
    }

    // MARK: Bridge helpers

    private func refreshAfterSelection() async {
        try? await Task.sleep(for: .milliseconds(500))
        await refreshMediaOptions()
        try? await Task.sleep(for: .milliseconds(1200))
        await refreshMediaOptions()
    }

    /// `JSONSerialization`/WKWebView hand back non-Sendable `[String: Any]`.
    /// The box is `@unchecked Sendable` because the dictionary is created on
    /// the web view's main-thread callback and only read back on the main
    /// actor; it is never mutated after the continuation resumes.
    private struct MediaOptionsJSON: @unchecked Sendable {
        let value: [String: Any]?
    }

    private func evalMediaOptionJSON(_ label: String, _ js: String) async -> [String: Any]? {
        let boxed: MediaOptionsJSON = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js, in: embedFrameInfo, in: .page) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: MediaOptionsJSON(value: value as? [String: Any]))
                case .failure(let error):
                    mediaLog.notice(
                        "[mediaOptions] \(label, privacy: .public) error: \(String(describing: error), privacy: .public)"
                    )
                    continuation.resume(returning: MediaOptionsJSON(value: nil))
                }
            }
        }
        return boxed.value
    }

    // MARK: Parsers

    private func parseQualities(_ json: [String: Any]) -> [TOSQualityOption] {
        (json["qualities"] as? [[String: Any]] ?? []).compactMap { dict in
            guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
            let label = dict["label"] as? String ?? TOSPlayerTransportSupport.prettyQuality(id)
            let height = (dict["height"] as? NSNumber)?.intValue ?? (dict["height"] as? Int) ?? 0
            return TOSQualityOption(id: id, label: label, height: height)
        }
    }

    private func parseAudioTracks(_ json: [String: Any]) -> [TOSAudioOption] {
        (json["audioTracks"] as? [[String: Any]] ?? []).compactMap { dict in
            guard let index = (dict["index"] as? NSNumber)?.intValue ?? (dict["index"] as? Int) else {
                return nil
            }
            let rawID = dict["id"] as? String ?? "\(index)"
            let providedLanguage = (dict["languageCode"] as? String) ?? ""
            // The embed often omits `languageCode`, but its track id is usually
            // the "langcode.number" form ("en.4", "de-DE.2"). Derive the code so
            // language matching (saved preference) and the pill label work.
            let languageCode =
                providedLanguage.isEmpty
                ? (TOSPlayerTransportSupport.audioLanguageCode(provided: "", identifier: rawID) ?? "")
                : providedLanguage
            let providedName = (dict["name"] as? String) ?? ""
            let name = TOSPlayerTransportSupport.audioTrackDisplayName(
                provided: providedName,
                languageCode: languageCode,
                identifier: rawID,
                index: index
            )
            return TOSAudioOption(
                index: index,
                id: "audio-\(index)-\(rawID)",
                name: name,
                languageCode: languageCode,
                isOriginal: dict["isOriginal"] as? Bool ?? false,
                debugIdentifier: rawID
            )
        }
    }

}
#endif
