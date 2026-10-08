import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SmartTubeIOSCore

// MARK: - HomeWidgetSnapshotTests (task #353)

private func makePNG(width: Int, height: Int) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func video(_ id: String, isShort: Bool = false, isUpcoming: Bool = false) -> Video {
    var v = Video(
        id: id, title: "Title \(id)", channelTitle: "Channel",
        thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"))
    v.isShort = isShort
    v.isUpcoming = isUpcoming
    return v
}

private func tempStore() -> HomeWidgetStore {
    HomeWidgetStore(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeWidgetTests-\(UUID().uuidString)", isDirectory: true))
}

@Suite("Home widget snapshot (#353)")
struct HomeWidgetSnapshotTests {

    @Test("widget videos skip Shorts, upcoming premieres and duplicates, capped at maxItems")
    func widgetVideosFiltering() {
        let videos =
            [video("a"), video("s", isShort: true), video("u", isUpcoming: true), video("a")]
            + (1...10).map { video("v\($0)") }
        let ids = HomeWidgetStore.widgetVideos(from: videos).map(\.id)
        #expect(ids == ["a", "v1", "v2", "v3", "v4", "v5"])
        #expect(ids.count == HomeWidgetStore.maxItems)
    }

    @Test("save writes the snapshot and downscaled thumbnails, and load reads it back")
    func saveAndLoad() async throws {
        let store = tempStore()
        defer { store.clear() }
        let png = makePNG(width: 1280, height: 720)
        let changed = try await store.save([video("a"), video("b")], fetch: { _ in png })
        #expect(changed)

        let snapshot = try #require(store.load())
        #expect(snapshot.items.map(\.id) == ["a", "b"])
        #expect(snapshot.items[0].title == "Title a")

        let jpeg = try Data(contentsOf: store.thumbnailURL(for: "a"))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(props[kCGImagePropertyPixelWidth] as? Int)
        #expect(width <= 400)
    }

    @Test("4:3 thumbnails lose their baked-in letterbox bars; 16:9 ones are untouched")
    func letterboxCropped() throws {
        func size(_ data: Data) throws -> (Int, Int) {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
        }
        let fourThree = try #require(HomeWidgetStore.downscaledJPEG(makePNG(width: 480, height: 360), maxWidth: 400))
        #expect(try size(fourThree) == (400, 225))
        let sixteenNine = try #require(HomeWidgetStore.downscaledJPEG(makePNG(width: 1280, height: 720), maxWidth: 400))
        #expect(try size(sixteenNine) == (400, 225))
    }

    @Test("saving the same videos again reports no change and skips the download")
    func unchangedSaveIsNoOp() async throws {
        let store = tempStore()
        defer { store.clear() }
        let png = makePNG(width: 64, height: 36)
        try await store.save([video("a")], fetch: { _ in png })
        let changed = try await store.save(
            [video("a")], fetch: { _ in Issue.record("unexpected download"); return png })
        #expect(!changed)
    }

    @Test("thumbnails of videos no longer in the snapshot are removed")
    func staleThumbnailsRemoved() async throws {
        let store = tempStore()
        defer { store.clear() }
        let png = makePNG(width: 64, height: 36)
        try await store.save([video("a"), video("b")], fetch: { _ in png })
        try await store.save([video("b"), video("c")], fetch: { _ in png })
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: store.thumbnailURL(for: "a").path))
        #expect(fm.fileExists(atPath: store.thumbnailURL(for: "c").path))
    }

    @Test("a failed thumbnail download still saves the snapshot")
    func failedDownloadStillSaves() async throws {
        let store = tempStore()
        defer { store.clear() }
        struct Offline: Error {}
        try await store.save([video("a")], fetch: { _ in throw Offline() })
        #expect(store.load()?.items.map(\.id) == ["a"])
    }

    @Test("the tap URL opens the same video through SmartTubeURLScheme")
    func watchURLRoundTrips() {
        let item = HomeWidgetSnapshot.Item(
            id: "dQw4w9WgXcQ", title: "t", channelTitle: "c", duration: nil, isLive: false)
        #expect(item.watchURL.absoluteString == "smarttube://watch?v=dQw4w9WgXcQ")
        #expect(SmartTubeURLScheme.videoID(from: item.watchURL) == "dQw4w9WgXcQ")
    }
}
