import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - WatchLaterMembershipStoreTests (#39)

@Suite("Watch Later membership store (#39)", .serialized)
@MainActor
struct WatchLaterMembershipStoreTests {

    /// Each test gets its own store and defaults suite. The shared singleton loads whatever
    /// earlier runs persisted, and other suites can create it first, so tests on it were
    /// order-dependent.
    private func freshStore() -> (WatchLaterMembershipStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "wl-\(UUID().uuidString)")!
        return (WatchLaterMembershipStore(defaults: defaults), defaults)
    }

    @Test("markSaved adds the id; contains reflects it")
    func markSavedAddsId() {
        let (store, _) = freshStore()
        store.markSaved("VID_SAVE_TEST")
        #expect(store.contains("VID_SAVE_TEST"))
    }

    @Test("markRemoved removes a previously saved id")
    func markRemovedRemovesId() {
        let (store, _) = freshStore()
        store.markSaved("VID_REMOVE_TEST")
        #expect(store.contains("VID_REMOVE_TEST"))
        store.markRemoved("VID_REMOVE_TEST")
        #expect(!store.contains("VID_REMOVE_TEST"))
    }

    @Test("markSaved writes the id to the exact UserDefaults key the store reads on init")
    func markSavedWritesToPersistenceKey() {
        let (store, defaults) = freshStore()
        store.markSaved("VID_PERSIST_TEST")
        let raw = defaults.stringArray(forKey: "com.smarttube.watchLaterMembership") ?? []
        #expect(
            raw.contains("VID_PERSIST_TEST"),
            "markSaved must persist to the same UserDefaults key the store's init reads from, or a fresh launch loses saved state"
        )
        #expect(WatchLaterMembershipStore(defaults: defaults).contains("VID_PERSIST_TEST"))
    }

    @Test("recentlySaved only includes saves inside the window, and removal clears it (#157)")
    func recentlySavedWindow() {
        let store = WatchLaterMembershipStore(defaults: UserDefaults(suiteName: "wl-\(UUID().uuidString)")!)
        let now = Date()
        store.markSaved("RECENT", at: now.addingTimeInterval(-30))
        store.markSaved("OLD", at: now.addingTimeInterval(-600))
        #expect(store.recentlySaved(within: 120, now: now) == ["RECENT"])
        store.markRemoved("RECENT")
        #expect(store.recentlySaved(within: 120, now: now).isEmpty)
    }

    @Test("re-saving an already-saved video refreshes its recency (#157)")
    func resaveRefreshesRecency() {
        let store = WatchLaterMembershipStore(defaults: UserDefaults(suiteName: "wl-\(UUID().uuidString)")!)
        let now = Date()
        store.markSaved("V", at: now.addingTimeInterval(-600))
        store.markSaved("V", at: now)
        #expect(store.recentlySaved(within: 120, now: now) == ["V"])
    }

    @Test("markSaved(video:) keeps the video with its token; markRemoved forgets it (#157)")
    func savedVideoKeepsToken() {
        let (store, _) = freshStore()
        store.markSaved(Video(id: "VID_A", title: "A", channelTitle: "C"), setVideoId: "TOKEN_A")
        store.markSaved(Video(id: "VID_B", title: "B", channelTitle: "C"), setVideoId: nil, at: Date(timeIntervalSinceNow: 1))
        #expect(store.setVideoId(for: "VID_A") == "TOKEN_A")
        #expect(store.savedVideo("VID_A")?.playlistId == "WL")
        #expect(store.recentlySavedVideos(within: 60).map(\.id) == ["VID_B", "VID_A"])
        store.markRemoved("VID_A")
        #expect(store.savedVideo("VID_A") == nil)
        #expect(store.setVideoId(for: "VID_A") == nil)
    }
}
