import Foundation
import os

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

// MARK: - Playlist endpoints

extension InnerTubeAPI {

    // MARK: - Testing hook

    /// Internal accessor so unit tests can exercise the playlist parser without a live network.
    func parsePlaylistsForTesting(_ json: [String: Any]) throws -> [PlaylistInfo] {
        try parsePlaylists(from: json)
    }

    // MARK: - Public endpoints

    public func fetchUserPlaylists() async throws -> [PlaylistInfo] {
        var body = makeBody(client: tvClientContext)
        body["browseId"] = "FElibrary"
        let data = try await postTV(endpoint: "browse", body: body)
        // Log the second-level structure so it's easy to diagnose mismatches
        // if the live response shape differs from the mock.
        let contentsKeys = (data["contents"] as? [String: Any])?.keys.map { $0 } ?? []
        tubeLog.notice("fetchUserPlaylists FElibrary contents keys: \(contentsKeys, privacy: .public)")
        var playlists = try parsePlaylists(from: data)
        // Watch Later (id "WL") is a special system playlist. On the TVHTML5 FElibrary
        // response it appears as a specialCollectionRenderer / video-item shelf rather
        // than a gridPlaylistRenderer, so parsePlaylists never picks it up. Prepend it
        // explicitly — it is always available for authenticated users and always uses
        // the fixed browse ID VLWL (handled correctly by fetchPlaylistVideos).
        if !playlists.contains(where: { $0.id == "WL" }) {
            playlists.insert(PlaylistInfo(id: "WL", title: L10n.string("Watch Later")), at: 0)
        }
        return playlists
    }

    public func fetchPlaylistVideos(playlistId: String, continuationToken: String? = nil) async throws -> VideoGroup {
        let isAuth = authToken != nil
        var body = makeBody(
            client: isAuth ? tvClientContext : webClientContext,
            continuationToken: continuationToken)
        if continuationToken == nil {
            body["browseId"] = "VL\(playlistId)"
        }
        let data =
            isAuth
            ? try await postTV(endpoint: "browse", body: body)
            : try await post(endpoint: "browse", body: body)
        return try parseVideoGroup(from: data, title: nil)
    }

    // MARK: - Private playlist parser

    private func parsePlaylists(from json: [String: Any]) throws -> [PlaylistInfo] {
        var playlists: [PlaylistInfo] = []

        // Extracts a PlaylistInfo from a renderer dict, handling both
        // `playlistRenderer` (WEB search results) and
        // `gridPlaylistRenderer` / `compactPlaylistRenderer` (TVHTML5 library).
        func extractPlaylist(from renderer: [String: Any]) -> PlaylistInfo? {
            guard let id = renderer["playlistId"] as? String,
                let title = (renderer["title"] as? [String: Any]).flatMap({ extractText($0) })
                    ?? (renderer["title"] as? String)
            else { return nil }
            // Thumbnails may be at renderer["thumbnails"][0]["thumbnails"] (WEB)
            // or renderer["thumbnail"]["thumbnails"] (TV grid).
            let thumbSources: [[String: Any]]? =
                ((renderer["thumbnails"] as? [[String: Any]])?.first?["thumbnails"] as? [[String: Any]])
                ?? (renderer["thumbnail"] as? [String: Any]).flatMap { $0["thumbnails"] as? [[String: Any]] }
            let thumbURL = thumbSources?.last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }
            // Video count may be a plain string or in a text object.
            let count: Int? =
                (renderer["videoCount"] as? String).flatMap { Int($0) }
                ?? (renderer["videoCountText"] as? [String: Any]).flatMap { extractText($0) }.flatMap {
                    extractNumber($0)
                }
                ?? (renderer["videoCountShortText"] as? [String: Any]).flatMap { extractText($0) }.flatMap {
                    extractNumber($0)
                }
            return PlaylistInfo(id: id, title: title, videoCount: count, thumbnailURL: thumbURL)
        }

