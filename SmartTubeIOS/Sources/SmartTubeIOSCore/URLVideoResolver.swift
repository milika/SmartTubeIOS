import Foundation
import os

private let resolverLog = Logger(subsystem: "com.void.smarttube", category: "URLVideoResolver")

// MARK: - URLVideoResolver

/// Resolves an arbitrary URL to a YouTube video ID through a multi-step pipeline:
///
///   1. Direct parse — `YouTubeLinkHandler.videoID(from:)` with zero network cost.
///   2. HEAD redirect chain — follow up to `maxRedirects` 3xx hops (e.g. bit.ly → youtu.be).
///   3. Page scrape — GET the final URL and search the HTML for YouTube links.
///   4. Failure — returns `nil`.
///
/// `URLVideoResolver` is an actor so its `URLSession` and state are isolated from
/// the calling context without additional synchronisation.
public actor URLVideoResolver {

    // MARK: - Configuration

    /// Maximum number of 3xx redirect hops to follow before giving up.
    public static let maxRedirects = 5

    /// Per-request timeout in seconds for HEAD requests in the redirect chain.
    public static let hopTimeout: TimeInterval = 5

    /// Total timeout budget for the full resolution pipeline.
    public static let totalTimeout: TimeInterval = 12

    /// Maximum number of bytes read from a page during HTML scraping.
    public static let maxBodyBytes = 256 * 1024  // 256 KB

    // MARK: - Private state

    private let session: URLSession

    // MARK: - Init

    public init() {
        // Manual redirect handling so we can inspect each Location hop.
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = URLVideoResolver.hopTimeout
        config.timeoutIntervalForResource = URLVideoResolver.totalTimeout
        // No cookies, no credentials forwarded to arbitrary third-party hosts.
        session = URLSession(configuration: config, delegate: RedirectBlockingDelegate(), delegateQueue: nil)
    }

    // MARK: - Public API

    /// Resolves `url` to a YouTube video ID.
    /// - Parameter onProgress: Optional `@Sendable` closure called at the start of each
    ///   network step. Invoked from the actor's executor — dispatch to `@MainActor` inside
    ///   the closure for UI updates.
    /// - Returns: The video ID string, or `nil` if none was found.
    public func resolve(url: URL, onProgress: (@Sendable (String) -> Void)? = nil) async -> String? {
        resolverLog.notice("resolve: \(url.absoluteString, privacy: .public)")

        // Step 1 — Direct parse (no network)
        if let id = YouTubeLinkHandler.videoID(from: url) {
            resolverLog.notice("step1 hit: \(id, privacy: .public)")
            return id
        }

        // Step 2 — HEAD redirect chain
        onProgress?(L10n.string("Following redirect links\u{2026}"))
        if let id = await followRedirects(from: url, onProgress: onProgress) {
            resolverLog.notice("step2 hit: \(id, privacy: .public)")
            return id
        }

        // Step 3 — Page scrape
        onProgress?(L10n.string("Scanning page for video links\u{2026}"))
        if let id = await scrape(url: url) {
            resolverLog.notice("step3 hit: \(id, privacy: .public)")
            return id
        }

        resolverLog.notice("no video ID found")
        return nil
    }

    // MARK: - Step 2: HEAD redirect chain

    private func followRedirects(from startURL: URL, onProgress: (@Sendable (String) -> Void)? = nil) async -> String? {
        var current = startURL
        for hop in 1...URLVideoResolver.maxRedirects {
            guard isHTTP(current) else {
                resolverLog.notice("hop\(hop, privacy: .public) non-http scheme — stopping")
                return nil
            }

            var request = URLRequest(url: current)
            request.httpMethod = "HEAD"
            request.setValue("SmartTube/1.0", forHTTPHeaderField: "User-Agent")

            guard let (_, response) = try? await session.data(for: request) else {
                resolverLog.notice("hop\(hop, privacy: .public) request failed")
                return nil
            }

            guard let http = response as? HTTPURLResponse else { return nil }

            // Check the URL we actually landed on (session may follow some redirects
            // even with the delegate, depending on the OS version).
            let landed = http.url ?? current
            if let id = YouTubeLinkHandler.videoID(from: landed) { return id }

            // Look for a Location header to manually follow
            guard (300...399).contains(http.statusCode),
                let location = http.value(forHTTPHeaderField: "Location"),
                let next = URL(string: location, relativeTo: current)?.absoluteURL
            else {
                // Not a redirect — we've reached the final URL; step 3 will scrape it.
                resolverLog.notice("hop\(hop, privacy: .public) final URL: \(landed.absoluteString, privacy: .public)")
                return nil
            }

            resolverLog.notice("hop\(hop, privacy: .public) → \(next.absoluteString, privacy: .public)")
            onProgress?("  ↳ \(next.host ?? next.absoluteString)")
            if let id = YouTubeLinkHandler.videoID(from: next) { return id }
            current = next
        }
        resolverLog.notice("maxRedirects exhausted")
        return nil
    }

    // MARK: - Step 3: Page scrape

    private func scrape(url: URL) async -> String? {
        guard isHTTP(url) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("SmartTube/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse
        else { return nil }

        // Only parse text/html responses.
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.lowercased().contains("text/html") else {
            resolverLog.notice("scrape skipped — content-type: \(contentType, privacy: .public)")
            return nil
        }

        // Cap at maxBodyBytes to prevent memory blowout.
        let capped = data.prefix(URLVideoResolver.maxBodyBytes)
        guard
            let html = String(data: capped, encoding: .utf8)
                ?? String(data: capped, encoding: .isoLatin1)
        else { return nil }

        guard let found = HTMLVideoLinkExtractor.extractURL(from: html) else { return nil }
        return YouTubeLinkHandler.videoID(from: found)
    }

    // MARK: - Helpers

    private func isHTTP(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }
}

// MARK: - RedirectBlockingDelegate

/// Prevents URLSession from automatically following redirects so we can inspect
/// each `Location` hop in `followRedirects(from:)`.
private final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Pass nil to block automatic redirect — we handle it manually.
        completionHandler(nil)
    }
}
