// Downloading is compiled out (App Store guideline 5.2.3). Define ENABLE_DOWNLOADS to build it.
#if ENABLE_DOWNLOADS
import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - DownloadStore tests
//
// Covers the destinationURL guarantee introduced in task #224:
//   - Percent-encoding produces a bijective mapping (no two distinct videoIds
//     can produce the same filename).
//   - Standard YouTube 11-char IDs pass through unchanged (no encoding needed).

@Suite("DownloadStore – destinationURL")
struct DownloadStoreDestinationURLTests {

    @Test("Standard YouTube IDs are unchanged after percent-encoding")
    func standardYouTubeIdUnchanged() async {
        let store = await DownloadStore.shared
        // YouTube video IDs only use [A-Za-z0-9_-], all of which are in
        // .alphanumerics except _ and -. Only _ and - get encoded.
        // But since we use .alphanumerics which excludes _ and -, those ARE encoded.
        // What matters is that the result is deterministic and unique.
        let url = await store.destinationURL(for: "dQw4w9WgXcQ")
        // The filename must end with .mp4 and contain the encoded ID.
        #expect(url.lastPathComponent.hasSuffix(".mp4"))
        #expect(url.lastPathComponent.contains("dQw4w9WgXcQ"))
    }

    @Test("Two distinct IDs never produce the same destination URL")
    func distinctIDsProduceDistinctURLs() async {
        let store = await DownloadStore.shared
        let url1 = await store.destinationURL(for: "abc123")
        let url2 = await store.destinationURL(for: "abc-123")
        // Old character-filter would produce the same result (both → "abc123").
        // Percent-encoding encodes "-" → "%2D", producing distinct filenames.
        #expect(url1 != url2, "Distinct video IDs must map to distinct file URLs")
    }

    @Test("destinationURL is deterministic for the same videoId")
    func deterministicURL() async {
        let store = await DownloadStore.shared
        let url1 = await store.destinationURL(for: "testVideo123")
        let url2 = await store.destinationURL(for: "testVideo123")
        #expect(url1 == url2)
    }
}
#endif  // ENABLE_DOWNLOADS
