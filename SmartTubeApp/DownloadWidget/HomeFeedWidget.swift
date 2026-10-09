import SmartTubeIOSCore
import SwiftUI
import UIKit
import WidgetKit

// MARK: - HomeFeedWidget (task #353)
//
// Home Screen widget showing thumbnails from the app's Home page. Tapping a video opens
// smarttube://watch?v=ID, which the app plays (AppEntry.handleOpenURL).
//
// The widget only reads the snapshot the app writes into the App Group container
// (HomeWidgetSnapshot.swift / HomeWidgetPublisher.swift); it never calls YouTube.
//
// small:  1 video, the whole widget is the link
// medium: 1 video, full width
// large:  2×3 grid

struct HomeFeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetStore.widgetKind, provider: HomeFeedProvider()) { entry in
            HomeFeedWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("SmartTube Home")
        .description("Videos from your Home page. Tap one to play it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct HomeFeedEntry: TimelineEntry {
    struct Item: Identifiable {
        let video: HomeWidgetSnapshot.Item
        let thumbnail: UIImage?
        var id: String { video.id }
    }

    let date: Date
    let items: [Item]

    static let empty = HomeFeedEntry(date: Date(), items: [])
}

struct HomeFeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeFeedEntry {
        let sample = HomeWidgetSnapshot.Item(
            id: "placeholder", title: "Video title", channelTitle: "Channel", duration: 600, isLive: false)
        return HomeFeedEntry(date: Date(), items: Array(repeating: .init(video: sample, thumbnail: nil), count: 6))
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeFeedEntry) -> Void) {
        completion(context.isPreview && loadEntry().items.isEmpty ? placeholder(in: context) : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeFeedEntry>) -> Void) {
        // The app reloads the widget whenever Home changes; the fallback only re-reads
        // the snapshot in case a reload was missed.
        let next = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
        completion(Timeline(entries: [loadEntry()], policy: .after(next)))
    }

    private func loadEntry() -> HomeFeedEntry {
        guard let store = HomeWidgetStore.shared, let snapshot = store.load() else { return .empty }
        let items = snapshot.items.map { item in
            HomeFeedEntry.Item(video: item, thumbnail: UIImage(contentsOfFile: store.thumbnailURL(for: item.id).path))
        }
        return HomeFeedEntry(date: snapshot.updatedAt, items: items)
    }
}

// MARK: - Views

struct HomeFeedWidgetView: View {
    let entry: HomeFeedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.items.isEmpty {
            emptyState
        } else {
            switch family {
            case .systemSmall, .systemMedium:
                // Full-bleed: one video is the whole widget (the wide one too).
                VideoTile(item: entry.items[0], size: .large)
                    .widgetURL(entry.items[0].video.watchURL)
            default:
                grid(columns: 2, rows: 3, size: .small)
            }
        }
    }

    private func grid(columns: Int, rows: Int, size: VideoTile.Size) -> some View {
        let items = Array(entry.items.prefix(columns * rows))
        return Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < items.count {
                            Link(destination: items[index].video.watchURL) {
                                VideoTile(item: items[index], size: size)
                                    .clipShape(ContainerRelativeShape())
                            }
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
        .padding(4)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "play.rectangle.fill")
                .font(.title)
                .foregroundStyle(.red)
            Text("Open SmartTube to load your Home feed")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }
}

/// A thumbnail filling the whole tile, with the title and channel on a dark gradient at the
/// bottom (photo-widget style).
private struct VideoTile: View {
    enum Size { case large, small }

    let item: HomeFeedEntry.Item
    let size: Size

    var body: some View {
        Color.black
            .overlay { thumbnail }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.8), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .topTrailing) { badge }
            .clipped()
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: size == .small ? 0 : 2) {
            Text(item.video.title)
                .font(titleFont)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(item.video.channelTitle)
                .font(channelFont)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .padding(.horizontal, size == .large ? 14 : 8)
        .padding(.bottom, size == .large ? 14 : 7)
    }

    private var titleFont: Font {
        switch size {
        case .large: return .system(size: 17, weight: .bold)
        case .small: return .system(size: 12, weight: .bold)
        }
    }

    private var channelFont: Font {
        switch size {
        case .large: return .system(size: 15)
        case .small: return .system(size: 10)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = item.thumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(.white.opacity(0.12))
        }
    }

    @ViewBuilder private var badge: some View {
        if item.video.isLive {
            label("LIVE", background: .red)
        } else if let duration = item.video.duration, duration > 0 {
            label(Self.format(duration), background: .black.opacity(0.75))
        }
    }

    private func label(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(background, in: RoundedRectangle(cornerRadius: 3))
            .padding(size == .large ? 10 : 6)
    }

    static func format(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
