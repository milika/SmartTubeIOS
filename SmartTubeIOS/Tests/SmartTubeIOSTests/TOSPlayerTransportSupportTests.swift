#if !os(tvOS)
import Foundation
import Testing

@testable import SmartTubeIOS
import SmartTubeIOSCore

// MARK: - TOSPlayerTransportSupportTests
//
// Pure-logic coverage for the TOS native transport/media-option helpers. No
// WKWebView is involved, so these run in the SwiftPM test target.

@Suite("TOSPlayerTransportSupport.parseRanges")
struct TOSPlayerTransportParseRangesTests {

    @Test("decodes NSNumber pairs into closed ranges")
    func decodesNumberPairs() {
        let raw: [[Any]] = [[NSNumber(value: 0), NSNumber(value: 12.5)], [NSNumber(value: 30), NSNumber(value: 40)]]
        let ranges = TOSPlayerTransportSupport.parseRanges(raw)
        #expect(ranges.count == 2)
        #expect(ranges[0].lowerBound == 0)
        #expect(ranges[0].upperBound == 12.5)
        #expect(ranges[1].lowerBound == 30)
        #expect(ranges[1].upperBound == 40)
    }

    @Test("rejects non-finite, inverted and malformed entries")
    func rejectsInvalidEntries() {
        let raw: [[Any]] = [
            [NSNumber(value: Double.infinity), NSNumber(value: 10)],
            [NSNumber(value: 20), NSNumber(value: 10)],
            [NSNumber(value: 5)],
        ]
        #expect(TOSPlayerTransportSupport.parseRanges(raw).isEmpty)
    }

    @Test("non-array payload returns no ranges")
    func ignoresNonArray() {
        #expect(TOSPlayerTransportSupport.parseRanges("nope").isEmpty)
        #expect(TOSPlayerTransportSupport.parseRanges(nil).isEmpty)
    }
}

@Suite("TOSPlayerTransportSupport.clampedScrubTime")
struct TOSPlayerTransportClampTests {

    @Test("within the window is unchanged")
    func withinWindow() {
        #expect(TOSPlayerTransportSupport.clampedScrubTime(42, duration: 100) == 42)
    }

    @Test("above the window clamps to duration")
    func aboveWindow() {
        #expect(TOSPlayerTransportSupport.clampedScrubTime(140, duration: 100) == 100)
    }

    @Test("below zero clamps to zero")
    func belowZero() {
        #expect(TOSPlayerTransportSupport.clampedScrubTime(-5, duration: 100) == 0)
    }

    @Test("unknown duration still clamps the lower bound")
    func unknownDuration() {
        #expect(TOSPlayerTransportSupport.clampedScrubTime(-5, duration: 0) == 0)
        #expect(TOSPlayerTransportSupport.clampedScrubTime(30, duration: 0) == 30)
    }
}

@Suite("TOSPlayerTransportSupport quality + language helpers")
struct TOSPlayerTransportQualityTests {

    @Test("prettyQuality maps YouTube identifiers")
    func prettyQualityMapping() {
        #expect(TOSPlayerTransportSupport.prettyQuality("hd1080") == "1080p")
        #expect(TOSPlayerTransportSupport.prettyQuality("large") == "480p")
        #expect(TOSPlayerTransportSupport.prettyQuality("mystery") == "mystery")
    }

    @Test("bestQualityID picks the highest at or below the cap")
    func bestQualityAtOrBelow() {
        let qualities = [
            TOSQualityOption(id: "hd1080", label: "1080p", height: 1080),
            TOSQualityOption(id: "hd720", label: "720p", height: 720),
            TOSQualityOption(id: "medium", label: "360p", height: 360),
        ]
        #expect(TOSPlayerTransportSupport.bestQualityID(forMaxHeight: 720, in: qualities) == "hd720")
        #expect(TOSPlayerTransportSupport.bestQualityID(forMaxHeight: 1080, in: qualities) == "hd1080")
    }

    @Test("bestQualityID falls back to the lowest when every option exceeds the cap")
    func bestQualityFallback() {
        let qualities = [
            TOSQualityOption(id: "hd1080", label: "1080p", height: 1080),
            TOSQualityOption(id: "hd720", label: "720p", height: 720),
        ]
        #expect(TOSPlayerTransportSupport.bestQualityID(forMaxHeight: 400, in: qualities) == "hd720")
        #expect(TOSPlayerTransportSupport.bestQualityID(forMaxHeight: 400, in: []) == nil)
    }

    @Test("matchLanguage prefers an exact code, then a prefix")
    func languageMatching() {
        let tracks: [(String, Int)] = [("en-US", 0), ("es", 1), ("fr", 2)]
        #expect(TOSPlayerTransportSupport.matchLanguage("es", in: tracks) == 1)
        #expect(TOSPlayerTransportSupport.matchLanguage("en-GB", in: tracks) == 0)
        #expect(TOSPlayerTransportSupport.matchLanguage("de", in: tracks) == nil)
    }

