import Foundation

// MARK: - ShortDescription

/// What the official app's Shorts "Description" sheet shows: title, channel, the
/// Likes/Views/date tiles and the description text. Parsed from the WEB client's
/// `reel/reel_item_watch` → `engagementPanels[].structuredDescriptionContentRenderer`.
public struct ShortDescription: Sendable, Equatable {
    /// One stat tile ("88K" over "Likes"). Both strings come pre-formatted and
    /// localised by YouTube.
    public struct Factoid: Sendable, Equatable, Hashable {
        public let value: String
        public let label: String
        public let accessibilityText: String?

        public init(value: String, label: String, accessibilityText: String? = nil) {
            self.value = value
            self.label = label
            self.accessibilityText = accessibilityText
        }
    }

    public let videoId: String
    public var title: String
    public var channelTitle: String
    public var channelId: String?
    public var channelAvatarURL: URL?
    /// Likes, Views, upload date — in YouTube's order.
    public var factoids: [Factoid]
    public var descriptionText: String

    public init(
        videoId: String,
        title: String,
        channelTitle: String,
        channelId: String? = nil,
        channelAvatarURL: URL? = nil,
        factoids: [Factoid] = [],
        descriptionText: String = ""
    ) {
        self.videoId = videoId
        self.title = title
        self.channelTitle = channelTitle
        self.channelId = channelId
        self.channelAvatarURL = channelAvatarURL
        self.factoids = factoids
        self.descriptionText = descriptionText
    }
}

// MARK: - Parser

public enum ShortsDescriptionParser {

    /// Parses a WEB `reel/reel_item_watch` response. Nil when it has no structured
    /// description panel.
    public static func parse(_ json: [String: Any], videoId: String) -> ShortDescription? {
        guard let items = structuredDescriptionItems(in: json) else { return nil }
        var result = ShortDescription(videoId: videoId, title: "", channelTitle: "")
        var foundHeader = false
        for item in items {
            if let header = item["videoDescriptionHeaderRenderer"] as? [String: Any] {
                foundHeader = true
                result.title = text(header["title"]) ?? ""
                result.channelTitle = text(header["channel"]) ?? ""
                result.channelId =
                    ((header["channelNavigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?[
                        "browseId"] as? String
                result.channelAvatarURL = largestThumbnail(header["channelThumbnail"])
                result.factoids = (header["factoid"] as? [[String: Any]] ?? []).compactMap(factoid)
            } else if let body = item["expandableVideoDescriptionBodyRenderer"] as? [String: Any] {
                result.descriptionText =
                    text(body["descriptionBodyText"]) ?? text(body["attributedDescriptionBodyText"]) ?? ""
            }
        }
        return foundHeader ? result : nil
    }

    // MARK: Private

    private static func structuredDescriptionItems(in json: [String: Any]) -> [[String: Any]]? {
        let panels = json["engagementPanels"] as? [[String: Any]] ?? []
        for panel in panels {
            let content =
                (panel["engagementPanelSectionListRenderer"] as? [String: Any])?["content"] as? [String: Any]
            if let renderer = content?["structuredDescriptionContentRenderer"] as? [String: Any] {
                return renderer["items"] as? [[String: Any]]
            }
        }
        return nil
    }

    /// `factoidRenderer`, or the view-count variant that wraps one.
    private static func factoid(_ item: [String: Any]) -> ShortDescription.Factoid? {
        let renderer =
            item["factoidRenderer"] as? [String: Any]
            ?? ((item["viewCountFactoidRenderer"] as? [String: Any])?["factoid"] as? [String: Any])?[
                "factoidRenderer"] as? [String: Any]
        guard let renderer, let value = text(renderer["value"]), !value.isEmpty else { return nil }
        return ShortDescription.Factoid(
            value: value,
            label: text(renderer["label"]) ?? "",
            accessibilityText: renderer["accessibilityText"] as? String)
    }

    /// `{simpleText}`, `{runs: [{text}]}` or `{content}` (view-model text).
    static func text(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return value as? String }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return dict["content"] as? String
    }

    private static func largestThumbnail(_ value: Any?) -> URL? {
        let thumbnails = (value as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let best = thumbnails.max { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        guard var url = best?["url"] as? String else { return nil }
        if url.hasPrefix("//") { url = "https:" + url }
        return URL(string: url)
    }
}
