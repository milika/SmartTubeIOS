#if os(iOS)
import AppIntents
import Foundation
import SmartTubeIOS
import SmartTubeIOSCore
import UIKit

// MARK: - OpenYouTubeVideoIntent

/// Opens a YouTube video directly in SmartTube from Siri or the Shortcuts app.
///
/// Siri phrases (registered via SmartTubeShortcuts):
///   - "Watch on SmartTube"
///   - "Open YouTube video in SmartTube"
///   - "Play in SmartTube"
///
/// The intent extracts the video ID using YouTubeLinkHandler and fires the
/// existing smarttube://video/<id> deep link, which AppEntry.handleOpenURL
/// already handles — no new playback wiring required.
struct OpenYouTubeVideoIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Open YouTube Video in SmartTube", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens a YouTube video or Short URL directly in SmartTube.", bundle: L10n.bundle)
    )
    static let openAppWhenRun: Bool = true

    @Parameter(
        title: LocalizedStringResource("YouTube URL", bundle: L10n.bundle),
        description: LocalizedStringResource(
            "A YouTube video, Short, or youtu.be URL.", bundle: L10n.bundle)
    )
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

/// Intents that open the app hand it a smarttube:// route, so AppEntry.handleOpenURL is
/// the single place that turns requests into navigation (same as the Share Extension).
@MainActor
private func open(_ route: SmartTubeRoute) async {
    await UIApplication.shared.open(route.url)
}

// MARK: - SearchYouTubeIntent

struct SearchYouTubeIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Search YouTube in SmartTube", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource("Searches YouTube in SmartTube.", bundle: L10n.bundle))
    static let openAppWhenRun: Bool = true

    @Parameter(
        title: LocalizedStringResource("Search for", bundle: L10n.bundle),
        requestValueDialog: IntentDialog(
            LocalizedStringResource("What do you want to search for?", bundle: L10n.bundle))
    )
    var query: String

    static var parameterSummary: some ParameterSummary {
        // Parameter summaries are resolved by the system from Bundle.main, which has no
        // catalog, so this summary stays in English like the AppShortcut phrases below.
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

    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Section", bundle: L10n.bundle))
    static let caseDisplayRepresentations: [SmartTubeSection: DisplayRepresentation] = [
        .home: DisplayRepresentation(
            title: LocalizedStringResource("Home", bundle: L10n.bundle)),
        .recommended: DisplayRepresentation(
            title: LocalizedStringResource("Recommended", bundle: L10n.bundle)),
        .subscriptions: DisplayRepresentation(
            title: LocalizedStringResource("Subscriptions", bundle: L10n.bundle)),
        .history: DisplayRepresentation(
            title: LocalizedStringResource("History", bundle: L10n.bundle)),
        .watchLater: DisplayRepresentation(
            title: LocalizedStringResource("Watch Later", bundle: L10n.bundle)),
        .playlists: DisplayRepresentation(
            title: LocalizedStringResource("Playlists", bundle: L10n.bundle)),
        .channels: DisplayRepresentation(
            title: LocalizedStringResource("Channels", bundle: L10n.bundle)),
        .shorts: DisplayRepresentation(
            title: LocalizedStringResource("Shorts", bundle: L10n.bundle)),
        .music: DisplayRepresentation(
            title: LocalizedStringResource("Music", bundle: L10n.bundle)),
        .news: DisplayRepresentation(
            title: LocalizedStringResource("News", bundle: L10n.bundle)),
        .gaming: DisplayRepresentation(
            title: LocalizedStringResource("Gaming", bundle: L10n.bundle)),
        .live: DisplayRepresentation(
            title: LocalizedStringResource("Live", bundle: L10n.bundle)),
        .sports: DisplayRepresentation(
            title: LocalizedStringResource("Sports", bundle: L10n.bundle)),
    ]

    var sectionType: BrowseSection.SectionType? { BrowseSection.SectionType(rawValue: rawValue) }
}

