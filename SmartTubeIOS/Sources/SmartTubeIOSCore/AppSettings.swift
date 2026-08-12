import Foundation
import SwiftUI

// MARK: - AppSettings

/// Persisted app-wide preferences (mirrors Android `PlayerData`, `MainUIData`, `GeneralData`, etc.).
public struct AppSettings: Codable {
    // MARK: Player
    public var preferredQuality: VideoQuality
    public var playbackSpeed: Double
    public var autoplayEnabled: Bool
    public var subtitlesLanguage: String?
    public var backgroundPlaybackEnabled: Bool
    /// Player implementation used for regular videos on iOS.
    /// The YouTube embed is the compatibility-first default; the native player
    /// supports reliable background playback and the full set of native controls.
    public var iOSPlayer: IOSPlayer
    /// When `true`, the player automatically rotates to landscape when a video starts on iPhone.
    public var landscapeAlwaysPlay: Bool
    /// When `true`, Picture-in-Picture is available and the PiP button is shown in the player.
    public var pipEnabled: Bool
    /// When `true` (default), pressing back or swiping down minimizes the player to the
    /// in-app mini-player bar instead of stopping playback. When `false`, the player is
    /// dismissed and playback stops — mirrors the behaviour of a standalone player app.
    public var miniPlayerEnabled: Bool
    /// Seconds to seek backward (configurable; default 10 mirrors Android's default).
    public var seekBackSeconds: Int
    /// Seconds to seek forward (configurable; default 30 mirrors Android's default).
    public var seekForwardSeconds: Int
    /// Seconds before the player controls auto-hide after the last interaction.
    /// Mirrors Android's `PlayerData.controlsHideTimeoutMs`. Default: 4.
    public var controlsHideTimeout: Int

    /// Whether the video should fill the screen (cropping sides) or fit within bounds.
    public enum VideoGravityMode: String, Codable, CaseIterable, Sendable {
        case fit  = "fit"   // resizeAspect — letterbox/pillarbox
        case fill = "fill"  // resizeAspectFill — crops to fill
    }
    public var videoGravityMode: VideoGravityMode

    /// When `true`, the current video replays from the start instead of advancing.
    public var loopEnabled: Bool
    /// When `true`, autoplay picks a random video from the related-videos list.
    public var shuffleEnabled: Bool
    /// When `true`, playing from the Current Queue picks a random remaining video instead of the next sequential one.
    /// Independent from `shuffleEnabled` (which shuffles YouTube recommendations after non-queue playback).
    public var queueShuffleEnabled: Bool

    // MARK: UI
    public var defaultSection: String
    public var compactThumbnails: Bool
    public var hideShorts: Bool
    public var hideLiveShorts: Bool
    public var hideVideoPremieres: Bool
    /// When `true` (default), a per-device `visitorData` token is included in home-feed
    /// requests so YouTube tailors recommendations to this device.
    /// When `false`, the token is cleared and YouTube returns its default shared feed.
    public var perDeviceRecommendationsEnabled: Bool
    public var themeName: ThemeName
    /// Ordered list of section types visible in the sidebar/tab bar.
    /// When empty, all default sections are shown.
    public var enabledSections: [BrowseSection.SectionType]

    // MARK: General

    /// Controls whether watch history is recorded locally and fetched from YouTube.
    /// Mirrors Android's `GeneralData.historyEnabled`.
    public enum HistoryState: String, Codable, CaseIterable, Sendable {
        /// Default — history is fetched from YouTube and local positions are saved.
        case enabled  = "enabled"
        /// History section shows nothing and local watch positions are not saved.
        case disabled = "disabled"
    }
    public var historyState: HistoryState

    // MARK: SponsorBlock

    /// Per-segment action that controls how each SponsorBlock category is handled.
    /// Mirrors Android's per-category action setting in `SponsorBlockData`.
    public enum SponsorBlockAction: String, Codable, CaseIterable, Sendable {
        /// Automatically skip the segment without user interaction.
        case skip      = "skip"
        /// Show a dismissible toast and let the user manually skip.
        case showToast = "showToast"
        /// Take no action — segment plays through normally.
        case nothing   = "nothing"
    }

