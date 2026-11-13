import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - CheckedAsyncImage
//
// `AsyncImage` ignores the HTTP status. i.ytimg.com answers a missing thumbnail
// (e.g. `oardefault.jpg` for a Short with no portrait cover, `maxresdefault.jpg`
// for an SD upload) with **404 and a valid 120×90 grey "•••" JPEG** as the body, so
// AsyncImage reported `.success` with that placeholder and every fallback chain
// built on its `.failure` phase never ran.

/// Drop-in replacement for `AsyncImage(url:content:)` that reports an HTTP error
/// status as `.failure`, so callers can fall back to another URL. A `nil` URL is a
/// failure too (AsyncImage would stay `.empty` and spin forever).
struct CheckedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var loaded: Loaded?

    private struct Loaded {
        let url: URL?
        let phase: AsyncImagePhase
    }

    var body: some View {
        // A phase loaded for a previous URL is never shown for the new one.
        content(loaded.flatMap { $0.url == url ? $0.phase : nil } ?? .empty)
            .task(id: url) {
                guard let url else {
                    loaded = Loaded(url: nil, phase: .failure(URLError(.badURL)))
                    return
                }
                let phase: AsyncImagePhase
                do {
                    phase = .success(try await ThumbnailLoader.image(from: url))
                } catch is CancellationError {
                    return
                } catch {
                    phase = .failure(error)
                }
                loaded = Loaded(url: url, phase: phase)
            }
    }
}

// MARK: - ThumbnailLoader

enum ThumbnailLoader {
    struct HTTPStatusError: Error, Equatable {
        let statusCode: Int
    }

    struct UndecodableImageError: Error {}

    /// Fetches `url`, throwing `HTTPStatusError` for a non-2xx response even when
    /// the body is a decodable image.
    nonisolated static func imageData(from url: URL, session: URLSession = .shared) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPStatusError(statusCode: http.statusCode)
        }
        return data
    }

    @MainActor
    static func image(from url: URL, session: URLSession = .shared) async throws -> Image {
        let data = try await imageData(from: url, session: session)
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { throw UndecodableImageError() }
        return Image(uiImage: image)
        #else
        guard let image = NSImage(data: data) else { throw UndecodableImageError() }
        return Image(nsImage: image)
        #endif
    }
}