        // Extracts a PlaylistInfo from a TVHTML5 tileRenderer.
        // Playlist tiles carry a browseId prefixed with "VL" in onSelectCommand;
        // video tiles use watchEndpoint instead, so we filter by the "VL" prefix.
        func extractPlaylistFromTile(_ tile: [String: Any]) -> PlaylistInfo? {
            func findBrowseId(_ cmd: [String: Any]) -> String? {
                if let ep = cmd["browseEndpoint"] as? [String: Any],
                    let bid = ep["browseId"] as? String
                {
                    return bid
                }
                for v in cmd.values {
                    if let nested = v as? [String: Any], let bid = findBrowseId(nested) { return bid }
                }
                return nil
            }
            guard let cmd = tile["onSelectCommand"] as? [String: Any],
                let rawId = findBrowseId(cmd),
                rawId.hasPrefix("VL")
            else { return nil }
            let id = String(rawId.dropFirst(2))

            let metadata = (tile["metadata"] as? [String: Any])?["tileMetadataRenderer"] as? [String: Any]
            guard let titleRaw = metadata?["title"],
                let title = (titleRaw as? [String: Any]).flatMap({ extractText($0) }) ?? (titleRaw as? String)
            else { return nil }

            let thumbSources =
                // tileHeaderRenderer.thumbnail.thumbnails
                ((tile["header"] as? [String: Any])?["tileHeaderRenderer"] as? [String: Any])
                .flatMap { $0["thumbnail"] as? [String: Any] }
                .flatMap { $0["thumbnails"] as? [[String: Any]] }
                // direct tile.thumbnail.thumbnails
                ?? (tile["thumbnail"] as? [String: Any]).flatMap { $0["thumbnails"] as? [[String: Any]] }
                // tile.thumbnails[0].thumbnails (WEB-style)
                ?? (tile["thumbnails"] as? [[String: Any]])?.first.flatMap { $0["thumbnails"] as? [[String: Any]] }
            let thumbURL = thumbSources?.last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }

            return PlaylistInfo(id: id, title: title, videoCount: nil, thumbnailURL: thumbURL)
        }

        // Extracts a PlaylistInfo from a specialCollectionRenderer (used by TVHTML5
        // for system playlists like Watch Later "WL" and Liked Videos "LL").
        func extractSpecialCollection(from renderer: [String: Any]) -> PlaylistInfo? {
            guard let id = renderer["collectionId"] as? String else { return nil }
            let title = (renderer["title"] as? [String: Any]).flatMap({ extractText($0) }) ?? id
            let thumbDict = renderer["thumbnail"] as? [String: Any]
            let thumbSources: [[String: Any]]? =
                // direct thumbnails array (standard playlist shape)
                thumbDict.flatMap { $0["thumbnails"] as? [[String: Any]] }
                // collectionThumbnailRenderer.details[0].thumbnails
                ?? (thumbDict?["collectionThumbnailRenderer"] as? [String: Any])
                .flatMap { $0["details"] as? [[String: Any]] }
                .flatMap { $0.first?["thumbnails"] as? [[String: Any]] }
                // thumbnailRenderer.thumbnails
                ?? (renderer["thumbnailRenderer"] as? [String: Any])
                .flatMap { $0["thumbnails"] as? [[String: Any]] }
                // header.specialCollectionHeaderRenderer.thumbnail.thumbnails
                ?? ((renderer["header"] as? [String: Any])?["specialCollectionHeaderRenderer"] as? [String: Any])
                .flatMap { $0["thumbnail"] as? [String: Any] }
                .flatMap { $0["thumbnails"] as? [[String: Any]] }
            let thumbURL = thumbSources?.last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }
            tubeLog.notice(
                "specialCollectionRenderer id=\(id, privacy: .public) keys=\(renderer.keys.sorted().joined(separator: ","), privacy: .public) thumbURL=\(thumbURL?.absoluteString ?? "nil", privacy: .public)"
            )
            let count: Int? =
                (renderer["videoCountText"] as? [String: Any]).flatMap { extractText($0) }.flatMap { extractNumber($0) }
                ?? (renderer["totalCountText"] as? [String: Any]).flatMap { extractText($0) }.flatMap {
                    extractNumber($0)
                }
                ?? (renderer["videoCount"] as? String).flatMap { Int($0) }
            return PlaylistInfo(id: id, title: title, videoCount: count, thumbnailURL: thumbURL)
        }

        func walk(_ obj: Any) {
            if let dict = obj as? [String: Any] {
                let rendererKeys = ["playlistRenderer", "gridPlaylistRenderer", "compactPlaylistRenderer"]
                if let key = rendererKeys.first(where: { dict[$0] is [String: Any] }),
                    let renderer = dict[key] as? [String: Any],
                    let info = extractPlaylist(from: renderer)
                {
                    playlists.append(info)
                } else if let tile = dict["tileRenderer"] as? [String: Any],
                    let info = extractPlaylistFromTile(tile)
                {
                    playlists.append(info)
                } else if let renderer = dict["specialCollectionRenderer"] as? [String: Any],
                    let info = extractSpecialCollection(from: renderer)
                {
                    playlists.append(info)
                } else {
                    for value in dict.values { walk(value) }
                }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item) }
            }
        }

        walk(json)
        tubeLog.notice("parsePlaylists → \(playlists.count, privacy: .public) playlists")
        return playlists
    }
}
