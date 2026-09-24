import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - LocalWatchHistoryStoreTests (#150)

@MainActor
@Suite("LocalWatchHistoryStore (#150)")
struct LocalWatchHistoryStoreTests {

    private func makeStore() -> (LocalWatchHistoryStore, UserDefaults, String) {
        let suite = "LocalWatchHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (LocalWatchHistoryStore(defaults: defaults), defaults, suite)
    }

    private func video(_ id: String) -> Video {
        Video(id: id, title: "Title \(id)", channelTitle: "Chan", channelId: "UC1")
    }

    @Test("records most recent first")
    func mostRecentFirst() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.record(video("a"), at: Date(timeIntervalSince1970: 1))
        store.record(video("b"), at: Date(timeIntervalSince1970: 2))
        #expect(store.videos.map(\.id) == ["b", "a"])
    }

    @Test("re-watching a video moves it to the front without duplicating")
    func dedupeMovesToFront() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.record(video("a"))
        store.record(video("b"))
        store.record(video("a"))
        #expect(store.videos.map(\.id) == ["a", "b"])
    }

    @Test("caps at maxEntries, evicting the oldest")
    func capsEntries() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        for i in 0..<(LocalWatchHistoryStore.maxEntries + 5) { store.record(video("v\(i)")) }
        #expect(store.entries.count == LocalWatchHistoryStore.maxEntries)
        #expect(store.videos.first?.id == "v\(LocalWatchHistoryStore.maxEntries + 4)")
        #expect(!store.videos.contains { $0.id == "v0" })
    }

    @Test("persists across instances sharing the same defaults")
    func persists() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.record(video("a"))
        let reloaded = LocalWatchHistoryStore(defaults: defaults)
        #expect(reloaded.videos.map(\.id) == ["a"])
    }

    @Test("clear removes everything, including from disk")
    func clearEmpties() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.record(video("a"))
        store.clear()
        #expect(store.videos.isEmpty)
        #expect(LocalWatchHistoryStore(defaults: defaults).videos.isEmpty)
    }

    @Test("stored entries keep display fields but drop per-fetch tokens")
    func slimsVideo() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var v = video("a")
        v.notInterestedToken = "secret-token"
        store.record(v)
        #expect(store.videos.first?.title == "Title a")
        #expect(store.videos.first?.notInterestedToken == nil)
    }
}