    public var sponsorBlockEnabled: Bool
    /// Per-category action. Categories absent from this dict are treated as `.nothing`.
    public var sponsorBlockActions: [SponsorSegment.Category: SponsorBlockAction]
    /// Minimum segment length (seconds). Segments shorter than this value are ignored.
    /// 0 means "accept all" (no filtering). Mirrors Android's `SponsorBlockData.minSegmentDuration`.
    public var sponsorBlockMinSegmentDuration: Double
    /// Channels where SponsorBlock is disabled. Key = channelId, value = display title.
    /// Mirrors Android's `SponsorBlockData.excludedChannels`.
    public var sponsorBlockExcludedChannels: [String: String]
    /// Channels hidden from the feed via "Don't Recommend Channel". Key = channelId, value = channel title.
    /// Persists across sessions and syncs via iCloud when `iCloudSyncEnabled` is true.
    public var blockedChannels: [String: String]

    /// Convenience: the set of categories whose action is not `.nothing`.
    /// Passed to `SponsorBlockService.fetchSegments` so we only fetch relevant segments.
    public var activeSponsorCategories: Set<SponsorSegment.Category> {
        Set(sponsorBlockActions.compactMap { $0.value != .nothing ? $0.key : nil })
    }

    /// Returns the action for a given category (`.nothing` if not configured).
    public func sponsorAction(for category: SponsorSegment.Category) -> SponsorBlockAction {
        sponsorBlockActions[category] ?? .nothing
    }

    // MARK: Audio
    /// BCP 47 language code of the user's preferred audio track (e.g. "es", "fr", "pt-BR").
    /// `nil` means use the HLS default. Set implicitly when the user picks a track in the player.
    public var preferredAudioLanguage: String?

    /// BCP 47 language code of the user's last selected caption track (e.g. "en", "es").
    /// `nil` means captions are off. Set implicitly when the user picks a caption track in the player.
    /// Applied automatically to each new video on load.
    public var preferredCaptionLanguage: String?

    // MARK: DeArrow
    public var deArrowEnabled: Bool

    // MARK: Network
    /// Optional URL of a self-hosted poToken microservice (e.g. youtube-trusted-session-generator).
    /// When set, `ServerPoTokenProvider` is wired up to `InnerTubeAPI` so poToken is injected
    /// into every `/player` request. Nil by default — no token is sent until the user configures
    /// a server URL (see docs/potoken.md §Step 5).
    public var poTokenServiceURL: URL?

    // MARK: Audio-only mode
    /// When `true`, videos load only the audio stream and display the thumbnail.
    /// ~90% data reduction vs 1080p. Live streams are excluded automatically.
    public var audioOnlyMode: Bool

    // MARK: Codec preference
    /// When `true`, restricts adaptive video format selection to H.264 (`avc1`) only.
    /// Mirrors Android's `limitVideoCodec("avc1")` opt-in for devices with VP9/AV1
    /// decoder issues. Defaults to `false` (all codecs allowed).
    public var preferH264: Bool

    // MARK: iCloud sync
    /// When `true`, local user data (subscriptions, RSS feeds, video state, queue) is
    /// synced to iCloud via `NSUbiquitousKeyValueStore`. Defaults to `false` (opt-in).
    public var iCloudSyncEnabled: Bool

    // MARK: Experimental (macOS / iOS)
    /// When `true` on macOS, the YouTube IFrame-based TOS-compliant player is used
    /// instead of the AVPlayer-based pipeline. Ads will play. Quality control is unavailable.
    /// Opt-in experiment — has no effect on tvOS.
    public var useTOSPlayerOnMac: Bool

