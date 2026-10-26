#if !os(tvOS)
import Foundation
import SmartTubeIOSCore

// MARK: - TOSPlayerTransportSupport
//
// Pure helpers behind the TOS transport/media-option logic, extracted so they
// can be unit-tested without instantiating a WKWebView-owning view model.
enum TOSPlayerTransportSupport {

    /// Decodes the `[[start, end], ...]` arrays sent by `stateDetectionJS`.
    /// `JSONSerialization` bridges the numbers to `NSNumber`, not `Double`.
    static func parseRanges(_ value: Any?) -> [ClosedRange<Double>] {
        guard let raw = value as? [[Any]] else { return [] }
        return raw.compactMap { pair in
            guard pair.count >= 2,
                let start = (pair[0] as? NSNumber)?.doubleValue,
                let end = (pair[1] as? NSNumber)?.doubleValue,
                start.isFinite, end.isFinite, end >= start
            else { return nil }
            return start...end
        }
    }

    /// Clamps a scrub target to the media window. A not-yet-known duration
    /// (0) still clamps the lower bound to 0.
    static func clampedScrubTime(_ time: Double, duration: Double) -> Double {
        if duration > 0 { return min(max(time, 0), duration) }
        return max(time, 0)
    }

    /// Maps YouTube's internal quality identifiers to the labels the picker
    /// and pill display.
    static func prettyQuality(_ id: String) -> String {
        switch id {
        case "highres": return "4320p"
        case "hd2160": return "2160p"
        case "hd1440": return "1440p"
        case "hd1080": return "1080p"
        case "hd720": return "720p"
        case "large": return "480p"
        case "medium": return "360p"
        case "small": return "240p"
        case "tiny": return "144p"
        default: return id
        }
    }

    /// Exact BCP-47 match first, then language-prefix match.
    static func matchLanguage(_ code: String, in tracks: [(String, Int)]) -> Int? {
        let base = code.components(separatedBy: "-").first ?? code
        if let exact = tracks.first(where: { $0.0 == code }) { return exact.1 }
        return tracks.first(where: { $0.0.hasPrefix(base) })?.1
    }

    /// Best-effort language code for an audio track. The TV embed sometimes
    /// returns only `id`/`audioTrackId` (e.g. "en", "en-US", "en.4") without
    /// `languageCode`/`displayName`, so derive it from the identifier.
    static func audioLanguageCode(provided: String, identifier: String) -> String? {
        let trimmed = provided.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.count <= 7, trimmed.rangeOfCharacter(from: .letters) != nil {
            return trimmed
        }
        let tokens = identifier.split(whereSeparator: { !($0.isLetter || $0 == "-") }).map(String.init)
        for token in tokens {
            if token.count == 2, token.allSatisfy({ $0.isLetter }) {
                return token.lowercased()
            }
            let parts = token.split(separator: "-")
            if parts.count == 2, parts[0].count == 2, parts[1].count == 2 {
                return token
            }
        }
        return nil
    }

    static func localizedLanguageName(_ code: String) -> String? {
        Locale.current.localizedString(forLanguageCode: code)
    }

    /// Human-readable audio-track label. Prefers the embed's own name, then a
    /// localized language name derived from the track id, then "Audio N".
    static func audioTrackDisplayName(
        provided: String, languageCode: String, identifier: String, index: Int
    ) -> String {
        let trimmed = provided.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != identifier, !trimmed.lowercased().hasPrefix("audio ") {
            if trimmed.count <= 7, let localized = localizedLanguageName(trimmed),
                trimmed.rangeOfCharacter(from: .letters) != nil
            {
                return localized
            }
            return trimmed
        }
        if let code = audioLanguageCode(provided: languageCode, identifier: identifier),
            let localized = localizedLanguageName(code)
        {
            return localized
        }
        return "Audio \(index + 1)"
    }

    /// Highest available quality at or below `maxHeight`, falling back to the
    /// lowest available level when every option exceeds the cap.
    static func bestQualityID(forMaxHeight maxHeight: Int, in qualities: [TOSQualityOption]) -> String? {
        let candidates = qualities.filter { $0.height > 0 }
        guard !candidates.isEmpty else { return nil }
        let atOrBelow = candidates.filter { $0.height <= maxHeight }.max(by: { $0.height < $1.height })
        return (atOrBelow ?? candidates.min(by: { $0.height < $1.height }))?.id
    }

    // MARK: Chapter navigation

    /// Start time of the first chapter strictly after `time`, or nil when the
    /// playhead is already in (or past) the last chapter.
    static func nextChapterStart(in chapters: [Chapter], after time: Double) -> Double? {
        chapters.first(where: { $0.startTime > time })?.startTime
    }

    /// Target of the "previous chapter" action, mirroring the direct player:
    /// when more than 3 s into the current chapter, restart that chapter;
    /// otherwise jump to the start of the previous one (nil when already in the
    /// first chapter within its first 3 s).
    static func previousChapterStart(in chapters: [Chapter], currentTime: Double) -> Double? {
        guard !chapters.isEmpty else { return nil }
        guard let current = chapters.last(where: { $0.startTime <= currentTime }) else { return nil }
        if currentTime - current.startTime > 3 { return current.startTime }
        return chapters.last(where: { $0.startTime < current.startTime })?.startTime
    }

    // MARK: Playlist gating

    /// Whether the video's previous/next buttons can navigate the active queue.
    /// Only videos that came from the Current Queue (a YouTube playlist, search
    /// "play all", or the Library queue) carry the synthetic queue `playlistId`;
    /// a queue of one item has nowhere to go, so both buttons stay disabled.
    static func canNavigatePlaylist(
        playlistId: String?, queuePlaylistID: String, queueCount: Int
    ) -> Bool {
        playlistId == queuePlaylistID && queueCount > 1
    }
}
#endif
