// Single source of truth for accessibility identifiers used by UI tests.
// Use these constants instead of raw strings in `.accessibilityIdentifier(_:)`.
// Older screens still use raw strings (tracked in the SwiftLint baseline); move
// them here when they are touched.

enum AccessibilityID {

    enum Shorts {
        static let tab = "shorts.tab"
        static let loadingCover = "shorts.loadingCover"
        static let controlsOverlay = "shorts.controlsOverlay"
        static let errorBanner = "shorts.errorBanner"
        static let emptyState = "shorts.emptyState"
        static let indexLabel = "shorts.indexLabel"
        static let backButton = "shorts.backButton"
        static let channelButton = "shorts.channelButton"
        static let subscribeButton = "shorts.subscribeButton"
        static let title = "shorts.title"
        static let likeButton = "shorts.likeButton"
        static let dislikeButton = "shorts.dislikeButton"
        static let commentsButton = "shorts.commentsButton"
        static let shareButton = "shorts.shareButton"
        static let moreButton = "shorts.moreButton"
        static let progressBar = "shorts.progressBar"
        static let commentsSheet = "shorts.commentsSheet"
        static let autoScrollToggle = "shorts.autoScrollToggle"
    }

    enum Settings {
        static let shortsAutoScrollToggle = "settings.shortsAutoScrollToggle"
    }
}
