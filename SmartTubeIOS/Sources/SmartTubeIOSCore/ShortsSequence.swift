import Foundation

// MARK: - Shorts sequence (YouTube's own Shorts algorithm)
//
// The official apps page through Shorts with two InnerTube calls, both of which the
// TVHTML5 client on youtubei.googleapis.com supports — so they go through `postTV`
// (Bearer when signed in → personalised; API key when signed out → YouTube's
// non-personalised sequence):
//
//   reel/reel_item_watch      seedless start (`inputType: REEL_WATCH_INPUT_TYPE_SEEDLESS`)
//                             → first Short + `sequenceContinuation`;
//                             or per-Short overlay metadata (`playerRequest.videoId`).
//   reel/reel_watch_sequence  `sequenceParams` (first page) or `continuation` (next pages)
//                             → `entries[]` of reelWatchEndpoints + `continuation`.
//
// Gotcha: a TV `continuation` must be sent back as `continuation`. Sent as
// `sequenceParams` it is accepted but silently returns the first page again.
// See docs/superpowers/plans/2026-11-11-shorts-algorithm-feed-and-ui.md.

/// One page of Shorts from YouTube's Shorts sequence.
public struct ShortsFeedPage: Sendable, Equatable {
    public var videos: [Video]
    /// Opaque token for `fetchShortsFeedMore(continuation:)`; nil when exhausted.
    public var continuation: String?
    /// `true` when YouTube reported the request as signed in (`logged_in=1`),
    /// i.e. the sequence is personalised.
    public var isPersonalized: Bool

    public init(videos: [Video], continuation: String?, isPersonalized: Bool) {
        self.videos = videos
        self.continuation = continuation
        self.isPersonalized = isPersonalized
    }
}

/// Overlay metadata for one Short (title, channel, like/comment state) from
/// `reel/reel_item_watch`.
public struct ShortMetadata: Sendable, Equatable {
    public let videoId: String
    public var title: String
    public var channelTitle: String
    public var channelId: String?
    public var channelAvatarURL: URL?
    public var publishedTimeText: String?
    /// Like count as YouTube formats it ("1.2K"); nil when YouTube shows only "Like".
    public var likeCountText: String?
    /// Comment count as YouTube formats it ("239"); nil when comments are off.
    public var commentCountText: String?
    public var likeStatus: LikeStatus
    public var isSubscribed: Bool

    public init(
        videoId: String,
        title: String,
        channelTitle: String,
        channelId: String? = nil,
        channelAvatarURL: URL? = nil,
        publishedTimeText: String? = nil,
        likeCountText: String? = nil,
        commentCountText: String? = nil,
        likeStatus: LikeStatus = .none,
        isSubscribed: Bool = false
    ) {
        self.videoId = videoId
        self.title = title
        self.channelTitle = channelTitle
        self.channelId = channelId
        self.channelAvatarURL = channelAvatarURL
        self.publishedTimeText = publishedTimeText
        self.likeCountText = likeCountText
        self.commentCountText = commentCountText
        self.likeStatus = likeStatus
        self.isSubscribed = isSubscribed
    }
}

// MARK: - Request parameters

public enum ShortsSequenceParams {
    /// `params` for a seedless `reel/reel_item_watch` (the Shorts tab's first Short).
    public static let seedlessItemParams = "CA8%3D"
    /// `params` for a per-Short metadata `reel/reel_item_watch`.
    public static let metadataItemParams = "CAUwAg%3D%3D"
    /// `inputType` for a seedless `reel/reel_item_watch`.
    public static let seedlessInputType = "REEL_WATCH_INPUT_TYPE_SEEDLESS"
    /// Prefix on Shorts-shelf continuation tokens that come from the reel sequence, so
    /// `fetchShortsMore(continuationToken:)` routes them to `fetchShortsShelf`.
    public static let shelfTokenPrefix = "reel:"

