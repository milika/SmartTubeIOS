#if os(iOS)
import AppIntents
import UIKit
import SmartTubeIOS
import SmartTubeIOSCore

// MARK: - OpenYouTubeVideoIntent

/// Opens a YouTube video directly in SmartTube from Siri or the Shortcuts app.
///
/// Siri phrases (registered via ``SmartTubeShortcuts``):
///   - "Watch on SmartTube"
///   - "Open YouTube video in SmartTube"
///   - "Play in SmartTube"
///
/// The intent extracts the video ID using ``YouTubeLinkHandler`` and fires the
/// existing `smarttube://video/<id>` deep link, which ``AppEntry.handleOpenURL``
/// already handles — no new playback wiring required.
struct OpenYouTubeVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Open YouTube Video in SmartTube"
    static let description = IntentDescription(
        "Opens a YouTube video or Short URL directly in SmartTube."
    )
    static let openAppWhenRun: Bool = true

    @Parameter(title: "YouTube URL", description: "A YouTube video, Short, or youtu.be URL.")
    var url: URL

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let videoID = YouTubeLinkHandler.videoID(from: url) else {
            throw SmartTubeIntentError.notYouTubeURL
        }
        guard let deepLink = URL(string: "smarttube://video/\(videoID)") else {
            throw SmartTubeIntentError.invalidURL
        }
        await UIApplication.shared.open(deepLink)
        return .result()
    }
}

// MARK: - Opening the app at a route

/// Intents that open the app hand it a `smarttube://` route, so AppEntry.handleOpenURL is
/// the single place that turns requests into navigation (same as the Share Extension).
@MainActor
private func open(_ route: SmartTubeRoute) async {
    await UIApplication.shared.open(route.url)
}

// MARK: - SearchYouTubeIntent

struct SearchYouTubeIntent: AppIntent {
    static let title: LocalizedStringResource = "Search YouTube in SmartTube"
    static let description = IntentDescription("Searches YouTube in SmartTube.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Search for", requestValueDialog: "What do you want to search for?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search SmartTube for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SmartTubeIntentError.emptySearch }
        await open(.search(query: trimmed))
        return .result()
    }
}

// MARK: - OpenSectionIntent

enum SmartTubeSection: String, AppEnum {
    case home, recommended, subscriptions, history, watchLater, playlists, channels
    case shorts, music, news, gaming, live, sports

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Section"
    static let caseDisplayRepresentations: [SmartTubeSection: DisplayRepresentation] = [
        .home: "Home", .recommended: "Recommended", .subscriptions: "Subscriptions",
        .history: "History", .watchLater: "Watch Later", .playlists: "Playlists",
        .channels: "Channels", .shorts: "Shorts", .music: "Music", .news: "News",
        .gaming: "Gaming", .live: "Live", .sports: "Sports",
    ]

    var sectionType: BrowseSection.SectionType? { BrowseSection.SectionType(rawValue: rawValue) }
}

struct OpenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open SmartTube Section"
    static let description = IntentDescription("Opens a Home page section such as Subscriptions or Watch Later.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Section")
    var section: SmartTubeSection

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$section) in SmartTube")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let type = section.sectionType else { throw SmartTubeIntentError.invalidURL }
        await open(.section(type))
        return .result()
    }
}

// MARK: - PlayWatchLaterIntent / ContinueWatchingIntent

struct PlayWatchLaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Watch Later"
    static let description = IntentDescription("Plays the first video in your Watch Later playlist.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await open(.playWatchLater)
        return .result()
    }
}

struct ContinueWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Watching"
    static let description = IntentDescription("Resumes the video you watched last in SmartTube.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await open(.continueWatching)
        return .result()
    }
}

// MARK: - Player controls (run without opening the app)

struct PlayPauseVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause SmartTube"
    static let description = IntentDescription("Plays or pauses the video playing in SmartTube.")

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlayerRemote.togglePlayPause() else { throw SmartTubeIntentError.nothingPlaying }
        return .result()
    }
}

struct SkipForwardIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Forward in SmartTube"
    static let description = IntentDescription("Skips forward in the video playing in SmartTube.")

    @Parameter(title: "Seconds", default: 10, inclusiveRange: (1, 600))
    var seconds: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlayerRemote.skip(by: TimeInterval(seconds)) else { throw SmartTubeIntentError.nothingPlaying }
        return .result()
    }
}

struct SkipBackwardIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Back in SmartTube"
    static let description = IntentDescription("Skips back in the video playing in SmartTube.")

    @Parameter(title: "Seconds", default: 10, inclusiveRange: (1, 600))
    var seconds: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlayerRemote.skip(by: -TimeInterval(seconds)) else { throw SmartTubeIntentError.nothingPlaying }
        return .result()
    }
}

struct NextVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Video in SmartTube"
    static let description = IntentDescription("Plays the next video in SmartTube.")

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlayerRemote.playNext() else { throw SmartTubeIntentError.nothingPlaying }
        return .result()
    }
}

// MARK: - SmartTubeShortcuts

/// Registers app shortcuts so they surface in Spotlight, Siri and the Shortcuts app
/// automatically — no user setup required. Apple allows at most 10; skip back/forward stay
/// available as Shortcuts actions.
struct SmartTubeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenYouTubeVideoIntent(),
            phrases: [
                "Open YouTube video in \(.applicationName)",
                "Watch on \(.applicationName)",
                "Play in \(.applicationName)",
            ],
            shortTitle: "Open in SmartTube",
            systemImageName: "play.rectangle"
        )
        AppShortcut(
            intent: SearchYouTubeIntent(),
            phrases: ["Search \(.applicationName)", "Search YouTube in \(.applicationName)"],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenSectionIntent(),
            phrases: ["Open \(\.$section) in \(.applicationName)", "Show \(\.$section) in \(.applicationName)"],
            shortTitle: "Open Section",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: PlayWatchLaterIntent(),
            phrases: ["Play Watch Later in \(.applicationName)", "Play my Watch Later in \(.applicationName)"],
            shortTitle: "Play Watch Later",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: ["Continue watching in \(.applicationName)", "Resume \(.applicationName)"],
            shortTitle: "Continue Watching",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PlayPauseVideoIntent(),
            phrases: ["Pause \(.applicationName)", "Play or pause \(.applicationName)"],
            shortTitle: "Play/Pause",
            systemImageName: "playpause"
        )
        AppShortcut(
            intent: NextVideoIntent(),
            phrases: ["Next video in \(.applicationName)", "Skip video in \(.applicationName)"],
            shortTitle: "Next Video",
            systemImageName: "forward.end"
        )
    }
}

// MARK: - SmartTubeIntentError

enum SmartTubeIntentError: LocalizedError {
    case invalidURL
    case notYouTubeURL
    case emptySearch
    case nothingPlaying

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Could not build a SmartTube deep link."
        case .notYouTubeURL: "The URL doesn't appear to be a YouTube video link."
        case .emptySearch: "Say or type what to search for."
        case .nothingPlaying: "Nothing is playing in SmartTube."
        }
    }
}
#endif
