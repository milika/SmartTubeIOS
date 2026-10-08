import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Home widget snapshot (task #353)
//
// The Home Screen widget never talks to YouTube: auth, BotGuard and the TV client stay in
// the app, and widget timelines run on a tight CPU/memory budget. Instead the app writes
// the first few Home videos plus small JPEG thumbnails into the App Group container each
// time Home loads, and the widget only reads them.
//
// Layout in the App Group container:
//   HomeWidget/snapshot.json   — HomeWidgetSnapshot
//   HomeWidget/<videoId>.jpg   — thumbnails, ~400 px wide

public struct HomeWidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let channelTitle: String
        public let duration: TimeInterval?
        public let isLive: Bool

        public init(id: String, title: String, channelTitle: String, duration: TimeInterval?, isLive: Bool) {
            self.id = id
            self.title = title
            self.channelTitle = channelTitle
            self.duration = duration
            self.isLive = isLive
        }

        /// What tapping the item opens: handled by the app's `onOpenURL` (SmartTubeURLScheme).
        public var watchURL: URL {
            var components = URLComponents()
            components.scheme = "smarttube"
            components.host = "watch"
            components.queryItems = [URLQueryItem(name: "v", value: id)]
            return components.url!
        }
    }

    public let items: [Item]
    public let updatedAt: Date

    public init(items: [Item], updatedAt: Date) {
        self.items = items
        self.updatedAt = updatedAt
    }
}

public struct HomeWidgetStore: Sendable {
    public static let appGroup = "group.com.void.smarttube"
    /// The widget's `kind`, used by the app to ask WidgetKit for a reload.
    public static let widgetKind = "SmartTubeHomeWidget"
    /// Large widget shows a 2×3 grid.
    public static let maxItems = 6
    static let thumbnailWidth: CGFloat = 400

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store in the shared App Group container, or nil when the entitlement is missing.
    public static var shared: HomeWidgetStore? {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        return HomeWidgetStore(directory: container.appendingPathComponent("HomeWidget", isDirectory: true))
    }

    var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }

    public func thumbnailURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).jpg")
    }

    // MARK: Reading (widget)

    public func load() -> HomeWidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(HomeWidgetSnapshot.self, from: data)
    }

    // MARK: Writing (app)

    /// The videos the widget shows: what the Home page shows, minus Shorts (portrait, and
    /// hidden when the user hides them), upcoming premieres and duplicates.
    public static func widgetVideos(from videos: [Video]) -> [Video] {
        var seen = Set<String>()
        return videos.filter { !$0.isShort && !$0.isUpcoming && seen.insert($0.id).inserted }
            .prefix(maxItems)
            .map { $0 }
    }

    /// Saves `videos` (already filtered by `widgetVideos`) and their thumbnails.
    /// Returns false when nothing changed, so the caller can skip the widget reload.
    @discardableResult
    public func save(
        _ videos: [Video],
        now: Date = Date(),
        fetch: @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }
    ) async throws -> Bool {
        let items = videos.map {
            HomeWidgetSnapshot.Item(
                id: $0.id, title: $0.title, channelTitle: $0.channelTitle,
                duration: $0.duration, isLive: $0.isLive)
        }
        let fm = FileManager.default
        if let current = load(), current.items == items,
            items.allSatisfy({ fm.fileExists(atPath: thumbnailURL(for: $0.id).path) })
        {
            return false
        }

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for video in videos where !fm.fileExists(atPath: thumbnailURL(for: video.id).path) {
            guard let source = video.thumbnailURL,
                let data = try? await fetch(source),
                let jpeg = Self.downscaledJPEG(data, maxWidth: Self.thumbnailWidth)
            else { continue }
            try? jpeg.write(to: thumbnailURL(for: video.id), options: .atomic)
        }

        let snapshot = HomeWidgetSnapshot(items: items, updatedAt: now)
        try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: .atomic)
        removeStaleThumbnails(keeping: Set(items.map(\.id)))
        return true
    }

    /// Removes the snapshot and thumbnails (sign-out).
    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func removeStaleThumbnails(keeping ids: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "jpg" {
            if !ids.contains(file.deletingPathExtension().lastPathComponent) {
                try? fm.removeItem(at: file)
            }
        }
    }

    /// YouTube's 4:3 thumbnails (hqdefault, sddefault) carry the 16:9 frame with black bars
    /// baked in above and below. The widget fills its tiles edge to edge, so keep only the
    /// centre 16:9 band.
    static func cropLetterbox(_ image: CGImage) -> CGImage {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard height > 0, abs(width / height - 4.0 / 3.0) < 0.02 else { return image }
        let band = (width * 9 / 16).rounded()
        let rect = CGRect(x: 0, y: ((height - band) / 2).rounded(), width: width, height: band)
        return image.cropping(to: rect) ?? image
    }

    /// Decodes `data` at reduced size and re-encodes it as JPEG. Widgets have a ~30 MB
    /// memory limit, so full-size thumbnails must not reach them.
    public static func downscaledJPEG(_ data: Data, maxWidth: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxWidth,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = cropLetterbox(thumbnail)
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
