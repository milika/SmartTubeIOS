import Foundation
import SmartTubeIOSCore
import os

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - Auth Token

extension PlaybackViewModel {

    /// Updates the local auth flag used for LOGIN_REQUIRED retry logic.
    /// The shared InnerTubeAPI instance already carries the updated token.
    public func updateAuthToken(_ token: String?) {
        let wasAuthenticated = hasAuthToken
        let tokenChanged = currentAuthToken != token
        hasAuthToken = token != nil
        currentAuthToken = token
        // Propagate the token to the PlaybackViewModel's own API instance so that
        // WatchtimeTracker sends authenticated watch-time pings (fixes watch history
        // not being recorded for signed-in users — GitHub issue #51).
        Task { await api.setAuthToken(token) }
        // Keep the cache's InnerTubeAPI instance in sync so prefetch requests
        // can make authenticated calls.
        Task { await VideoPreloadCache.shared.setAuthToken(token) }
        if wasAuthenticated, token == nil {
            // Signed out: evict account-bound cache data
            Task { await VideoPreloadCache.shared.evictAuthSensitiveData() }
        }
        if tokenChanged {
            // Signed in/out or token refreshed (BUG-016): drop the session's tracking URLs
            // so the next checkpoint resolves them again for the current account.
            tracker.setTrackingURLs(nil)
        }
    }

    /// Propagates the YouTube.com SAPISID cookie to the PlaybackViewModel's own
    /// InnerTubeAPI instance so WEB_CREATOR requests use SAPISIDHASH auth.
    public func updateSAPISID(_ sapisid: String?) {
        Task { await api.setSAPISID(sapisid) }
        Task { await VideoPreloadCache.shared.setSAPISID(sapisid) }
    }
}
