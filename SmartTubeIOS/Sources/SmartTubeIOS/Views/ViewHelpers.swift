import SmartTubeIOSCore
import SwiftUI

// MARK: - ShortsPresentation
//
// Shared Identifiable wrapper used by HomeView, BrowseView and ChannelView to present
// ShortsPlayerView via .fullScreenCover(item:).

struct ShortsPresentation: Identifiable {
    let id = UUID()
    let source: ShortsFeedViewModel.Source

    /// A Short tapped in a feed shelf: like the official app, play it and continue
    /// with YouTube's Shorts sequence seeded from it (not the rest of the shelf).
    /// Hermetic UI tests (`--uitesting`) keep paging the shelf's stub list instead.
    init(shelf videos: [Video], startIndex: Int) {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") || !videos.indices.contains(startIndex) {
            source = .list(videos, startIndex: startIndex)
        } else {
            source = .algorithm(seed: videos[startIndex])
        }
    }

    /// A Short tapped in a fixed list (a channel's Shorts): page through that list,
    /// then continue with YouTube's sequence.
    init(list videos: [Video], startIndex: Int) {
        source = .list(videos, startIndex: startIndex)
    }
}

// MARK: - ChannelDestination
//
// Identifiable wrapper used to drive navigationDestination(item:) for channel navigation
// triggered by the .openChannel NotificationCenter event.

struct ChannelDestination: Identifiable, Hashable {
    let channelId: String
    var id: String { channelId }
}

// MARK: - Shared layout constants

/// tvOS: fixed 4 columns (flexible) — predictable across all TV sizes.
#if os(tvOS)
let videoGridColumns = [
    GridItem(.flexible(), spacing: 40),
    GridItem(.flexible(), spacing: 40),
    GridItem(.flexible(), spacing: 40),
    GridItem(.flexible(), spacing: 40),
]
let videoGridRowSpacing: CGFloat = 40
#else
let videoGridRowSpacing: CGFloat = 12

/// Fixed (not adaptive) columns avoid the rotation hit-test mismatch of issue #82.
func videoGridColumns(_ settings: AppSettings, landscape: Bool) -> [GridItem] {
    let count = landscape ? settings.gridColumnsLandscape : settings.gridColumnsPortrait
    return Array(repeating: GridItem(.flexible(), spacing: videoGridRowSpacing), count: count)
}
#endif

// MARK: - Layout orientation

private struct IsLandscapeLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` when the root window is wider than tall; set by `RootView`.
    var isLandscapeLayout: Bool {
        get { self[IsLandscapeLayoutKey.self] }
        set { self[IsLandscapeLayoutKey.self] = newValue }
    }
}

// MARK: - Accent color

extension AppSettings.AccentColorChoice {
    /// `nil` falls back to the `AccentColor` asset.
    public var color: Color? {
        switch self {
        case .system: return nil
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "Default", bundle: .module)
        case .red: return String(localized: "Red", bundle: .module)
        case .orange: return String(localized: "Orange", bundle: .module)
        case .yellow: return String(localized: "Yellow", bundle: .module)
        case .green: return String(localized: "Green", bundle: .module)
        case .mint: return String(localized: "Mint", bundle: .module)
        case .teal: return String(localized: "Teal", bundle: .module)
        case .blue: return String(localized: "Blue", bundle: .module)
        case .indigo: return String(localized: "Indigo", bundle: .module)
        case .purple: return String(localized: "Purple", bundle: .module)
        case .pink: return String(localized: "Pink", bundle: .module)
        }
    }

    /// Pre-tinted, because Picker menus re-tint template images with the current accent.
    var swatch: Image {
        #if canImport(UIKit)
        let tint = color.map { UIColor($0) } ?? UIColor(named: "AccentColor") ?? .systemBlue
        let base = UIImage(systemName: AppSymbol.colorSwatch) ?? UIImage()
        return Image(uiImage: base.withTintColor(tint, renderingMode: .alwaysOriginal))
        #else
        let tint = color.map { NSColor($0) } ?? NSColor(named: "AccentColor") ?? .systemBlue
        let base = NSImage(systemSymbolName: AppSymbol.colorSwatch, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        return Image(nsImage: base ?? NSImage())
        #endif
    }
}

// MARK: - DownloadAlertItem

/// Shared alert payload used by views that trigger video downloads.
struct DownloadAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - AppSymbol
//
// Single source of truth for SF Symbol names used across the app.
// Use these constants instead of raw strings in Image(systemName:) and Label(..., systemImage:).

enum AppSymbol {
    // MARK: - Navigation tabs
    static let home = "house.fill"
    static let search = "magnifyingglass"
    static let library = "square.stack.fill"
    static let channel = "person.crop.circle.fill"
    static let settings = "gearshape.fill"

    // MARK: - Navigation / chevrons
    static let chevronLeft = "chevron.left"
    static let chevronUp = "chevron.up"
    static let chevronDown = "chevron.down"

    // MARK: - Playback controls
    static let previousTrack = "backward.end.fill"
    static let nextTrack = "forward.end.fill"
    static let previousChapter = "backward.end.alt.fill"
    static let nextChapter = "forward.end.alt.fill"
    static let thumbsUp = "hand.thumbsup"
    static let thumbsDown = "hand.thumbsdown"

    // MARK: - Actions
    static let checkmark = "checkmark"
    static let xmark = "xmark"
    static let xmarkCircle = "xmark.circle.fill"
    static let share = "square.and.arrow.up"
    static let copyDoc = "doc.on.doc"
    static let download = "arrow.down.to.line"
    static let watchLater = "clock.badge"
    static let audioOnly = "waveform.circle"

    // MARK: - Status / info
    static let warning = "exclamationmark.triangle.fill"
    static let clock = "clock"
    static let questionCircle = "questionmark.circle"
    static let qrcode = "qrcode"
    static let colorSwatch = "circle.fill"

    // MARK: - People / account
    static let personCircle = "person.crop.circle"
    static let personRectangle = "person.crop.rectangle"
    static let personCircleQuestion = "person.crop.circle.badge.questionmark"
    static let personCircleWarning = "person.crop.circle.badge.exclamationmark"

    // MARK: - Content
    static let stackLayers = "square.stack"
    static let tvMediabox = "tv.and.mediabox"
    static let tvPlay = "play.tv"

    // MARK: - Shorts
    static let shortsTab = "play.square.stack.fill"
    static let thumbsUpFill = "hand.thumbsup.fill"
    static let thumbsDownFill = "hand.thumbsdown.fill"
    static let commentsFill = "text.bubble.fill"
    static let shareForward = "arrowshape.turn.up.right.fill"
    static let ellipsis = "ellipsis"
    static let playFill = "play.fill"
    static let autoScroll = "arrow.down.circle"
}