    // MARK: Schema version
    /// Persisted schema version. Starts at 1 for newly stored settings.
    /// Old JSON lacking this key decodes as 0, signalling a pre-migration store.
    /// Increment when a breaking schema change requires a migration step.
    public var settingsVersion: Int

    // MARK: Types

    /// Canonical ordered list of selectable playback speeds — single source of truth.
    public static let availableSpeeds: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// Canonical ordered list of selectable seek-interval values (seconds) — used by Stepper on iOS and Picker on tvOS.
    public static let availableSeekOptions: [Int] = [5, 10, 15, 20, 30, 45, 60]

    public enum IOSPlayer: String, Codable, CaseIterable, Sendable {
        case youtubeEmbed = "youtubeEmbed"
        case native = "native"
    }

    public enum VideoQuality: String, Codable, CaseIterable, Sendable {
        case auto  = "auto"
        case q2160 = "2160p"
        case q1440 = "1440p"
        case q1080 = "1080p"
        case q720  = "720p"
        case q480  = "480p"
        case q360  = "360p"
        case q240  = "240p"
        case q144  = "144p"

        /// The maximum pixel height corresponding to this quality level.
        /// Returns `nil` for `.auto` (no cap).
        public var maxHeight: Int? {
            switch self {
            case .auto:  return nil
            case .q144:  return 144
            case .q240:  return 240
            case .q360:  return 360
            case .q480:  return 480
            case .q720:  return 720
            case .q1080: return 1080
            case .q1440: return 1440
            case .q2160: return 2160
            }
        }

        /// Returns the `VideoQuality` matching an exact pixel height, or `nil` if none matches.
        public static func from(height: Int) -> VideoQuality? {
            allCases.first { $0.maxHeight == height }
        }
    }

    public enum ThemeName: String, Codable, CaseIterable {
        case system = "System"
        case dark   = "Dark"
        case light  = "Light"

        public var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .dark:   return .dark
            case .light:  return .light
            }
        }
    }

    // MARK: Defaults

    public init() {
        preferredQuality     = .auto
        playbackSpeed        = 1.0
        autoplayEnabled      = true
        subtitlesLanguage    = nil
        backgroundPlaybackEnabled = false
        iOSPlayer            = .youtubeEmbed
        landscapeAlwaysPlay  = false
        pipEnabled           = true
        miniPlayerEnabled    = true
        seekBackSeconds      = 10
        seekForwardSeconds   = 30
        controlsHideTimeout  = 4
        videoGravityMode     = .fit
        loopEnabled          = false
        shuffleEnabled       = false
        queueShuffleEnabled  = false
        defaultSection       = BrowseSection.SectionType.home.rawValue
        compactThumbnails    = false
        hideShorts           = false
        hideLiveShorts       = false
        hideVideoPremieres   = false
        perDeviceRecommendationsEnabled = true
        themeName            = .system
        enabledSections      = BrowseSection.defaultSections.map(\.type)
        historyState         = .enabled
        sponsorBlockEnabled  = true
        // Default actions mirror Android's SponsorBlockData defaults:
        //   sponsor / selfPromo → auto-skip; interaction / intro / preview / musicOfftopic → show toast; others → nothing
        sponsorBlockActions = [
            .sponsor:       .skip,
            .selfPromo:     .skip,
            .interaction:   .showToast,
            .intro:         .showToast,
            .outro:         .nothing,
            .preview:       .showToast,
            .filler:        .nothing,
            .musicOfftopic: .showToast,
            .poiHighlight:  .nothing,
        ]
        sponsorBlockMinSegmentDuration = 0
        sponsorBlockExcludedChannels   = [:]
        blockedChannels                = [:]
        preferredAudioLanguage = nil
        preferredCaptionLanguage = nil
        deArrowEnabled       = false
        poTokenServiceURL    = nil
        audioOnlyMode        = false
        preferH264           = false
        iCloudSyncEnabled    = false
        #if os(macOS)
        useTOSPlayerOnMac    = true
        #else
        useTOSPlayerOnMac    = false
        #endif
        settingsVersion      = 1
    }
}

