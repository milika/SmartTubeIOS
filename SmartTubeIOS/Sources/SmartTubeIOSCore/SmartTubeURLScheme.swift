import Foundation

// MARK: - SmartTubeURLScheme (#84)
//
// Parses the app's own `smarttube://` URL scheme, used by the Share Extension
// (`smarttube://video/VIDEO_ID`) and by hand-built links from Shortcuts/browser address
// bars using YouTube's own watch-URL query param shape (`smarttube://watch?v=VIDEO_ID`).
// Pulled out of AppEntry.swift's handleOpenURL (a different module, not covered by
// `swift test`) so this parsing has real unit coverage.

public enum SmartTubeURLScheme {
    /// Returns the video ID encoded in `url`, or `nil` if `url` isn't a recognized
    /// `smarttube://` video link.
    public static func videoID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "smarttube" else { return nil }
        let videoID: String?
        switch url.host?.lowercased() {
        case "video":
            videoID = url.pathComponents.filter { $0 != "/" }.first
        case "watch":
            videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
        default:
            videoID = nil
        }
        guard let videoID, !videoID.isEmpty else { return nil }
        return videoID
    }
}

// MARK: - Routes (App Intents, Spotlight)
//
// Everything Siri / Shortcuts / Spotlight can ask the app to do, as `smarttube://` URLs so
// the app has a single entry point (AppEntry.handleOpenURL) for all of them:
//   smarttube://video/ID, smarttube://watch?v=ID   play a video
//   smarttube://search?q=TEXT                      search
//   smarttube://section/TYPE                       open a Home section (BrowseSection.SectionType)
//   smarttube://play/watchlater                    play the first Watch Later video
//   smarttube://play/continue                      resume the last watched video
//   smarttube://channel/ID                         open a channel

public enum SmartTubeRoute: Equatable, Sendable {
    case video(id: String)
    case search(query: String)
    case section(BrowseSection.SectionType)
    case playWatchLater
    case continueWatching
    case channel(id: String)

    public init?(url: URL) {
        if let id = SmartTubeURLScheme.videoID(from: url) {
            self = .video(id: id)
            return
        }
        guard url.scheme?.lowercased() == "smarttube" else { return nil }
        let first = url.pathComponents.first { $0 != "/" }
        switch url.host?.lowercased() {
        case "search":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let query, !query.isEmpty else { return nil }
            self = .search(query: query)
        case "section":
            guard let raw = first, let type = BrowseSection.SectionType(rawValue: raw) else { return nil }
            self = .section(type)
        case "play":
            switch first?.lowercased() {
            case "watchlater": self = .playWatchLater
            case "continue": self = .continueWatching
            default: return nil
            }
        case "channel":
            guard let id = first, !id.isEmpty else { return nil }
            self = .channel(id: id)
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "smarttube"
        switch self {
        case .video(let id):
            components.host = "video"
            components.path = "/\(id)"
        case .search(let query):
            components.host = "search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .section(let type):
            components.host = "section"
            components.path = "/\(type.rawValue)"
        case .playWatchLater:
            components.host = "play"
            components.path = "/watchlater"
        case .continueWatching:
            components.host = "play"
            components.path = "/continue"
        case .channel(let id):
            components.host = "channel"
            components.path = "/\(id)"
        }
        return components.url!
    }
}