    @Test("audio display name derives a language name from the track id")
    func audioDisplayNameFromTrackID() {
        let name = TOSPlayerTransportSupport.audioTrackDisplayName(
            provided: "", languageCode: "", identifier: "en.4", index: 0)
        if let localized = TOSPlayerTransportSupport.localizedLanguageName("en") {
            #expect(name == localized)
        } else {
            #expect(name == "Audio 1")
        }
    }

    @Test("audio display name falls back to Audio N for opaque ids")
    func audioDisplayNameFallback() {
        let name = TOSPlayerTransportSupport.audioTrackDisplayName(
            provided: "", languageCode: "", identifier: "opaque-content-id", index: 1)
        #expect(name == "Audio 2")
    }

    @Test("audio language code is derived from the langcode.number track id")
    func audioLanguageCodeFromLangcodeNumberID() {
        #expect(TOSPlayerTransportSupport.audioLanguageCode(provided: "", identifier: "en.4") == "en")
        #expect(TOSPlayerTransportSupport.audioLanguageCode(provided: "", identifier: "de-DE.2") == "de-DE")
        #expect(TOSPlayerTransportSupport.audioLanguageCode(provided: "", identifier: "opaque-content-id") == nil)
    }

    @Test("audio language code prefers an explicit provided code")
    func audioLanguageCodePrefersProvided() {
        #expect(TOSPlayerTransportSupport.audioLanguageCode(provided: "fr", identifier: "opaque") == "fr")
    }

    @Test("audio display name prefers the embed's localized name")
    func audioDisplayNamePrefersProvidedName() {
        #expect(
            TOSPlayerTransportSupport.audioTrackDisplayName(
                provided: "English original", languageCode: "en", identifier: "en.4", index: 0)
                == "English original")
        // A three-letter-plus localized name is passed through unchanged.
        #expect(
            TOSPlayerTransportSupport.audioTrackDisplayName(
                provided: "Deutsch", languageCode: "de", identifier: "de.2", index: 1)
                == "Deutsch")
    }
}

// MARK: - Chapter navigation

@Suite("TOSPlayerTransportSupport chapter navigation")
struct TOSPlayerTransportChapterTests {

    private let chapters = [
        Chapter(title: "Intro", startTime: 0),
        Chapter(title: "Main", startTime: 90),
        Chapter(title: "End", startTime: 300),
    ]

    @Test("next chapter start is the first chapter after the playhead")
    func nextChapter() {
        #expect(TOSPlayerTransportSupport.nextChapterStart(in: chapters, after: 0) == 90)
        #expect(TOSPlayerTransportSupport.nextChapterStart(in: chapters, after: 120) == 300)
        #expect(TOSPlayerTransportSupport.nextChapterStart(in: chapters, after: 300) == nil)
        #expect(TOSPlayerTransportSupport.nextChapterStart(in: [], after: 0) == nil)
    }

    @Test("previous chapter restarts the current one once >3s in")
    func previousChapterRestarts() {
        // 10s into the chapter starting at 0 → restart it.
        #expect(TOSPlayerTransportSupport.previousChapterStart(in: chapters, currentTime: 10) == 0)
        // 100s into the chapter starting at 90 → restart 90.
        #expect(TOSPlayerTransportSupport.previousChapterStart(in: chapters, currentTime: 100) == 90)
    }

    @Test("previous chapter jumps back within the first 3s of a chapter")
    func previousChapterJumpsBack() {
        // 1s into the chapter starting at 90 → previous chapter (0).
        #expect(TOSPlayerTransportSupport.previousChapterStart(in: chapters, currentTime: 91) == 0)
    }

    @Test("previous chapter is nil at the first chapter's start")
    func previousChapterAtStart() {
        #expect(TOSPlayerTransportSupport.previousChapterStart(in: chapters, currentTime: 1) == nil)
        #expect(TOSPlayerTransportSupport.previousChapterStart(in: [], currentTime: 5) == nil)
    }
}

// MARK: - Playlist gating

@Suite("TOSPlayerTransportSupport playlist gating")
struct TOSPlayerTransportPlaylistTests {

    @Test("non-playlist videos cannot navigate")
    func nonPlaylistDisabled() {
        #expect(
            TOSPlayerTransportSupport.canNavigatePlaylist(
                playlistId: nil, queuePlaylistID: "__queue__", queueCount: 5) == false)
        #expect(
            TOSPlayerTransportSupport.canNavigatePlaylist(
                playlistId: "PLother", queuePlaylistID: "__queue__", queueCount: 5) == false)
    }

    @Test("a one-item queue keeps both buttons disabled")
    func singleItemQueue() {
        #expect(
            TOSPlayerTransportSupport.canNavigatePlaylist(
                playlistId: "__queue__", queuePlaylistID: "__queue__", queueCount: 1) == false)
        #expect(
            TOSPlayerTransportSupport.canNavigatePlaylist(
                playlistId: "__queue__", queuePlaylistID: "__queue__", queueCount: 0) == false)
    }

    @Test("a multi-item queue enables navigation")
    func multiItemQueue() {
        #expect(
            TOSPlayerTransportSupport.canNavigatePlaylist(
                playlistId: "__queue__", queuePlaylistID: "__queue__", queueCount: 2) == true)
    }
}
#endif