// MARK: - Forward-compatible Codable

// The synthesized init(from:) requires ALL non-Optional properties to be present in the
// stored JSON. If any property is added, renamed, or type-changed in a new app version,
// the decode throws and SettingsStore silently resets all settings to defaults (bug #181).
//
// This custom init(from:) uses decodeIfPresent with per-field defaults so that:
//  - New fields get their default value when absent from old JSON (forward compatibility).
//  - Renamed/type-changed fields fall back to defaults rather than wiping everything.
//  - settingsVersion = 0 in old JSON signals a pre-migration store for future use.

private extension KeyedDecodingContainer {
    /// Decodes T if the key exists and the value is the right type; returns `defaultValue`
    /// for absent keys, null values, or type mismatches — never throws.
    func safeDecode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}

extension AppSettings {
    // Explicit CodingKeys keep JSON key names stable even if Swift property names change.
    enum CodingKeys: String, CodingKey {
        case settingsVersion
        case preferredQuality
        case playbackSpeed
        case autoplayEnabled
        case subtitlesLanguage
        case backgroundPlaybackEnabled
        case iOSPlayer
        case landscapeAlwaysPlay
        case pipEnabled
        case miniPlayerEnabled
        case seekBackSeconds
        case seekForwardSeconds
        case controlsHideTimeout
        case videoGravityMode
        case loopEnabled
        case shuffleEnabled
        case queueShuffleEnabled
        case defaultSection
        case compactThumbnails
        case hideShorts
        case hideLiveShorts
        case hideVideoPremieres
        case perDeviceRecommendationsEnabled
        case themeName
        case enabledSections
        case historyState
        case sponsorBlockEnabled
        case sponsorBlockActions
        case sponsorBlockMinSegmentDuration
        case sponsorBlockExcludedChannels
        case blockedChannels
        case preferredAudioLanguage
        case preferredCaptionLanguage
        case deArrowEnabled
        case poTokenServiceURL
        case audioOnlyMode
        case preferH264
        case iCloudSyncEnabled
        case useTOSPlayerOnMac
    }

