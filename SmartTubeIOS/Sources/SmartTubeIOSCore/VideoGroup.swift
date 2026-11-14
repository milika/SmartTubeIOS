import Foundation

// MARK: - VideoGroup

/// A named collection of videos that maps to an Android `VideoGroup`.
public struct VideoGroup: Identifiable, Sendable {
    public let id: UUID
    public var title: String?
    public var videos: [Video]
    public var nextPageToken: String?
    public var action: Action
    /// How this group should be laid out in the UI.
    /// `.row` renders as a horizontal scrolling shelf (home feed rows);
    /// `.grid` renders as the default adaptive vertical grid.
    public var layout: Layout

    public enum Action: Sendable {
        case append
        case replace
        case remove
        case prepend
    }

    public enum Layout: Sendable {
        case grid
        case row
    }

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        videos: [Video] = [],
        nextPageToken: String? = nil,
        action: Action = .replace,
        layout: Layout = .grid
    ) {
        self.id = id
        self.title = title
        self.videos = videos
        self.nextPageToken = nextPageToken
        self.action = action
        self.layout = layout
    }
}

// MARK: - BrowseSection

/// Represents a tab/section shown in the main browse screen (mirrors Android `BrowseSection`).
public struct BrowseSection: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var type: SectionType

    public enum SectionType: String, CaseIterable, Codable, Sendable {
        case home = "home"
        case recommended = "recommended"
        case subscriptions = "subscriptions"
        case history = "history"
        case playlists = "playlists"
        case channels = "channels"
        case shorts = "shorts"
        case music = "music"
        case news = "news"
        case gaming = "gaming"
        case live = "live"
        case sports = "sports"
        case watchLater = "watchLater"
        case settings = "settings"

        /// Canonical display title — single source of truth used by defaultSections,
        /// allSections, and any code that needs a localised label for a section type.
        public var defaultTitle: String {
            switch self {
            case .home: return L10n.string("Home")
            case .recommended: return L10n.string("Recommended")
            case .subscriptions: return L10n.string("Subscriptions")
            case .history: return L10n.string("History")
            case .playlists: return L10n.string("Playlists")
            case .channels: return L10n.string("Channels")
            case .shorts: return L10n.string("Shorts")
            case .music: return L10n.string("Music")
            case .news: return L10n.string("News")
            case .gaming: return L10n.string("Gaming")
            case .live: return L10n.string("Live")
            case .sports: return L10n.string("Sports")
            case .watchLater: return L10n.string("Watch Later")
            case .settings: return L10n.string("Settings")
            }
        }
    }

    public init(id: String, title: String, type: SectionType) {
        self.id = id
        self.title = title
        self.type = type
    }

    /// Convenience: creates a section whose id and title are derived from the type.
    public init(type: SectionType) {
        self.id = type.rawValue
        self.title = type.defaultTitle
        self.type = type
    }

    public static let defaultSections: [BrowseSection] = [
        BrowseSection(type: .home),
        BrowseSection(type: .subscriptions),
        BrowseSection(type: .history),
        BrowseSection(type: .playlists),
        BrowseSection(type: .channels),
    ]

    /// All known sections including extended categories (music, gaming, etc.).
    public static let allSections: [BrowseSection] =
        defaultSections + [
            BrowseSection(type: .recommended),
            BrowseSection(type: .shorts),
            BrowseSection(type: .music),
            BrowseSection(type: .gaming),
            BrowseSection(type: .news),
            BrowseSection(type: .live),
            BrowseSection(type: .sports),
            BrowseSection(type: .watchLater),
        ]
}

// MARK: - SearchResult

public struct SearchResult: Identifiable, Sendable {
    public let id: UUID
    public var videos: [Video]
    public var query: String
    public var nextPageToken: String?

    public init(id: UUID = UUID(), videos: [Video] = [], query: String, nextPageToken: String? = nil) {
        self.id = id
        self.videos = videos
        self.query = query
        self.nextPageToken = nextPageToken
    }
}

// MARK: - Channel

public struct Channel: Identifiable, Hashable, Codable, Sendable {
    public let id: String  // channelId
    public var title: String
    public var description: String?
    public var thumbnailURL: URL?
    public var subscriberCount: String?
    public var isSubscribed: Bool

    public init(
        id: String,
        title: String,
        description: String? = nil,
        thumbnailURL: URL? = nil,
        subscriberCount: String? = nil,
        isSubscribed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.subscriberCount = subscriberCount
        self.isSubscribed = isSubscribed
    }
}

// MARK: - PlaylistInfo

public struct PlaylistInfo: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var videoCount: Int?
    public var thumbnailURL: URL?

    public init(id: String, title: String, videoCount: Int? = nil, thumbnailURL: URL? = nil) {
        self.id = id
        self.title = title
        self.videoCount = videoCount
        self.thumbnailURL = thumbnailURL
    }
}

// MARK: - VideoFormat

public struct VideoFormat: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var label: String
    public var width: Int
    public var height: Int
    public var fps: Int
    public var mimeType: String
    public var url: URL?
    public var bitrate: Int?

    public init(
        id: UUID = UUID(), label: String, width: Int, height: Int, fps: Int, mimeType: String, url: URL? = nil,
        bitrate: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.width = width
        self.height = height
        self.fps = fps
        self.mimeType = mimeType
        self.url = url
        self.bitrate = bitrate
    }

    public var qualityLabel: String { "\(height)p\(fps > 30 ? "\(fps)" : "")" }

    /// Short human-readable codec identifier derived from `mimeType`, e.g. "H.264", "VP9", "AV1".
    public var codecShortLabel: String {
        if mimeType.contains("avc1") { return "H.264" }
        if mimeType.contains("vp09") { return "VP9" }
        if mimeType.contains("av01") { return "AV1" }
        if mimeType.contains("hvc1") || mimeType.contains("hev1") { return "HEVC" }
        if mimeType.contains("mp4") { return "mp4" }
        if mimeType.contains("webm") { return "webm" }
        return ""
    }
}

// MARK: - SponsorSegment

/// A SponsorBlock segment within a video.
public struct SponsorSegment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var category: Category
    /// The SponsorBlock API's own segment identifier (its `"UUID"` field) — an
    /// arbitrary string, not a Swift `UUID`, so it's kept separate from `id` (which
    /// is just a local SwiftUI-identity token, `Identifiable`-generated per fetch).
    /// `nil` for segments not sourced from a live API response (e.g. UI-test-injected
    /// synthetic segments). Required by `SponsorBlockService.reportIncorrect(uuid:)`
    /// (#67) — voting on a segment needs the API's own identifier, not ours.
    public var apiUUID: String?

    public enum Category: String, Codable, CaseIterable, Sendable {
        case sponsor = "sponsor"
        case selfPromo = "selfpromo"
        case interaction = "interaction"
        case intro = "intro"
        case outro = "outro"
        case preview = "preview"
        case filler = "filler"
        case musicOfftopic = "music_offtopic"
        case poiHighlight = "poi_highlight"
    }

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, category: Category, apiUUID: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.category = category
        self.apiUUID = apiUUID
    }
}