    /// `sequenceParams` that seeds `reel/reel_watch_sequence` with `videoId` — the
    /// protobuf the official clients put in `reelWatchEndpoint.sequenceParams`:
    /// field 1 = videoId, followed by the fixed feed-type fields they always send.
    public static func seed(videoId: String) -> String {
        let id = Data(videoId.utf8)
        var bytes = Data([0x0A, UInt8(truncatingIfNeeded: id.count)])
        bytes.append(id)
        bytes.append(contentsOf: [0x2A, 0x02, 0x18, 0x02, 0x50, 0x19, 0x68, 0x00])
        return bytes.base64EncodedString()
    }
}

// MARK: - Parsers (pure, unit-tested)

public enum ShortsReelParser {

    /// `reel/reel_watch_sequence` → Shorts in order + next-page token. Ads are left out
    /// (`isAd(reelWatchEndpoint:)`).
    public static func parseSequence(_ json: [String: Any]) -> (videos: [Video], continuation: String?) {
        let entries = json["entries"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        let videos: [Video] = entries.compactMap { entry in
            guard
                let command = entry["command"] as? [String: Any],
                let endpoint = command["reelWatchEndpoint"] as? [String: Any],
                let video = video(fromReelWatchEndpoint: endpoint),
                seen.insert(video.id).inserted
            else { return nil }
            return video
        }
        return (videos, continuationToken(json))
    }

    /// Seedless `reel/reel_item_watch` → the first Short (nil if it is an ad) +
    /// `sequenceParams` for the rest.
    public static func parseSeedless(_ json: [String: Any]) -> (first: Video?, sequenceParams: String?) {
        let replacement = json["replacementEndpoint"] as? [String: Any]
        let endpoint = replacement?["reelWatchEndpoint"] as? [String: Any]
        return (endpoint.flatMap(video(fromReelWatchEndpoint:)), json["sequenceContinuation"] as? String)
    }

    /// `responseContext.serviceTrackingParams[].params[logged_in]` — `true` when YouTube
    /// treated the request as signed in. nil when the field is missing.
    public static func parseLoggedIn(_ json: [String: Any]) -> Bool? {
        let context = json["responseContext"] as? [String: Any]
        let services = context?["serviceTrackingParams"] as? [[String: Any]] ?? []
        for service in services {
            for param in service["params"] as? [[String: Any]] ?? [] where param["key"] as? String == "logged_in" {
                return (param["value"] as? String) == "1"
            }
        }
        return nil
    }

    /// Per-Short `reel/reel_item_watch` (TVHTML5 shape) → overlay metadata.
    /// Returns nil when the response has no `reelPlayerOverlayRenderer`.
    public static func parseMetadata(_ json: [String: Any], videoId: String) -> ShortMetadata? {
        guard
            let overlayRoot = json["overlay"] as? [String: Any],
            let overlay = overlayRoot["reelPlayerOverlayRenderer"] as? [String: Any]
        else { return nil }

        let headerRoot = overlay["reelPlayerHeaderSupportedRenderers"] as? [String: Any]
        let header = headerRoot?["reelPlayerHeaderRenderer"] as? [String: Any] ?? [:]
        let title = text(header["reelTitleText"]) ?? ""
        let channelTitle = text(header["channelTitleText"]) ?? ""
        let browse = (header["channelNavigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any]

        let subscribeRoot = overlay["subscribeButtonRenderer"] as? [String: Any]
        let subscribe = subscribeRoot?["subscribeButtonRenderer"] as? [String: Any]

        var metadata = ShortMetadata(
            videoId: videoId,
            title: title,
            channelTitle: channelTitle,
            channelId: browse?["browseId"] as? String ?? subscribe?["channelId"] as? String,
            channelAvatarURL: bestThumbnailURL(header["channelThumbnail"]),
            publishedTimeText: text(header["timestampText"]),
            isSubscribed: subscribe?["subscribed"] as? Bool ?? false
        )

        let actionBarRoot = overlay["buttonBar"] as? [String: Any]
        let actionBar = actionBarRoot?["reelActionBarViewModel"] as? [String: Any]
        for item in actionBar?["buttonViewModels"] as? [[String: Any]] ?? [] {
            let wrapper = item["reelActionBarButtonViewModel"] as? [String: Any] ?? item
            let button = wrapper["buttonViewModel"] as? [String: Any] ?? wrapper
            if let like = button["likeButtonViewModel"] as? [String: Any] {
                applyLike(like, to: &metadata)
            } else if let plain = iconButton(button), plain["iconName"] as? String == "COMMENT" {
                metadata.commentCountText = countText(plain["title"] as? String)
            }
        }
        return metadata
    }

    // MARK: Helpers

    /// Shorts ads come in the sequence as ordinary reelWatchEndpoints, even for a
    /// YouTube Premium account, marked `adClientParams.isAd` and
    /// `videoType: REEL_VIDEO_TYPE_AD` (a regular Short is `REEL_VIDEO_TYPE_VIDEO`).
    /// Captured from a TVHTML5 `reel/reel_watch_sequence` on 2026-11-12.
    static func isAd(reelWatchEndpoint endpoint: [String: Any]) -> Bool {
        let adParams = endpoint["adClientParams"] as? [String: Any]
        return adParams?["isAd"] as? Bool == true || endpoint["videoType"] as? String == "REEL_VIDEO_TYPE_AD"
    }

    /// The Short a reelWatchEndpoint opens; nil for an ad or an endpoint without an id.
    static func video(fromReelWatchEndpoint endpoint: [String: Any]) -> Video? {
        guard let id = endpoint["videoId"] as? String, !id.isEmpty, !isAd(reelWatchEndpoint: endpoint)
        else { return nil }
        return Video(
            id: id,
            title: "",
            channelTitle: "",
            thumbnailURL: bestThumbnailURL(endpoint["thumbnail"])
                ?? URL(string: "https://i.ytimg.com/vi/\(id)/oardefault.jpg"),
            isShort: true,
            hasPortraitThumbnail: true
        )
    }

    static func continuationToken(_ json: [String: Any]) -> String? {
        if let token = json["continuation"] as? String, !token.isEmpty { return token }
        // WEB shape — kept so a WEB response can't silently end the feed.
        let endpoint = json["continuationEndpoint"] as? [String: Any]
        let command = endpoint?["continuationCommand"] as? [String: Any]
        return command?["token"] as? String
    }

    private static func applyLike(_ like: [String: Any], to metadata: inout ShortMetadata) {
        let entity = like["likeStatusEntity"] as? [String: Any]
        switch entity?["likeStatus"] as? String {
        case "LIKE": metadata.likeStatus = .like
        case "DISLIKE": metadata.likeStatus = .dislike
        default: metadata.likeStatus = .none
        }
        let toggleRoot = like["toggleButtonViewModel"] as? [String: Any]
        let toggle = toggleRoot?["toggleButtonViewModel"] as? [String: Any]
        let key = metadata.likeStatus == .like ? "toggledButtonViewModel" : "defaultButtonViewModel"
        let state = toggle?[key] as? [String: Any]
        let button = state?["buttonViewModel"] as? [String: Any]
        metadata.likeCountText = countText(button?["title"] as? String)
    }

    /// The action-bar wraps plain buttons in one or two `buttonViewModel` levels;
    /// returns the innermost dictionary that carries `iconName`.
    private static func iconButton(_ dict: [String: Any]) -> [String: Any]? {
        var current: [String: Any]? = dict
        for _ in 0..<3 {
            guard let candidate = current else { return nil }
            if candidate["iconName"] != nil { return candidate }
            current = candidate["buttonViewModel"] as? [String: Any]
        }
        return nil
    }

    /// A button title is a count only when it contains a digit ("1.2K", "239");
    /// YouTube shows the plain label ("Like", "Comment") when the count is hidden.
    static func countText(_ title: String?) -> String? {
        guard let title, title.contains(where: \.isNumber) else { return nil }
        return title
    }

    static func text(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let content = dict["content"] as? String { return content }
        if let runs = dict["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    static func bestThumbnailURL(_ value: Any?) -> URL? {
        let thumbnails = (value as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let best = thumbnails.max { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        guard var raw = best?["url"] as? String else { return nil }
        if raw.hasPrefix("//") { raw = "https:" + raw }
        return URL(string: raw)
    }
}