struct OpenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Open SmartTube Section", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens a Home page section such as Subscriptions or Watch Later.",
            bundle: L10n.bundle))
    static let openAppWhenRun: Bool = true

    @Parameter(title: LocalizedStringResource("Section", bundle: L10n.bundle))
    var section: SmartTubeSection

    static var parameterSummary: some ParameterSummary {
        // System-resolved from Bundle.main; stays English (see SearchYouTubeIntent).
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
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Play Watch Later", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource(
            "Plays the first video in your Watch Later playlist.", bundle: L10n.bundle))
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await open(.playWatchLater)
        return .result()
    }
}

struct ContinueWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Continue Watching", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource(
            "Resumes the video you watched last in SmartTube.", bundle: L10n.bundle))
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await open(.continueWatching)
        return .result()
    }
}

// MARK: - Player controls (run without opening the app)

struct PlayPauseVideoIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Play or Pause SmartTube", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource(
            "Plays or pauses the video playing in SmartTube.", bundle: L10n.bundle))

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlayerRemote.togglePlayPause() else { throw SmartTubeIntentError.nothingPlaying }
        return .result()
    }
}

struct SkipForwardIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Skip Forward in SmartTube", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource(
            "Skips forward in the video playing in SmartTube.", bundle: L10n.bundle))

    @Parameter(
        title: LocalizedStringResource("Seconds", bundle: L10n.bundle), default: 10,
        inclusiveRange: (1, 600))
    var seconds: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlayerRemote.skip(by: TimeInterval(seconds)) else { throw SmartTubeIntentError.nothingPlaying }
        return .result()
    }
}

struct SkipBackwardIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Skip Back in SmartTube", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource(
            "Skips back in the video playing in SmartTube.", bundle: L10n.bundle))

    @Parameter(
        title: LocalizedStringResource("Seconds", bundle: L10n.bundle), default: 10,
        inclusiveRange: (1, 600))
    var seconds: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlayerRemote.skip(by: -TimeInterval(seconds)) else { throw SmartTubeIntentError.nothingPlaying }
        return .result()
    }
}

struct NextVideoIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Next Video in SmartTube", bundle: L10n.bundle)
    static let description = IntentDescription(
        LocalizedStringResource("Plays the next video in SmartTube.", bundle: L10n.bundle))

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
            // Spoken phrases are compiled into the AppShortcuts metadata in Bundle.main and
            // cannot resolve the SmartTubeIOSCore catalog, so they stay in English. Siri
            // still matches the localized display strings above.
            phrases: [
                "Open YouTube video in \(.applicationName)",
                "Watch on \(.applicationName)",
                "Play in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Open in SmartTube", bundle: L10n.bundle),
            systemImageName: "play.rectangle"
        )
        AppShortcut(
            intent: SearchYouTubeIntent(),
            phrases: ["Search \(.applicationName)", "Search YouTube in \(.applicationName)"],
            shortTitle: LocalizedStringResource("Search", bundle: L10n.bundle),
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenSectionIntent(),
            phrases: [
                "Open \(\.$section) in \(.applicationName)",
                "Show \(\.$section) in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Open Section", bundle: L10n.bundle),
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: PlayWatchLaterIntent(),
            phrases: [
                "Play Watch Later in \(.applicationName)",
                "Play my Watch Later in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Play Watch Later", bundle: L10n.bundle),
            systemImageName: "clock"
        )
        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: ["Continue watching in \(.applicationName)", "Resume \(.applicationName)"],
            shortTitle: LocalizedStringResource("Continue Watching", bundle: L10n.bundle),
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PlayPauseVideoIntent(),
            phrases: ["Pause \(.applicationName)", "Play or pause \(.applicationName)"],
            shortTitle: LocalizedStringResource("Play/Pause", bundle: L10n.bundle),
            systemImageName: "playpause"
        )
        AppShortcut(
            intent: NextVideoIntent(),
            phrases: ["Next video in \(.applicationName)", "Skip video in \(.applicationName)"],
            shortTitle: LocalizedStringResource("Next Video", bundle: L10n.bundle),
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
        case .invalidURL: L10n.string("Could not build a SmartTube deep link.")
        case .notYouTubeURL: L10n.string("The URL doesn't appear to be a YouTube video link.")
        case .emptySearch: L10n.string("Say or type what to search for.")
        case .nothingPlaying: L10n.string("Nothing is playing in SmartTube.")
        }
    }
}
#endif