    public init(from decoder: Decoder) throws {
        let d = AppSettings()   // defaults for any missing/mismatched field
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settingsVersion              = c.safeDecode(Int.self,               forKey: .settingsVersion,              default: 0)
        preferredQuality             = c.safeDecode(VideoQuality.self,      forKey: .preferredQuality,             default: d.preferredQuality)
        playbackSpeed                = c.safeDecode(Double.self,            forKey: .playbackSpeed,                default: d.playbackSpeed)
        autoplayEnabled              = c.safeDecode(Bool.self,              forKey: .autoplayEnabled,              default: d.autoplayEnabled)
        subtitlesLanguage            = c.safeDecode(String?.self,           forKey: .subtitlesLanguage,            default: d.subtitlesLanguage)
        backgroundPlaybackEnabled    = c.safeDecode(Bool.self,              forKey: .backgroundPlaybackEnabled,    default: d.backgroundPlaybackEnabled)
        iOSPlayer                    = c.safeDecode(IOSPlayer.self,          forKey: .iOSPlayer,                    default: d.iOSPlayer)
        landscapeAlwaysPlay          = c.safeDecode(Bool.self,              forKey: .landscapeAlwaysPlay,          default: d.landscapeAlwaysPlay)
        pipEnabled                   = c.safeDecode(Bool.self,              forKey: .pipEnabled,                   default: d.pipEnabled)
        miniPlayerEnabled            = c.safeDecode(Bool.self,              forKey: .miniPlayerEnabled,            default: d.miniPlayerEnabled)
        seekBackSeconds              = c.safeDecode(Int.self,               forKey: .seekBackSeconds,              default: d.seekBackSeconds)
        seekForwardSeconds           = c.safeDecode(Int.self,               forKey: .seekForwardSeconds,           default: d.seekForwardSeconds)
        controlsHideTimeout          = c.safeDecode(Int.self,               forKey: .controlsHideTimeout,         default: d.controlsHideTimeout)
        videoGravityMode             = c.safeDecode(VideoGravityMode.self,  forKey: .videoGravityMode,             default: d.videoGravityMode)
        loopEnabled                  = c.safeDecode(Bool.self,              forKey: .loopEnabled,                  default: d.loopEnabled)
        shuffleEnabled               = c.safeDecode(Bool.self,              forKey: .shuffleEnabled,               default: d.shuffleEnabled)
        queueShuffleEnabled          = c.safeDecode(Bool.self,              forKey: .queueShuffleEnabled,          default: d.queueShuffleEnabled)
        defaultSection               = c.safeDecode(String.self,            forKey: .defaultSection,               default: d.defaultSection)
        compactThumbnails            = c.safeDecode(Bool.self,              forKey: .compactThumbnails,            default: d.compactThumbnails)
        hideShorts                   = c.safeDecode(Bool.self,              forKey: .hideShorts,                   default: d.hideShorts)
        hideLiveShorts               = c.safeDecode(Bool.self,              forKey: .hideLiveShorts,               default: d.hideLiveShorts)
        hideVideoPremieres           = c.safeDecode(Bool.self,              forKey: .hideVideoPremieres,           default: d.hideVideoPremieres)
        perDeviceRecommendationsEnabled = c.safeDecode(Bool.self,           forKey: .perDeviceRecommendationsEnabled, default: d.perDeviceRecommendationsEnabled)
        themeName                    = c.safeDecode(ThemeName.self,         forKey: .themeName,                    default: d.themeName)
        enabledSections              = c.safeDecode([BrowseSection.SectionType].self, forKey: .enabledSections,   default: d.enabledSections)
        historyState                 = c.safeDecode(HistoryState.self,      forKey: .historyState,                 default: d.historyState)
        sponsorBlockEnabled          = c.safeDecode(Bool.self,              forKey: .sponsorBlockEnabled,          default: d.sponsorBlockEnabled)
        sponsorBlockActions          = c.safeDecode([SponsorSegment.Category: SponsorBlockAction].self, forKey: .sponsorBlockActions, default: d.sponsorBlockActions)
        sponsorBlockMinSegmentDuration = c.safeDecode(Double.self,          forKey: .sponsorBlockMinSegmentDuration, default: d.sponsorBlockMinSegmentDuration)
        sponsorBlockExcludedChannels = c.safeDecode([String: String].self,  forKey: .sponsorBlockExcludedChannels, default: d.sponsorBlockExcludedChannels)
        blockedChannels              = c.safeDecode([String: String].self,  forKey: .blockedChannels,              default: d.blockedChannels)
        preferredAudioLanguage       = c.safeDecode(String?.self,           forKey: .preferredAudioLanguage,       default: d.preferredAudioLanguage)
        preferredCaptionLanguage     = c.safeDecode(String?.self,           forKey: .preferredCaptionLanguage,     default: d.preferredCaptionLanguage)
        deArrowEnabled               = c.safeDecode(Bool.self,              forKey: .deArrowEnabled,               default: d.deArrowEnabled)
        poTokenServiceURL            = c.safeDecode(URL?.self,              forKey: .poTokenServiceURL,            default: d.poTokenServiceURL)
        audioOnlyMode                = c.safeDecode(Bool.self,              forKey: .audioOnlyMode,                default: d.audioOnlyMode)
        preferH264                   = c.safeDecode(Bool.self,              forKey: .preferH264,                   default: d.preferH264)
        iCloudSyncEnabled            = c.safeDecode(Bool.self,              forKey: .iCloudSyncEnabled,            default: d.iCloudSyncEnabled)
        useTOSPlayerOnMac            = c.safeDecode(Bool.self,              forKey: .useTOSPlayerOnMac,            default: d.useTOSPlayerOnMac)
    }
}
