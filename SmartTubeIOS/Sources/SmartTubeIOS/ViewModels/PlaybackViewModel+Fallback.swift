@preconcurrency import AVFoundation
import os
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
import SmartTubeIOSCore

private typealias VideoFormat = SmartTubeIOSCore.VideoFormat

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - Exhaustive Playback Retry

extension PlaybackViewModel {

    // MARK: - Entry Points

    /// Main retry entry point. Called whenever the primary iOS stream fails.
    ///
    /// Strategy:
    ///   Phase 0 — Authenticated TV client: when logged in, the TV client with
    ///             `html5Preference: HTML5_PREF_WANTS` returns `streamingData` including
    ///             an `hlsManifestUrl`. Authenticated HLS URLs bypass rqh=1 CDN enforcement
    ///             and enable quality switching via AVPlayer ABR. Skipped if not logged in.
    ///   Phase 1 — TV embedded (TVHTML5_SIMPLY_EMBEDDED_PLAYER): returns HLS for most
    ///             embeddable videos without pot/rqh=1 restriction.
    ///   Phase 2 — try HLS + adaptive from iOS and Android clients in order.
    ///   Phase 3 — Android VR (Oculus Quest client, nameID=28): per yt-dlp research, this
    ///             client is exempt from the PO-token / rqh=1 requirement on adaptive streams.
    ///             Correct VR headers (nameID=28, Oculus UA on googleapis.com) are required.
    ///   Phase 4 — if all adaptive attempts fail, fall back to the Android muxed 360p stream.
    ///   The entire cycle repeats up to 3 times to survive transient network errors.
    func exhaustiveRetry(video: Video, originalError: Error?, playerInfo: PlayerInfo? = nil, cached: CachedVideoData? = nil) async {
        // Testing override: --uitesting-force-stream-method restricts the retry to a
        // single named client so UI tests can probe one path at a time.
        if let method = StreamMethodProbeSupport.forcedStreamMethod {
            await probeStreamMethod(method, video: video)
            return
        }
        #if canImport(WebKit)
        // Phase -1a: Cached WKWebView HLS URL shortcut — skip 5–9 s extraction when the
        // master manifest URL for this video was stored by a prior session or neighbour
        // pre-extraction. Falls through to live WKWebView extraction if the URL has expired
        // or if tryWebViewHLS fails (e.g. 403 on an expired signed URL).
        //
        // Note: for preWarm origin + pot=nil videos (e.g. uN7uKLsGRWw), tryWebViewHLS will
        // fail (~1.32 s) because pfa/1 variant playlist segments need pot= or a warm CDN
        // session. However, this failure is USEFUL: it gives wkHLSEarlyTask (launched by
        // loadAsync concurrently) ~1.78 s of head start so Path B wins immediately after
        // Phase -1a fails. Do NOT skip Phase -1a for preWarm+pot=nil — doing so removes the
        // concurrent overlap and forces Path B to wait the full ~2.17 s alone, costing ~0.6 s.
        if let cachedHLSURL = await VideoPreloadCache.shared.cachedWKHLSURL(for: video.id) {
            playerLog.notice("[wkHLS] cached HLS URL found — probing validity")
            let nSolver = YouTubeWebViewHLSExtractor.shared.extractedNSolver
            // fix21: Read pot= from VideoPreloadCache instead of from the extractor's
            // volatile extractedPoToken field. The extractor resets that field to nil at the
            // START of every new extractHLSURL call; wkHLSEarlyTask triggers that reset
            // before this point, so extractedPoToken is always nil here. The cache entry is
            // written by preWarm() AFTER extraction completes and is only evicted together
            // with the HLS URL itself — so it reliably holds the preWarm-extracted token.
            // fix24: Fall back to InnerTubeAPI's BotGuard-minted token when VideoPreloadCache
            // has no pot=. For videos with no serviceIntegrityDimensions.poToken (e.g.
            // uN7uKLsGRWw), preWarm stores nil in wkHLSPoTokenCache but BotGuard may have
            // minted a valid CDN token during loadAsync's 2 s prefetchPoToken window. Using
            // this token allows the proxy's Step 4 to inject pot= into segment URLs so the
            // CDN accepts them without iOS UA rejection.
            var capturedPoToken = await VideoPreloadCache.shared.cachedPoToken(for: video.id)
            // NOTE: Do NOT fall back to InnerTubeAPI.currentPoToken (BotGuard token, ~107 chars).
            // The BotGuard pot= is for youtubei/v1/player API auth; it is NOT a valid CDN
            // segment token. Injecting it into segment URLs TRIGGERS pot= validation on CDN
            // servers that would otherwise not enforce rqh=1 (returning HTTP 206). The result
            // is that CDN rejects segments with the wrong pot= type (-12753/-12860) even though
            // it would have accepted them with pot=nil. Only WKWebView-player-minted tokens
            // (from serviceIntegrityDimensions.poToken) are valid CDN segment tokens.
            // fix24 fallback removed in fix26.
            // fix25: Skip the HEAD probe if the URL was stored within the last 10 s.
            // The double-prewarm in VideoCardView ensures the cached URL is from a fresh
            // WKWebView session (< 1s old when the heartbeat fires). A fresh URL's CDN
            // session is guaranteed active — probing wastes ~0.22s that the user perceives.
            // For older URLs (> 10s), keep the probe to detect expired manifest URLs early.
            let urlIsFresh = await VideoPreloadCache.shared.isWKHLSURLFresh(for: video.id, within: 10)
            if urlIsFresh {
                playerLog.notice("[wkHLS/fix25] fresh URL (< 10s) — skipping probe")
            }
            let probeValid: Bool
            if urlIsFresh {
                probeValid = true
            } else {
                probeValid = await isWKHLSURLValid(cachedHLSURL)
            }
            if probeValid {
                if await tryWebViewHLS(cachedHLSURL, nSolver: nSolver, poToken: capturedPoToken, skipIfPfa1: true, for: video) {
                    playerLog.notice("[wkHLS] cached URL played — exhaustiveRetry done")
                    if let playerInfo { launchPhase2(video: video, info: playerInfo, cached: cached) }
                    return
                }
                playerLog.notice("[wkHLS] cached URL failed (tryWebViewHLS) — invalidating and falling back to live WKWebView")
                await VideoPreloadCache.shared.invalidateWKHLSURL(for: video.id)
            } else {
                playerLog.notice("[wkHLS] cached URL expired (probe 403/timeout) — invalidating and using live extraction")
                await VideoPreloadCache.shared.invalidateWKHLSURL(for: video.id)
            }
        }
        // Phase -2 + Phase -1b: race BotGuardWV adaptive path vs WKWebView HLS path.
        //
        // Both paths start simultaneously. They interleave cooperatively at every `await`
        // (suspension point) since both run on @MainActor. Whichever path reaches
        // `readyToPlay` first wins; the other task is cancelled immediately.
        //
        // Path A — BotGuardWV adaptive: waits for BotGuard mint (up to 6 s on cold start,
        //   <5 ms if already warm), probes CDN, tries WEB adaptive / proxy HLS / iOS+Android
        //   adaptive. Fast for videos where the CDN accepts the minted token (~1–2 s).
        //
        // Path B — WKWebView HLS: awaits `wkHLSEarlyTask` (started in loadAsync, already
        //   in-flight). Bypasses the 6 s BotGuard wait on cold starts. Fast for rqh=1 videos
        //   where the CDN probe returns 403 (~3–4 s from loadAsync start).
        //
        // Path C — AndroidVR adaptive: fetches playerInfo via the ANDROID_VR (Oculus Quest)
        //   client, which is CDN-exempt from rqh=1 / pot= token requirements. Runs concurrently
        //   with Path A and B. Expected ~2–3 s cold; beats serial WKWebView extraction (~3–5 s).
        //
        // fix30 (task #230): Pre-fetch TVEmbedded playerInfo in parallel with the race on iOS.
        // If all race paths fail, Phase 1 (TVEmbedded serial) can consume the already-resolved
        // result instead of waiting an additional ~0.5–1 s for a fresh network request.
        // tvOS already starts tvEmbeddedEarlyTask inside tryAllStreams (fix2); on iOS we fire
        // it here so the prefetch begins as soon as the race paths do.
        #if !os(tvOS)
        if tvEmbeddedEarlyTask == nil {
            let prefetchVideoId = video.id
            tvEmbeddedEarlyTask = Task { [weak self] in
                guard let self else { return nil }
                return try? await self.api.fetchPlayerInfoTVEmbedded(videoId: prefetchVideoId)
            }
            playerLog.notice("[TVEmbedded] fix30: started iOS TVEmbedded early pre-fetch alongside race paths")
        }
        #endif
        //
        // Key safety property: all paths are @MainActor, so `player.replaceCurrentItem` and
        // `itemObserverTask` mutations are always serialised. Losing paths' status streams
        // exit via task cancellation.
        var raceWon = false
        var raceWinningPath = 0  // 0=A (BotGuardWV), 1=B (WKWebView HLS), 2=C (AndroidVR)
        await withTaskGroup(of: (Bool, Int).self) { raceGroup in
            // Path A, B, C are @MainActor methods — calling them via `await self.`
            // from these nonisolated closures hops to the main actor for each path.
            // They interleave cooperatively at every `await` suspension point.
            raceGroup.addTask { (await self.racePathA(video: video), 0) }
            raceGroup.addTask { (await self.racePathB(video: video), 1) }
            #if os(tvOS)
            // fix2: Skip racePathC on tvOS. A fresh AndroidVR fetch hits the same rqh=1
            // timeout (2s) for the same video — wasting 2s just to fail again. The
            // TVEmbedded pre-fetch (tvEmbeddedEarlyTask) already runs concurrently from
            // tryAllStreams; Phase 1 will consume it instantly after the race.
            raceGroup.addTask { (false, 2) }
            #else
            raceGroup.addTask { (await self.racePathC(video: video), 2) }
            #endif
            for await (result, path) in raceGroup {
                if result {
                    raceWon = true
                    raceWinningPath = path
                    raceGroup.cancelAll()
                    return
                }
            }
        }
        if raceWon {
            switch raceWinningPath {
            case 1:
                playerLog.notice("✅ [webView] Path B won — WKWebView HLS playing via wkHLSEarlyTask — exhaustiveRetry done")
                // tryWebViewHLS does not call launchPhase2 internally — do it here so Phase 2
                // metadata (nextVideo, endCards, sponsorSegments) is fetched and cached data is used.
                if let playerInfo { launchPhase2(video: video, info: playerInfo, cached: cached) }
            case 2:
                playerLog.notice("[AndroidVR] ✅ Path C won — AndroidVR adaptive — exhaustiveRetry done")
                // attemptComposition already called launchPhase2(vrInfo) with the correct AndroidVR
                // playerInfo. Do NOT call it again — a second call would cancel the first phase2Task
                // and restart it with the stale iOS playerInfo, reverting availableFormats to
                // rqh=1-blocked streams and breaking quality switches.
                //
                // If AndroidVR composed at low quality (maxH < 480 and below user's preferred),
                // schedule a background HLS quality upgrade via TVEmbedded or MWEB while the
                // video is already playing at the lower quality. Does not affect readyToPlay timing.
                let vrMaxH = availableFormats.map(\.height).max() ?? 0
                let preferredH = settings.preferredQuality == .auto
                    ? Self.displayMaxVideoHeight()
                    : (settings.preferredQuality.maxHeight ?? 1080)
                if vrMaxH > 0 && vrMaxH < min(preferredH, 480) {
                    playerLog.notice("[AndroidVR] maxH=\(vrMaxH) < preferred \(min(preferredH, 480))p — scheduling background HLS quality upgrade")
                    let upgradeVideo = video
                    Task { [weak self] in await self?.backgroundQualityUpgrade(video: upgradeVideo) }
                }
            default:
                playerLog.notice("[BotGuardWV] ✅ adaptive streaming via minted BotGuard token — exhaustiveRetry done")
                // attemptComposition / attemptURL already called launchPhase2(webInfo). Same
                // reasoning as Path C: don't override with stale playerInfo.
            }
            return
        }

        // Both race paths failed — fall back to serial WKWebView extraction in case
        // the early task returned nil (e.g. network timeout, JS player error).
        // Skip serial extraction when Path B already hit a CDN permission error — a fresh
        // extraction produces the same CDN-signed URL which will get the same 403.
        // fix235: guard cancellation before expensive serial extraction — the exhaustiveRetry
        // task may have been cancelled by a subsequent load() or stop() call.
        guard !Task.isCancelled else {
            playerLog.notice("⚠️ [webView] race failed but task is cancelled — skipping serial extraction for \(video.id)")
            return
        }
        if wkHLSPermissionDenied {
            playerLog.notice("⚠️ [webView] race Path B hit CDN permission error — skipping serial extraction, going straight to client chain")
        } else {
            playerLog.notice("⚠️ [webView] race failed — attempting serial WKWebView extraction")
            isLoading = true
            retryStatusMessage = "Still loading\u{2026}"
            // Use serialExtract() instead of extractHLSURL() directly: serialExtract awaits any
            // in-flight extraction (for any video) before starting a new one, preventing the
            // cross-video cancellation chain where two concurrent serial callers (for video A and
            // video B) each call extractHLSURL and cancel each other via finish(url:nil).
            let serialURL = await YouTubeWebViewHLSExtractor.shared.serialExtract(videoId: video.id)
            let nSolverSerial = YouTubeWebViewHLSExtractor.shared.extractedNSolver
            if let pot = YouTubeWebViewHLSExtractor.shared.extractedPoToken {
                await api.storeExternalPoToken(pot, for: video.id)
            }
            if let serialURL {
                if await tryWebViewHLS(serialURL, nSolver: nSolverSerial, for: video) {
                    playerLog.notice("✅ [webView] serial WKWebView HLS playing — exhaustiveRetry done")
                    if let playerInfo { launchPhase2(video: video, info: playerInfo, cached: cached) }
                    return
                }
                playerLog.notice("⚠️ [webView] serial HLS load failed — falling through to client retry chain")
            } else {
                playerLog.notice("⚠️ [webView] serial WKWebView extraction returned nil — proceeding with client chain")
            }
        }
        #endif
        for attempt in 1...3 {
            guard !Task.isCancelled else { return }
            retryAttempts = attempt
            isLoading = true
            retryStatusMessage = attempt == 1 ? "Trying alternative sources\u{2026}" : "Retrying (\(attempt)/3)\u{2026}"
            playerLog.notice("Exhaustive retry \(attempt)/3 for \(video.id)")

            // Evict the stale cache entry so each attempt gets fresh signed URLs.
            await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)

            // --- Parallel fetch: fire all 7 API calls concurrently ---
            //
            // Each fetchPlayerInfo* is an independent network round-trip (~0.5–1 s).
            // Running them serially added 3.5–7 s of unnecessary latency on every load
            // for videos where the first few clients fail (rqh=1, embedding-disabled, etc.).
            // Running them in parallel collapses that to ~1 s (slowest single fetch).
            //
            // Play strategy:
            //  • HLS results are tried immediately as they arrive — first HLS success wins.
            //  • Non-HLS (adaptive-only) results are queued and tried in priority order
            //    after all fetches complete, so the fastest HLS client always gets priority
            //    regardless of which fetch finished first.
            //
            // Priority (lower = higher priority, mirrors proven probe data 2026-06-05):
            //   0 TVAuth  1 MWEB  2 TVEmbedded  3 WebSafari  4 iOS  5 Android  6 AndroidVR

            // Capture @MainActor state before entering the task group.
            let capturedEarlyTask = tvEmbeddedEarlyTask
            tvEmbeddedEarlyTask = nil
            let capturedHasAuth = hasAuthToken

            // Task group result carrier — @unchecked Sendable because PlayerInfo is accessed
            // only from @MainActor (the `for await` body runs on the calling actor).
            struct _FR: @unchecked Sendable {
                let priority: Int; let label: String; let info: PlayerInfo; let skipMuxed: Bool
            }
            enum _FO: @unchecked Sendable { case result(_FR); case ipBlocked(Error) }

            var pendingNonHLS: [_FR] = []     // adaptive-only results, tried after all fetches
            var androidInfoForMuxed: PlayerInfo? = nil
            var fetchIPBlockError: Error? = nil
            var parallelPlaySucceeded = false

            await withTaskGroup(of: Optional<_FO>.self) { fetchGroup in

                // 0 — TVAuth (authenticated TV client, HLS)
                if capturedHasAuth {
                    fetchGroup.addTask {
                        guard let info = try? await self.api.fetchPlayerInfoAuthenticated(videoId: video.id) else { return nil }
                        return .result(_FR(priority: 0, label: "TVAuth[\(attempt)]", info: info, skipMuxed: true))
                    }
                }

                // 1 — MWEB (no embedding restriction, no pot= required for HLS)
                fetchGroup.addTask {
                    guard let info = try? await self.api.fetchPlayerInfoMWEB(videoId: video.id) else { return nil }
                    return .result(_FR(priority: 1, label: "MWEB[\(attempt)]", info: info, skipMuxed: true))
                }

                // 2 — TVEmbedded (consume fix2/fix30 pre-fetch if available)
                let earlyTask2 = capturedEarlyTask
                fetchGroup.addTask {
                    if let et = earlyTask2, let info = await et.value {
                        return .result(_FR(priority: 2, label: "TVEmbedded[\(attempt)]", info: info, skipMuxed: true))
                    }
                    guard let info = try? await self.api.fetchPlayerInfoTVEmbedded(videoId: video.id) else { return nil }
                    return .result(_FR(priority: 2, label: "TVEmbedded[\(attempt)]", info: info, skipMuxed: true))
                }

                // 3 — WebSafari (WEB + macOS Safari UA, HLS for embedding-disabled)
                fetchGroup.addTask {
                    guard let info = try? await self.api.fetchPlayerInfoWebSafari(videoId: video.id) else { return nil }
                    return .result(_FR(priority: 3, label: "WebSafari[\(attempt)]", info: info, skipMuxed: true))
                }

                // 4 — iOS (authenticated preferred; IP-block detection)
                let hasAuth4 = capturedHasAuth
                fetchGroup.addTask {
                    do {
                        let info: PlayerInfo
                        if hasAuth4, let auth = try? await self.api.fetchPlayerInfoiOSAuthenticated(videoId: video.id) {
                            info = auth
                        } else {
                            info = try await self.api.fetchPlayerInfo(videoId: video.id)
                        }
                        return .result(_FR(priority: 4, label: "iOS[\(attempt)]", info: info, skipMuxed: true))
                    } catch {
                        if case APIError.ipBlocked = error { return .ipBlocked(error) }
                        return nil
                    }
                }

                // 5 — Android (IP-block detection; saved for muxed fallback)
                fetchGroup.addTask {
                    do {
                        let info = try await self.api.fetchPlayerInfoAndroid(videoId: video.id)
                        return .result(_FR(priority: 5, label: "Android[\(attempt)]", info: info, skipMuxed: true))
                    } catch {
                        if case APIError.ipBlocked = error { return .ipBlocked(error) }
                        return nil
                    }
                }

                // 6 — AndroidVR (CDN-exempt rqh=1, 2s composition timeout)
                fetchGroup.addTask {
                    guard let info = try? await self.api.fetchPlayerInfoAndroidVR(videoId: video.id) else { return nil }
                    return .result(_FR(priority: 6, label: "AndroidVR[\(attempt)]", info: info, skipMuxed: true))
                }

                // Process results as they arrive
                for await maybeOutcome in fetchGroup {
                    guard let outcome = maybeOutcome else { continue }
                    switch outcome {
                    case .ipBlocked(let err):
                        fetchIPBlockError = err
                        fetchGroup.cancelAll()
                        return
                    case .result(let r):
                        // Side-effects that need the concrete label/info
                        if r.label.hasPrefix("iOS[") {
                            await VideoPreloadCache.shared.store(playerInfo: r.info, for: video.id)
                        }
                        if r.label.hasPrefix("Android[") && !r.label.contains("VR") {
                            androidInfoForMuxed = r.info
                        }
                        // HLS present → try immediately; first success wins and cancels rest
                        if r.info.hlsURL != nil {
                            if await tryAllStreams(video: video, info: r.info,
                                                  label: r.label, skipMuxed: r.skipMuxed) {
                                parallelPlaySucceeded = true
                                fetchGroup.cancelAll()
                                return
                            }
                        } else {
                            // No HLS (adaptive/muxed only) → defer until all fetches done
                            pendingNonHLS.append(r)
                        }
                    }
                }
            } // end withTaskGroup

            if parallelPlaySucceeded { return }

            if let ipErr = fetchIPBlockError {
                playerLog.error("❌ IP blocked during parallel fetch (attempt \(attempt)) — \(ipErr)")
                self.error = ipErr
                return
            }
            guard !Task.isCancelled else { return }

            // Try non-HLS results (adaptive-only) in priority order.
            //
            // AndroidVR (priority=6) is skipped when a muxed fallback is available:
            // its 2s loadTracks timeout would delay muxed play with no gain when all
            // other methods already failed. Instead, muxed plays immediately and
            // backgroundQualityUpgrade retries AndroidVR (+ TVEmbedded/MWEB) in the
            // background — upgrading to higher quality while the video is already playing.
            pendingNonHLS.sort { $0.priority < $1.priority }
            let hasMuxedFallback = androidInfoForMuxed?.bestMuxedDownloadURL != nil
            playerLog.notice("[parallel fetch] attempt \(attempt): \(pendingNonHLS.count) non-HLS candidate(s) — trying in priority order (hasMuxed=\(hasMuxedFallback))")
            for candidate in pendingNonHLS {
                guard !Task.isCancelled else { return }
                // Skip AndroidVR when muxed is available — see comment above.
                if hasMuxedFallback && candidate.label.hasPrefix("AndroidVR[") {
                    playerLog.notice("[parallel fetch] skipping \(candidate.label) (muxed available — background upgrade will retry)")
                    continue
                }
                if await tryAllStreams(video: video, info: candidate.info,
                                      label: candidate.label, skipMuxed: candidate.skipMuxed) {
                    return
                }
            }

            guard !Task.isCancelled else { return }

            // --- Muxed direct MP4 (360p last resort) ---
            // Only reached when ALL HLS + adaptive attempts above failed.
            // On success: schedule backgroundQualityUpgrade to try TVEmbedded/MWEB HLS
            // and AndroidVR adaptive in the background while the video is already playing.
            if let androidInfo = androidInfoForMuxed, androidInfo.bestMuxedDownloadURL != nil {
                isLoading = true
                retryStatusMessage = "Using fallback stream\u{2026}"
                playerLog.notice("[Android[\(attempt)]] All adaptive failed — trying muxed fallback")
                if await tryAllStreams(video: video, info: androidInfo,
                                      label: "Android[\(attempt)]/muxed") {
                    // Muxed playing — attempt quality upgrade in background while user watches.
                    let upgradeVideo = video
                    Task { [weak self] in await self?.backgroundQualityUpgrade(video: upgradeVideo) }
                    return
                }
                // Android muxed failed (possibly AVF -11828 "Cannot Open" on SABR/long-video URLs,
                // or URL expiry). Try the Web/iOS client muxed URL as a final rescue path.
                // fetchPlayerInfo() returns iOS-client playerInfo whose muxed URL is
                // CDN-signed with standard MP4 headers, avoiding the TVHTML5 SABR issue.
                playerLog.notice("[Android[\(attempt)]] Muxed failed — trying Web client muxed fallback")
                do {
                    let webInfo = try await api.fetchPlayerInfo(videoId: video.id)
                    if webInfo.bestMuxedDownloadURL != nil {
                        if await tryAllStreams(video: video, info: webInfo,
                                              label: "Web[\(attempt)]/muxed") {
                            return
                        }
                    }
                } catch {
                    playerLog.error("Web client muxed fallback fetch failed (attempt \(attempt)): \(error)")
                }
            }
        }

        guard !Task.isCancelled else { return }
        playerLog.error("❌ All 3 retry attempts exhausted for \(video.id)")
        error = APIError.unavailable("Unable to play this video")
        isLoading = false
    }

    // MARK: - Race helpers (called from withTaskGroup in exhaustiveRetry)

    /// Path A of the exhaustiveRetry race: BotGuardWV adaptive / proxy HLS path.
    /// Waits up to 6 s for BotGuard to mint a token, then tries WEB/iOS/Android adaptive.
    /// Returns `true` if a stream reached `readyToPlay`.
    #if canImport(WebKit)
    func racePathA(video: Video) async -> Bool {
        if !BotGuardWebViewRunner.shared.isReady {
            playerLog.notice("[BotGuardWV] waiting up to 6 s for minted token (race Path A)…")
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await BotGuardWebViewRunner.shared.prepare(for: video.id) }
                group.addTask { try? await Task.sleep(nanoseconds: 6_000_000_000) }
                _ = await group.next()
                group.cancelAll()
            }
        }
        guard !Task.isCancelled else { return false }
        guard BotGuardWebViewRunner.shared.isReady else {
            playerLog.notice("[BotGuardWV] not ready after 6 s wait — Path A done")
            return false
        }
        // fix9: SAPISID recovery from WKWebView propagated cookies.
        // BotGuardWebViewRunner.prepare() calls propagateWebViewCookies() which copies
        // youtube.com cookies (including SAPISID) from the WKWebView session into
        // HTTPCookieStorage.shared. On real device, the WKWebView is signed into YouTube
        // (default WKWebsiteDataStore shares cookies with the signed-in browser session)
        // so SAPISID is now in HTTPCookieStorage.shared even when AuthService couldn't get
        // it via OAuthLogin/Multilogin (openid scope missing / old token).
        // Recovering SAPISID here lets postWebSafari use SAPISIDHASH auth → YouTube returns
        // rqh=0 adaptive URLs → CDN probe passes → Path A wins instead of waiting for Path B.
        if await !api.hasSAPISID,
           let webSAPISID = HTTPCookieStorage.shared
               .cookies(for: URL(string: "https://www.youtube.com")!)?.first(where: { $0.name == "SAPISID" })?.value {
            await api.setSAPISID(webSAPISID)
            playerLog.notice("[BotGuardWV] fix9: recovered SAPISID from WKWebView propagated cookies (len=\(webSAPISID.count))")
        }
        let webVD = BotGuardWebViewRunner.shared.webVisitorData
        // fix8: use webVD as the mintToken identifier so the minted pot= token is bound
        // to the WEB session visitorData — the same VD that will be sent in
        // fetchPlayerInfoWebWithPoToken's context.client.visitorData and X-Goog-Visitor-Id.
        // Previously, api.currentVisitorData() (iOS/TV session VD) was used as identifier,
        // causing apiVD ≠ webVD — the CDN tied the streaming URLs to the iOS session but
        // our pot= token was minted for the WEB session, causing HTTP 403 on every segment.
        // If webVD is empty (BotGuard warm-up hasn't fetched guide yet), fall back to apiVD.
        let apiVD = await api.currentVisitorData() ?? ""
        let identifier = webVD.isEmpty ? apiVD : webVD
        guard let mintedToken = await BotGuardWebViewRunner.shared.mintToken(identifier: identifier) else {
            playerLog.notice("[BotGuardWV] ⚠️ mintToken returned nil — Path A done")
            return false
        }
        await api.storeExternalPoToken(mintedToken, for: video.id)
        hasMintedPoToken = true
        playerLog.notice("[BotGuardWV] ✅ minted token (len=\(mintedToken.count) webVD.len=\(webVD.count) apiVD.len=\(apiVD.count) match=\(apiVD == webVD)) — Path A racing WKWebView HLS")
        guard !Task.isCancelled else { return false }
        do {
            let webInfo = try await api.fetchPlayerInfoWebWithPoToken(
                videoId: video.id, visitorData: webVD.isEmpty ? nil : webVD
            )
            let probeURL = webInfo.formats.first(where: {
                $0.mimeType.hasPrefix("video/mp4") && $0.url != nil
            })?.url
            var webProbeStatus: Int? = nil
            if let probeURL {
                let hasRqh = probeURL.absoluteString.contains("rqh=1")
                // Only run the CDN HEAD probe when the URL has rqh=1. The probe is only
                // used to skip tryAllStreams on 403. For non-rqh=1 URLs the CDN serves
                // the stream directly — skipping the probe removes one network round-trip
                // (~0.5–1s) from Path A, helping it win the race against Path B.
                if hasRqh {
                    var req = URLRequest(url: probeURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 1)
                    req.httpMethod = "HEAD"
                    let hasPot = probeURL.absoluteString.contains("pot=")
                    if let (_, resp) = try? await URLSession.shared.data(for: req),
                       let http = resp as? HTTPURLResponse {
                        webProbeStatus = http.statusCode
                        playerLog.notice("[BotGuardWV/WEB probe] CDN HEAD: HTTP \(http.statusCode) — pot=\(hasPot ? "YES" : "NO") rqh=1")
                    }
                } else {
                    playerLog.notice("[BotGuardWV/WEB probe] skipping CDN probe — no rqh=1, proceeding directly")
                }
            }
            guard !Task.isCancelled else { return false }
            if webProbeStatus != 403,
               await tryAllStreams(video: video, info: webInfo, label: "BotGuardWV", skipMuxed: true) {
                playerLog.notice("[BotGuardWV] ✅ Path A won — WEB adaptive")
                return true
            } else if webProbeStatus == 403 {
                playerLog.notice("[BotGuardWV] WEB probe 403 — skipping tryAllStreams + proxy HLS in Path A")
            }
            if webProbeStatus != 403, let hlsURL = webInfo.hlsURL, let proxyURL = hlsURL.proxyURL {
                guard !Task.isCancelled else { return false }
                playerLog.notice("[BotGuardWV] trying HLS via pot= proxy (Path A)")
                let safariUA = InnerTubeClients.WebSafari.userAgent
                let potProxyLoader = YTHLSProxyLoader(ua: safariUA, poToken: mintedToken)
                let asset = AVURLAsset(url: proxyURL)
                asset.resourceLoader.setDelegate(potProxyLoader, queue: DispatchQueue.global(qos: .userInitiated))
                webHLSProxyLoader = potProxyLoader
                let proxyItem = AVPlayerItem(asset: asset)
                proxyItem.audioTimePitchAlgorithm = .spectral
                proxyItem.preferredForwardBufferDuration = 0.5
                player.replaceCurrentItem(with: proxyItem)
                itemObserverTask?.cancel()
                for await st in proxyItem.statusStream {
                    guard !Task.isCancelled else { return false }
                    switch st {
                    case .readyToPlay:
                        playerLog.notice("[benchmark] readyToPlay — BotGuardWV/proxy-HLS — videoId=\(video.id)")
                        timeToPlayMs = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1000)
                        if timeToPlayMs > 4_000 {
                            CrashlyticsLogger.recordSlowVideoLoad(
                                videoId: video.id,
                                elapsedMs: timeToPlayMs,
                                streamType: "BotGuardWV/proxyHLS",
                                hasError: false
                            )
                        }
                        playerLog.notice("[BotGuardWV] ✅ Path A won — proxy HLS")
                        return true
                    case .failed:
                        playerLog.notice("[BotGuardWV] ⚠️ proxy HLS failed: \(proxyItem.error?.localizedDescription ?? "unknown")")
                        break
                    default:
                        continue
                    }
                    break
                }
            }
            guard !Task.isCancelled, webProbeStatus != 403 else { return false }
            playerLog.notice("[BotGuardWV] trying iOS adaptive with WAA minted token (Path A)")
            do {
                let iosInfo = try await api.fetchPlayerInfo(videoId: video.id)
                if await tryAllStreams(video: video, info: iosInfo, label: "BotGuardWV", skipMuxed: true) {
                    playerLog.notice("[BotGuardWV] ✅ Path A won — iOS adaptive")
                    return true
                }
            } catch {
                playerLog.notice("[BotGuardWV] ⚠️ iOS adaptive fetch failed: \(error)")
            }
            guard !Task.isCancelled else { return false }
            playerLog.notice("[BotGuardWV] trying Android adaptive with WAA minted token (Path A)")
            do {
                let androidInfo = try await api.fetchPlayerInfoAndroid(videoId: video.id)
                if await tryAllStreams(video: video, info: androidInfo, label: "BotGuardWV", skipMuxed: true) {
                    playerLog.notice("[BotGuardWV] ✅ Path A won — Android adaptive")
                    return true
                }
            } catch {
                playerLog.notice("[BotGuardWV] ⚠️ Android adaptive fetch failed: \(error)")
            }
        } catch {
            playerLog.notice("[BotGuardWV] ⚠️ WEB client fetch failed: \(error)")
        }
        playerLog.notice("[BotGuardWV] Path A exhausted — all BotGuardWV attempts failed")
        return false
    }
    #endif // canImport(WebKit)

    /// Path B of the exhaustiveRetry race: early WKWebView HLS path.
    /// Awaits the `wkHLSEarlyTask` started in `loadAsync` (already in-flight).
    /// Returns `true` if a stream reached `readyToPlay`.
    #if canImport(WebKit)
    func racePathB(video: Video) async -> Bool {
        guard let earlyTask = wkHLSEarlyTask else {
            playerLog.notice("⚠️ [webView] no earlyTask — Path B done")
            return false
        }
        playerLog.notice("⚠️ [webView] Path B awaiting early WKWebView HLS task…")
        guard let url = await earlyTask.value, !Task.isCancelled else {
            playerLog.notice("⚠️ [webView] earlyTask returned nil or cancelled — Path B done")
            return false
        }
        // fix20: Capture nSolver and poToken after earlyTask completes — the fresh
        // extraction has the up-to-date values (extractedPoToken is set at end of extractHLSURL).
        let nSolver = YouTubeWebViewHLSExtractor.shared.extractedNSolver
        let capturedPoToken = YouTubeWebViewHLSExtractor.shared.extractedPoToken
        if let pot = capturedPoToken {
            await api.storeExternalPoToken(pot, for: video.id)
            playerLog.notice("[webView] pot= token stored from WKWebView (\(pot.count) chars)")
        }
        let nInfo = nSolver.map { "\($0.unsolved)→\($0.solved)" } ?? "nil"
        playerLog.notice("⚠️ [webView] Path B got hlsManifestUrl — nSolver=\(nInfo as NSString)")
        let won = await tryWebViewHLS(url, nSolver: nSolver, poToken: capturedPoToken, for: video)
        if won { playerLog.notice("✅ [webView] Path B won — WKWebView HLS") }
        return won
    }
    #endif // canImport(WebKit)

    /// Path C of the exhaustiveRetry race: Android VR (Oculus Quest) adaptive path.
    /// CDN-exempt from rqh=1 / pot= token requirements. Runs concurrently with Path A and B.
    /// Returns `true` if adaptive composition reached `readyToPlay`.
    func racePathC(video: Video) async -> Bool {
        guard !Task.isCancelled else { return false }
        do {
            let vrInfo = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)
            if await tryAllStreams(video: video, info: vrInfo, label: "AndroidVR/race", skipMuxed: true) {
                playerLog.notice("[AndroidVR] ✅ Path C won — AndroidVR adaptive composition")
                return true
            }
        } catch {
            playerLog.notice("[AndroidVR] ⚠️ Path C fetch failed: \(error)")
        }
        playerLog.notice("[AndroidVR] Path C done — AndroidVR adaptive failed")
        return false
    }

    /// Background quality upgrade after AndroidVR wins the race at low quality (maxH < 480).
    ///
    /// Called from the `raceWon / case 2` block when AndroidVR composes at e.g. 240p for
    /// rqh=1 worst-case videos. Fires after a 700 ms stabilisation delay so the initial
    /// `readyToPlay` playback is already running. Tries:
    ///   1. TVEmbedded HLS (WEB_EMBEDDED_PLAYER — HLS for most embeddable videos)
    ///   2. MWEB HLS (m.youtube.com — no pot= for HLS, wider coverage than TVEmbedded)
    ///
    /// On success, replaces the current AVPlayerItem at the current playback position so
    /// the user sees no gap (position is saved to `savedPositionToRestore` just before
    /// calling `attemptURL`, and consumed by `attemptURL`'s `.readyToPlay` handler).
    /// On failure, stays on the AndroidVR quality silently — no error shown to the user.
    func backgroundQualityUpgrade(video: Video) async {
        // Stabilisation delay — let readyToPlay fire and playback begin before replacing the item.
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled else { return }
        // Bail if the user navigated to a different video while we were waiting.
        guard currentVideo?.id == video.id else {
            playerLog.notice("[VR→HLS/upgrade] video changed — cancelling quality upgrade")
            return
        }

        // 1. Try TVEmbedded HLS (WEB_EMBEDDED_PLAYER, nameID=56).
        do {
            let tvEmbedInfo = try await api.fetchPlayerInfoTVEmbedded(videoId: video.id)
            guard !Task.isCancelled, currentVideo?.id == video.id else { return }
            if let hlsURL = tvEmbedInfo.hlsURL {
                playerLog.notice("[VR→HLS/upgrade] TVEmbedded HLS available — upgrading from AndroidVR quality")
                // Capture position right before replacement so the stale window is minimal.
                let pos = currentTime
                if pos > 0.5 { savedPositionToRestore = pos }
                if await attemptURL(hlsURL, for: video, info: tvEmbedInfo, label: "VR→HLS/upgrade/TVEmbed") {
                    playerLog.notice("[VR→HLS/upgrade] ✅ quality upgrade via TVEmbedded HLS complete")
                    return
                }
                // attemptURL returned false — clear the now-stale saved position.
                savedPositionToRestore = nil
            }
        } catch {
            playerLog.notice("[VR→HLS/upgrade] TVEmbedded fetch failed: \(error)")
        }

        guard !Task.isCancelled, currentVideo?.id == video.id else { return }

        // 2. Try MWEB HLS (m.youtube.com — no pot= required for HLS, wider coverage).
        do {
            let mwebInfo = try await api.fetchPlayerInfoMWEB(videoId: video.id)
            guard !Task.isCancelled, currentVideo?.id == video.id else { return }
            if let hlsURL = mwebInfo.hlsURL {
                playerLog.notice("[VR→HLS/upgrade] MWEB HLS available — upgrading from AndroidVR quality")
                let pos = currentTime
                if pos > 0.5 { savedPositionToRestore = pos }
                if await attemptURL(hlsURL, for: video, info: mwebInfo, label: "VR→HLS/upgrade/MWEB") {
                    playerLog.notice("[VR→HLS/upgrade] ✅ quality upgrade via MWEB HLS complete")
                    return
                }
                savedPositionToRestore = nil
            }
        } catch {
            playerLog.notice("[VR→HLS/upgrade] MWEB fetch failed: \(error)")
        }

        // 3. Try AndroidVR adaptive (CDN-exempt rqh=1, no HLS needed).
        // Useful when muxed (360p) is playing and AndroidVR can deliver 1080p+ via adaptive
        // composition. The 2s loadTracks timeout applies — if CDN stalls we bail quickly.
        // Position is saved so the upgraded stream resumes from current playback point.
        //
        // On failure: keep availableFormats = AndroidVR's format list (so the quality picker
        // shows e.g. 1080p/720p options). Also restore isMuxedFallback = true because
        // tryAllStreams() unconditionally sets it to false via the label check. Without this
        // restoration, tapping a quality routes through reloadDASHItem (silent rqh=1 failure)
        // instead of triggering retryWith403Recovery → exhaustiveRetry.
        guard !Task.isCancelled, currentVideo?.id == video.id else { return }
        do {
            let vrInfo = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)
            guard !Task.isCancelled, currentVideo?.id == video.id else { return }
            let vrPos = currentTime
            if vrPos > 0.5 { savedPositionToRestore = vrPos }
            if await tryAllStreams(video: video, info: vrInfo,
                                  label: "muxed→upgrade/AndroidVR", skipMuxed: true) {
                playerLog.notice("[upgrade] ✅ quality upgrade via AndroidVR adaptive complete")
                return
            }
            savedPositionToRestore = nil
            // Upgrade failed: availableFormats now has AndroidVR's list (set by attemptComposition)
            // which is correct — user can see quality options and tap to trigger a retry.
            // Restore isMuxedFallback so quality taps route to retryWith403Recovery.
            qualityManager.isMuxedFallback = true
            playerLog.notice("[upgrade] AndroidVR adaptive failed — isMuxedFallback restored, \(availableFormats.count) formats visible in picker")
        } catch {
            playerLog.notice("[upgrade] AndroidVR fetch failed: \(error)")
        }

        playerLog.notice("[upgrade] no quality upgrade available — staying on muxed stream")
    }

    /// Kept for the `PlaybackQualityManagerDelegate` protocol.
    /// Quality-switch 403 errors start a fresh 3-attempt exhaustive cycle.
    func retryWith403Recovery(video: Video, originalError: Error?) async {
        playerLog.notice("403 recovery (quality switch) — exhaustive retry for \(video.id)")
        // Capture the current playback position so the new stream resumes from here.
        // Without this, attemptComposition / attemptURL have no seekTo target and the
        // new item starts from t=0 — causing the position-preservation assertion to fail.
        let pos = currentTime
        if pos > 0 {
            savedPositionToRestore = pos
        }
        retryAttempts = 0
        await exhaustiveRetry(video: video, originalError: originalError)
    }

    // MARK: - Stream Exhaustion

    /// Tries HLS → adaptive composition → (optionally) muxed direct from one PlayerInfo.
    /// Returns true if any stream starts playing successfully.
    /// - Parameter skipMuxed: When `true`, the muxed direct-MP4 fallback is skipped so that
    ///   the caller can try higher-priority clients before accepting the 360p muxed last-resort.
    func tryAllStreams(video: Video, info: PlayerInfo, label: String,
                        skipMuxed: Bool = false) async -> Bool {
        let hasHLS = info.hlsURL != nil
        let hasDASH = info.dashURL != nil
        let hasAdaptiveVideo = qualityCapVideoURL(from: info.formats) != nil
        let hasAdaptiveAudio = info.bestAdaptiveAudioURL != nil
        let hasMuxed = info.bestMuxedDownloadURL != nil
        // Diagnostic: show first adaptive video URL prefix to detect SABR (c=TVHTML5) vs standard
        let firstAdaptiveURL = info.formats.first(where: {
            $0.mimeType.hasPrefix("video/mp4") && !$0.mimeType.contains(", ") && $0.url != nil
        })?.url?.absoluteString.prefix(200) ?? "none"
        playerLog.notice("[\(label)] streams: HLS=\(hasHLS) DASH=\(hasDASH) adaptiveVideo=\(hasAdaptiveVideo) adaptiveAudio=\(hasAdaptiveAudio) muxed=\(hasMuxed) skipMuxed=\(skipMuxed) firstAdaptiveURL=\(firstAdaptiveURL)")

        // 1. HLS manifest — best quality, native AVPlayer ABR, alternate audio renditions
        if let hlsURL = info.hlsURL {
            playerLog.notice("[\(label)] Trying HLS")
            if await attemptURL(hlsURL, for: video, info: info, label: "\(label)/HLS") { return true }
            playerLog.notice("[\(label)] HLS failed — trying adaptive composition")
        }

        // 2. Adaptive composition — video-only + audio-only; avoids muxed CDN pot restrictions
        if let videoURL = qualityCapVideoURL(from: info.formats),
           let audioURL = info.bestAdaptiveAudioURL {
            // Guard: if every adaptive video URL is SABR (c=TVHTML5), AVURLAsset.loadTracks
            // will stall for 60 s then return -11828 "Cannot Open". Skip composition entirely
            // and let exhaustiveRetry's WKWebView path handle the video instead.
            if info.containsSabrFormats {
                playerLog.notice("[\(label)] All adaptive video URLs are SABR (c=TVHTML5) — skipping loadTracks stall, falling through")
            // Guard: if every adaptive video URL has rqh=1, AVURLAsset.loadTracks stalls
            // for ~8 s on the CDN's byte-range probe because rqh=1 requires CDN auth that
            // URLSession cannot provide (same class of stall as SABR but shorter timeout).
            // Skip composition and route to WKWebView HLS (spc=-authenticated).
            // Exception: if a WKWebView-extracted pot= token is available (Option B), the
            // adaptive URLs have already had &pot=<token> appended via applyingPoToken(),
            // so CDN auth may succeed — attempt composition before falling through.
            } else if info.containsRqhAdaptiveFormats {
                let hasPot = await api.hasPoToken(for: video.id)
                // ANDROID_VR is exempt from CDN rqh=1 enforcement (no GVS_PO_TOKEN_POLICY
                // defined for android_vr per yt-dlp source). attemptComposition also has
                // this exemption via isAndroidVR, but it was unreachable from here because
                // this guard returned early before calling it. Allow VR through directly.
                let isAndroidVRLabel = label.contains("AndroidVR") || label.contains("ANDROID_VR")
                if hasPot || isAndroidVRLabel {
                    #if os(tvOS)
                    // fix2: Pre-fetch TVEmbedded concurrently while AndroidVR rqh=1 composition
                    // times out (2s on tvOS). By the time the timeout fires and exhaustiveRetry
                    // reaches Phase 1, the result is ready — eliminating the sequential ~0.5s fetch.
                    // Fire for all AndroidVR attempts regardless of hasPot: the pot= token doesn't
                    // prevent the CDN from enforcing rqh=1 at the segment level (only firstByte
                    // probe returns 206; actual segments still reject with rqh=1).
                    if isAndroidVRLabel, tvEmbeddedEarlyTask == nil {
                        let prefetchVideoId = video.id
                        tvEmbeddedEarlyTask = Task { [weak self] in
                            guard let self else { return nil }
                            return try? await self.api.fetchPlayerInfoTVEmbedded(videoId: prefetchVideoId)
                        }
                        playerLog.notice("[\(label)] fix2: started TVEmbedded early pre-fetch alongside rqh=1 timeout")
                    }
                    #endif
                    playerLog.notice("[\(label)] rqh=1 but \(hasPot ? "pot= token available" : "ANDROID_VR exempt") — attempting adaptive composition")
                    if await attemptComposition(videoURL: videoURL, audioURL: audioURL,
                                                for: video, info: info, label: label) { return true }
                    playerLog.notice("[\(label)] adaptive composition with pot= failed — falling through")
                } else {
                    playerLog.notice("[\(label)] All adaptive video URLs are rqh=1 — skipping 8 s loadTracks stall, falling through")
                }
            } else {
                playerLog.notice("[\(label)] Trying adaptive composition")
                if await attemptComposition(videoURL: videoURL, audioURL: audioURL,
                                            for: video, info: info, label: label) {
                    return true
                }
                // A background prefetch may have stored an HLS URL in the cache while adaptive
                // was running (confirmed in logs: hls=true stored mid-retry for LSMQ3U1Thzw).
                // Check before falling through to muxed — HLS gives us multi-audio track support.
                let freshCachedInfo = await VideoPreloadCache.shared.consume(videoId: video.id).playerInfo
                if let freshHLSURL = freshCachedInfo?.hlsURL, freshHLSURL != info.hlsURL {
                    playerLog.notice("[\(label)] HLS URL appeared in cache after adaptive failed — trying HLS")
                    if await attemptURL(freshHLSURL, for: video, info: freshCachedInfo!,
                                        label: "\(label)/HLS-late") { return true }
                }
                playerLog.notice("[\(label)] Adaptive composition failed — trying muxed")
            }
        }

        // 3. Muxed direct MP4 (itag=18, 360p — last resort, skipped when skipMuxed=true)
        if !skipMuxed, let muxedURL = info.bestMuxedDownloadURL {
            // Guard: TVHTML5 SABR-protocol URLs serve binary data, not a standard MP4 container.
            // AVPlayer returns -11828 (AVFoundationErrorDomain "Cannot Open") for these.
            if muxedURL.absoluteString.contains("c=TVHTML5") {
                playerLog.notice("[\(label)] Skipping SABR muxed URL (c=TVHTML5) — not a playable MP4")
            } else {
                playerLog.notice("[\(label)] Trying muxed")
                let muxedItag = muxedURL.absoluteString
                    .components(separatedBy: "&")
                    .first(where: { $0.contains("itag=") })
                    .flatMap { $0.components(separatedBy: "=").last } ?? "?"
                let muxedBitrate = info.formats.first(where: { $0.url == muxedURL })?.bitrate.map { "\($0/1000)kbps" } ?? "?"
                playerLog.notice("[\(label)] muxed candidate: itag=\(muxedItag) bitrate=\(muxedBitrate) url=\(muxedURL.absoluteString.prefix(100))")
                if await attemptURL(muxedURL, for: video, info: info, label: "\(label)/muxed") { return true }
                playerLog.notice("[\(label)] Muxed failed — no more alternatives for this client")
            }
        }

        return false
    }

    // MARK: - Attempt Helpers

    /// Tries a single URL in AVPlayer. Returns true if `.readyToPlay` is received.
    /// `statusStream` finishes after `.readyToPlay` or `.failed`, making it safe to await inline.
    private func attemptURL(_ url: URL, for video: Video, info: PlayerInfo, label: String) async -> Bool {
        playerLog.notice("[\(label)]: \(url.absoluteString.prefix(120))")

        playerInfo = info
        let newFormats = Self.deduplicatedVideoFormats(info.formats)
        // Never reduce quality options for adaptive/HLS streams — preserve the richest set seen.
        // Exception: muxed fallback (label contains "/muxed") always resets availableFormats to
        // the muxed-only formats. This prevents stale rqh=1-blocked adaptive formats from
        // appearing in the quality picker when they can never actually play.
        let maxCurrentHeight = availableFormats.map(\.height).max() ?? 0
        let maxNewHeight = newFormats.map(\.height).max() ?? 0
        let isMuxedFallback = label.contains("/muxed")
        if isMuxedFallback || newFormats.count > availableFormats.count || maxNewHeight > maxCurrentHeight || availableFormats.isEmpty {
            availableFormats = newFormats
        }
        playerLog.notice("[\(label)] availableFormats after dedup: input=\(info.formats.count) output=\(newFormats.count) kept=\(availableFormats.count) maxH=\(availableFormats.map(\.height).max() ?? 0)")
        availableCaptions = info.captionTracks
        autoApplyCaptionPreference(tracks: info.captionTracks)

        var effectiveURL = url
        var applyHLSHints = false
        if let hlsURL = info.hlsURL, url == hlsURL {
            let videoId = video.id
            let variantURLs: [Int: URL]
            if let cached = PlaybackQualityManager.cachedHLSVariants(for: videoId) {
                playerLog.notice("[\(label)] HLS: using cached manifest for \(videoId) variantCount=\(cached.count)")
                variantURLs = cached
            } else {
                variantURLs = await fetchHLSVariantURLs(url: hlsURL)
                if !variantURLs.isEmpty {
                    PlaybackQualityManager.cacheHLSVariants(variantURLs, for: videoId)
                }
            }
            playerLog.notice("[\(label)] HLS: hlsURL=yes variantCount=\(variantURLs.count) preferredQuality=\(settings.preferredQuality)")
            if !variantURLs.isEmpty {
                hlsVariantURLs = variantURLs
                availableFormats = availableFormats.filter { variantURLs.keys.contains($0.height) }
                // Use a variant playlist URL directly rather than the master manifest URL.
                // The master manifest (hls_variant) stalls AVPlayer on manifest.googlevideo.com
                // because it requires session-level auth that AVPlayer's isolated network stack
                // cannot provide. Variant playlist URLs (hls_playlist) are directly downloadable
                // — yt-dlp confirms 720p in 13 s, 1080p in 29 s for the same video.
                let preferredMaxH = settings.preferredQuality == .auto ? nil : settings.preferredQuality.maxHeight
                let chosen = preferredMaxH
                    .flatMap { h in variantURLs.filter { $0.key <= h }.max(by: { $0.key < $1.key }) }
                    ?? variantURLs.max(by: { $0.key < $1.key })
                if let chosen {
                    let variantURL = chosen.value
                    effectiveURL = variantURL
                    playerLog.notice("[\(label)] HLS: selected variant \(chosen.key)p")
                    // DIAGNOSTIC D-14: probe variant playlist + first segment before handing to AVPlayer.
                    // Ephemeral session → no cookies, no shared state.
                    // 200 → URL is publicly accessible; 403 → YouTube session (SAPISID) required.
                    // Also logs first segment URL to determine if rqh=1 is enforced at segment level.
                    let capturedLabel = label
                    let capturedAuthToken = currentAuthToken
                    Task.detached {
                        var diagReq = URLRequest(url: variantURL)
                        diagReq.setValue(
                            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
                            forHTTPHeaderField: "User-Agent"
                        )
                        diagReq.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                        diagReq.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
                        diagReq.timeoutInterval = 8
                        guard let (diagData, diagResp) = try? await URLSession(configuration: .ephemeral).data(for: diagReq),
                              let http = diagResp as? HTTPURLResponse else {
                            playerLog.notice("[\(capturedLabel)] D-14 HLS variant probe: fail/timeout (no-cookie/Safari UA)")
                            return
                        }
                        let playlistText = String(data: diagData, encoding: .utf8) ?? ""
                        // Find first absolute segment URL (https:// line not starting with #)
                        let firstSegURL = playlistText.components(separatedBy: "\n")
                            .first { $0.hasPrefix("https://") } ?? "(no absolute URL found)"
                        // rqh=1 appears as /rqh/1/ path-style in HLS URLs (not ?rqh=1 query-style)
                        let hasRqh = firstSegURL.contains("/rqh/1") || firstSegURL.contains("rqh=1") || firstSegURL.contains("rqh%3D1")
                        playerLog.notice("[\(capturedLabel)] D-14 HLS variant probe: HTTP \(http.statusCode) bytes=\(diagData.count) firstSeg_rqh=\(hasRqh) firstSeg=\(firstSegURL.prefix(600))")
                        // If no absolute URL, log the first non-comment line to see relative segment format
                        if !firstSegURL.hasPrefix("https://") {
                            let firstNonComment = playlistText.components(separatedBy: "\n")
                                .first { !$0.hasPrefix("#") && !$0.isEmpty } ?? "(empty)"
                            playerLog.notice("[\(capturedLabel)] D-14 first non-comment line: \(firstNonComment.prefix(200))")
                        }
                        // Also test first segment URL (if absolute) to see if segments need auth
                        if firstSegURL.hasPrefix("https://"), let segURL = URL(string: firstSegURL) {
                            var segReq = URLRequest(url: segURL)
                            segReq.setValue(
                                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
                                forHTTPHeaderField: "User-Agent"
                            )
                            segReq.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                            segReq.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
                            segReq.timeoutInterval = 8
                            // Range request — just the first byte to test access
                            segReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                            if let (_, segResp) = try? await URLSession(configuration: .ephemeral).data(for: segReq),
                               let segHttp = segResp as? HTTPURLResponse {
                                playerLog.notice("[\(capturedLabel)] D-14 segment probe (Safari UA/no-cookie): HTTP \(segHttp.statusCode) rqh=\(hasRqh)")
                            } else {
                                playerLog.notice("[\(capturedLabel)] D-14 segment probe: fail/timeout")
                            }

                            // D-15: probe same segment WITH Bearer token — determines if
                            // OAuth2 Bearer satisfies rqh=1 for HLS path-style segments.
                            // If this returns 200/206, resource-loader interception is viable.
                            if let bearerToken = capturedAuthToken, hasRqh {
                                var segBearerReq = URLRequest(url: segURL)
                                segBearerReq.setValue(
                                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
                                    forHTTPHeaderField: "User-Agent"
                                )
                                segBearerReq.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                                segBearerReq.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
                                segBearerReq.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                                segBearerReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                                segBearerReq.timeoutInterval = 8
                                if let (_, segResp2) = try? await URLSession(configuration: .ephemeral).data(for: segBearerReq),
                                   let segHttp2 = segResp2 as? HTTPURLResponse {
                                    playerLog.notice("[\(capturedLabel)] D-15 segment probe (Safari UA+Bearer): HTTP \(segHttp2.statusCode) rqh=\(hasRqh)")
                                } else {
                                    playerLog.notice("[\(capturedLabel)] D-15 segment probe (Bearer): fail/timeout")
                                }
                            }
                        }
                    }
                }
            } else {
                playerLog.notice("[\(label)] HLS manifest fetch returned 0 variants — using master as-is")
            }
            qualityManager.setSelectedFormatForCurrentPreference()
            applyHLSHints = true
        } else {
            playerLog.notice("[\(label)] non-HLS URL — no EXT-X-MEDIA, audio tracks will be unavailable")
        }

        lastAttemptedStreamURL = effectiveURL
        let isHLSManifest = label.contains("/HLS")
        // WebSafari HLS variant playlists are served from manifest.googlevideo.com and
        // signed for a browser WEB client. The CDN checks that the requesting UA matches
        // a web browser; sending the iOS YouTube UA returns 403. Use the Safari macOS UA
        // for WebSafari HLS, and Origin + Referer for all HLS (browser-style headers).
        let hlsUA: String
        if isHLSManifest && label.contains("WebSafari") {
            hlsUA = InnerTubeClients.WebSafari.userAgent
        } else {
            hlsUA = "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)"
        }
        var hlsHeaders: [String: String] = ["User-Agent": hlsUA]
        if isHLSManifest {
            hlsHeaders["Origin"] = "https://www.youtube.com"
            hlsHeaders["Referer"] = "https://www.youtube.com/"
        }

        let item: AVPlayerItem
        if applyHLSHints {
            // Use AVURLAsset with custom UA headers for HLS — AVFoundation handles
            // HLS natively and sends our YouTube UA for ALL requests (manifest +
            // segments). AetherEngine cannot be used here because FFmpegBuild has
            // no HTTP protocol handler, so segment sub-requests inside HLS always
            // fail regardless of the io_open callback approach.
            let uaOpts: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": hlsHeaders]
            let asset = AVURLAsset(url: effectiveURL, options: uaOpts)
            playerLog.notice("[\(label)] HLS via AVURLAsset (native stack) url=\(effectiveURL.lastPathComponent)")
            item = AVPlayerItem(asset: asset)
        } else {
            // Non-HLS (muxed / DASH): direct AVURLAsset with iOS UA headers.
            let uaOpts: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": hlsHeaders]
            item = AVPlayerItem(asset: AVURLAsset(url: effectiveURL, options: uaOpts))
        }
        item.audioTimePitchAlgorithm = .spectral
        // Reduce startup latency: begin playback after 0.5 s of buffered content
        // (matches the primary HLS path). Reset to system default after readyToPlay.
        item.preferredForwardBufferDuration = 0.5
        Task { [weak item] in
            try? await Task.sleep(for: .seconds(5))
            item?.preferredForwardBufferDuration = 0
        }
        if applyHLSHints {
            if settings.preferredQuality != .auto, let maxH = settings.preferredQuality.maxHeight {
                item.preferredMaximumResolution = CGSize(width: CGFloat(maxH) * 4, height: CGFloat(maxH))
                item.preferredPeakBitRate = peakBitRate(for: maxH)
                playerLog.notice("[\(label)] HLS ABR hints: maxH=\(maxH)p peakBitRate=\(peakBitRate(for: maxH) / 1_000_000)Mbps (master URL preserved)")
            } else {
                // Auto: remove all constraints so AVPlayer picks the best available variant.
                item.preferredMaximumResolution = .zero
                item.preferredPeakBitRate = 0
                playerLog.notice("[\(label)] HLS ABR hints cleared (Auto quality, unconstrained)")
            }
        }
        // fix235: Guard cancellation and video identity immediately before touching the player.
        // Covers adaptive/muxed paths: a stale exhaustiveRetry (cancelled by load() or stop())
        // must not swap the AVPlayerItem under a correctly-playing video.
        guard !Task.isCancelled, currentVideo?.id == video.id else {
            playerLog.notice("⚠️ [\(label)] fix235: task cancelled or video changed (current=\(currentVideo?.id ?? "nil") expected=\(video.id)) — aborting replaceCurrentItem")
            return false
        }
        player.replaceCurrentItem(with: item)
        itemObserverTask?.cancel()

        // Some unreachable CDN URLs remain `.unknown` indefinitely on iOS 26.
        // Race the terminal status against a timeout so exhaustiveRetry can move on
        // to the next candidate instead of leaving the loading spinner up forever.
        let (statusRace, statusContinuation) = AsyncStream<AVPlayerItem.Status?>.makeStream()
        let statusTask = Task { @MainActor in
            for await status in item.statusStream {
                guard status != .unknown else { continue }
                statusContinuation.yield(status)
                statusContinuation.finish()
                return
            }
            statusContinuation.yield(nil)
            statusContinuation.finish()
        }
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            statusContinuation.yield(nil)
            statusContinuation.finish()
        }
        let terminalStatus = await statusRace.first(where: { @Sendable _ in true }) ?? nil
        statusTask.cancel()
        timeoutTask.cancel()

        guard let terminalStatus else {
            playerLog.error("❌ [\(label)] AVPlayerItem startup timed out after 12s")
            if player.currentItem === item {
                player.replaceCurrentItem(with: nil)
            }
            return false
        }

        switch terminalStatus {
            case .readyToPlay:
                playerLog.notice("[benchmark] readyToPlay — \(label) — videoId=\(video.id) title=\(video.title)")
                playerLog.notice("✅ [\(label)] readyToPlay")
                let itemDur = item.duration.seconds
                if itemDur.isFinite && itemDur > 0 {
                    let prevDur = self.duration
                    self.duration = itemDur
                    playerLog.notice("[duration] updated from AVPlayerItem: \(String(format: "%.1f", itemDur))s (was \(String(format: "%.1f", prevDur))s from metadata)")
                } else if self.duration == 0 {
                    durationObserverTask?.cancel()
                    durationObserverTask = Task { [weak self, weak item] in
                        guard let self, let item else { return }
                        for await seconds in item.firstValidDurationStream {
                            guard !Task.isCancelled else { return }
                            let prev = self.duration
                            self.duration = seconds
                            playerLog.notice("[duration] deferred KVO update: \(String(format: "%.1f", seconds))s (was \(String(format: "%.1f", prev))s)")
                            break
                        }
                    }
                }
                if let pos = savedPositionToRestore, pos > 0 {
                    savedPositionToRestore = nil
                    seek(to: pos)
                }
                loadAudioTracks(from: item)
                needsQuickStartup = false
                isLoading = false
                timeToPlayMs = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1000)
                lastSuccessfulStreamType = label
                if timeToPlayMs > 4_000 {
                    CrashlyticsLogger.recordSlowVideoLoad(
                        videoId: video.id,
                        elapsedMs: timeToPlayMs,
                        streamType: label,
                        hasError: false
                    )
                }
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                launchPhase2(video: video, info: info)
                // Track whether the succeeded stream is muxed so quality-switch attempts
                // can detect the state and trigger fresh WKWebView extraction (#210).
                qualityManager.isMuxedFallback = isMuxedFallback
                return true
            case .failed:
                let err = item.error.map { "\($0)" } ?? "nil"
                let nsErr = item.error as? NSError
                let failURL = nsErr?.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
                    ?? nsErr?.userInfo["NSErrorFailingURLKey"] as? String
                playerLog.error("❌ [\(label)] AVPlayerItem failed: \(err)")
                if let failURL {
                    playerLog.error("❌ [\(label)] failing URL: \(failURL.prefix(200))")
                }
                return false
            case .unknown:
                return false
            @unknown default:
                return false
        }
    }

    /// Composes a video-only + audio-only adaptive stream pair via `AVMutableComposition`.
    /// Returns true on successful `.readyToPlay`.
    private func attemptComposition(
        videoURL: URL, audioURL: URL,
        for video: Video, info: PlayerInfo, label: String
    ) async -> Bool {
        let videoItag = URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let audioItag = URLComponents(url: audioURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let videoRqh = videoURL.absoluteString.contains("rqh=1") || videoURL.absoluteString.contains("/rqh/1")

        // Use the client UA that matches the URL's signing client.
        let clientParam = URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "c" })?.value?.uppercased() ?? ""

        // Skip every rqh=1 stream by default — no client works without a pot= token.
        // Exception: TVAuth (TVHTML5) with a valid Bearer token. The official YouTube TV
        // app plays TVHTML5 rqh=1 adaptive streams without BotGuard — Bearer token may
        // satisfy CDN auth for authenticated TV sessions. An 8-second timeout (added to
        // the raceStream below) prevents indefinite hangs if the CDN holds the connection.
        // NOTE: BotGuard websafe fallback token (json[3] from GenerateIT) is NOT accepted
        // by the CDN for rqh=1 segments — only the full minting path (getMinter) produces
        // a CDN-accepted token, which requires a real browser JS context (WKWebView).
        // hasMintedPoToken is set in exhaustiveRetry when BotGuardWebViewRunner succeeds
        // with a full getMinter-minted token — those ARE accepted by the CDN.
        let isTVAuthBearer    = label.contains("TVAuth") && hasAuthToken && currentAuthToken != nil
        let isAndroidVR       = clientParam == "ANDROID_VR"
        #if canImport(WebKit)
        let isBotGuardMinted  = label == "BotGuardWV" && hasMintedPoToken
        #else
        let isBotGuardMinted  = false
        #endif
        if videoRqh && !isTVAuthBearer && !isAndroidVR && !isBotGuardMinted {
            playerLog.notice("[\(label)/adaptive] skipping rqh=1 (client=\(clientParam)) — not exempt")
            return false
        }
        if videoRqh && isBotGuardMinted {
            playerLog.notice("[\(label)/adaptive] attempting rqh=1 with WKWebView-minted BotGuard token (client=\(clientParam)) — CDN should accept")
        } else if videoRqh {
            playerLog.notice("[\(label)/adaptive] attempting rqh=1 TVAuth with Bearer — CDN auth experiment")
        }
        let ua: String
        switch clientParam {
        case "ANDROID_VR":   ua = InnerTubeClients.AndroidVR.userAgent
        case "ANDROID":      ua = InnerTubeClients.Android.userAgent
        case "TVHTML5":      ua = InnerTubeClients.TV.userAgent
        case "MWEB":         ua = InnerTubeClients.MWEB.userAgent
        case "WEB_CREATOR":  ua = InnerTubeClients.Web.userAgent
        default:             ua = InnerTubeClients.iOS.userAgent
        }

        playerLog.notice("[\(label)/adaptive] videoItag=\(videoItag) client=\(clientParam) audioItag=\(audioItag)")

        playerInfo = info
        let newFormats = Self.deduplicatedVideoFormats(info.formats)
        // Never reduce quality options — same policy as attemptURL.
        let maxCurrentHeight = availableFormats.map(\.height).max() ?? 0
        let maxNewHeight = newFormats.map(\.height).max() ?? 0
        if newFormats.count > availableFormats.count || maxNewHeight > maxCurrentHeight || availableFormats.isEmpty {
            availableFormats = newFormats
        }
        playerLog.notice("[\(label)/adaptive] availableFormats after dedup: input=\(info.formats.count) output=\(newFormats.count) kept=\(availableFormats.count) maxH=\(availableFormats.map(\.height).max() ?? 0)")
        availableCaptions = info.captionTracks
        autoApplyCaptionPreference(tracks: info.captionTracks)

        // Inject Bearer only for TVAuth (TVHTML5 authenticated) — CDN validates the
        // TV session token for rqh=1 streams. Android VR uses Oculus UA without OAuth;
        // injecting a TV Bearer token causes CDN to hold the connection and reject it.
        var assetHeaders: [String: String] = ["User-Agent": ua]
        if videoRqh && isTVAuthBearer, let token = currentAuthToken {
            assetHeaders["Authorization"] = "Bearer \(token)"
            playerLog.notice("[\(label)/adaptive] injecting Bearer auth into CDN headers for TVAuth rqh=1")
        }
        if videoRqh && isBotGuardMinted {
            // Inject youtube.com cookies (VISITOR_INFO1_LIVE) cross-domain to googlevideo.com.
            // The CDN validates bui= against VISITOR_INFO1_LIVE — without it, the CDN holds
            // the connection (no immediate 403, but our 3s loadTracks timeout fires).
            // BotGuardWebViewRunner.propagateWebViewCookies() copies WKWebView session cookies
            // into HTTPCookieStorage.shared, making VISITOR_INFO1_LIVE available here.
            let ytCookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://www.youtube.com")!) ?? []
            if !ytCookies.isEmpty {
                assetHeaders["Cookie"] = ytCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                playerLog.notice("[\(label)/adaptive] injecting \(ytCookies.count) youtube.com cookies for BotGuard rqh=1 CDN auth")
            }
        }

        // CDN probe for Android VR rqh=1 — avoids loadTracks timeout when CDN enforces
        // SABR at the content level. URLSession.data(for:) accumulates the full response
        // body before returning; if the CDN stalls mid-body the 1.5s timeout fires → nil.
        //
        // Range must cover the moov atom. The CDN returns HTTP 206 for small byte ranges
        // (including bytes=0-0 and bytes=0-1023) even for SABR-enforced videos — it
        // serves the initial container bytes (ftyp box, partial moov header) freely —
        // but then stalls larger sequential reads that AVURLAsset.loadTracks needs to
        // parse track metadata. The moov atom for a typical YouTube 720p video is
        // 20–200 KB; using bytes=0-131071 (128 KB) ensures we cover it. A stalling CDN
        // delivers a few KB then hangs; URLSession.data(for:) won't return until the
        // complete 128 KB body arrives, so the 1.5s timeout fires and we bail early.
        //
        // Timing: 128 KB at 148 Mbps ≈ 7 ms; at 10 Mbps ≈ 100 ms; stall → 1.5s.
        // TVAuth with Bearer is intentionally excluded — injecting an OAuth token into
        // a bare URLSession changes CDN session state, separate from AVURLAsset context.
        if videoRqh && isAndroidVR {
            var probeReq = URLRequest(url: videoURL)
            probeReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            probeReq.setValue("bytes=0-131071", forHTTPHeaderField: "Range")
            probeReq.timeoutInterval = 1.5
            if let (_, probeResp) = try? await URLSession(configuration: .ephemeral).data(for: probeReq),
               let http = probeResp as? HTTPURLResponse {
                if http.statusCode == 403 || http.statusCode == 401 {
                    playerLog.notice("❌ [\(label)/adaptive] rqh=1 probe: HTTP \(http.statusCode) — CDN enforcing rqh, skipping composition")
                    return false
                }
                playerLog.notice("[\(label)/adaptive] rqh=1 probe: HTTP \(http.statusCode) 128KB delivered — moov atom accessible, proceeding")
            } else {
                // CDN stalled before delivering 128 KB. This predicts loadTracks failure
                // (moov atom not accessible), so bail immediately rather than waiting 2s.
                playerLog.notice("⚠️ [\(label)/adaptive] rqh=1 probe: timeout after 1.5s (128KB stall) — CDN enforcing SABR, skipping composition")
                return false
            }
        }

        let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": assetHeaders])
        let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": assetHeaders])

        do {
            // loadTracks can stall indefinitely when rqh=1 CDN URLs don't fail fast.
            // @MainActor task-group child tasks are subject to main-actor scheduling
            // pressure (XCTest accessibility callbacks), so withThrowingTaskGroup is
            // unreliable here even with Task.detached wrappers.
            //
            // Solution: use AsyncStream as a cross-thread coordination channel.
            // Both the loadTracks work AND the 8-second timeout run in fully-detached
            // tasks (thread pool, no actor isolation). Whichever finishes first yields
            // to the stream. The main-actor consumer resumes when either signal arrives,
            // regardless of main-actor scheduling pressure.
            let vTracks: [AVAssetTrack]
            let aTracks: [AVAssetTrack]
            do {
                // AVAssetTrack is not Sendable in Swift 6 strict mode.
                // Wrap the pair so AsyncStream<TrackBox?> satisfies Sendable.
                // Ownership is transferred atomically through the stream; no concurrent
                // access occurs after the box is read on the main actor.
                struct TrackBox: @unchecked Sendable {
                    let video: [AVAssetTrack]
                    let audio: [AVAssetTrack]
                }
                let (raceStream, raceCont) = AsyncStream<TrackBox?>.makeStream()

                // loadTracks on thread pool — yields result or nil on error
                Task.detached {
                    let box: TrackBox? = try? await { () async throws -> TrackBox in
                        async let v = videoAsset.loadTracks(withMediaType: .video)
                        async let a = audioAsset.loadTracks(withMediaType: .audio)
                        let (vv, aa) = try await (v, a)
                        return TrackBox(video: vv, audio: aa)
                    }()
                    raceCont.yield(box)
                    raceCont.finish()
                }

                // Timeout task — prevents indefinite CDN hang for rqh=1 Bearer experiments.
                // After finish() is called by either task, subsequent yield/finish are no-ops.
                // On tvOS/iOS: AndroidVR gets 2s — the firstByte probe (Range: bytes=0-0) is a
                // false positive for rqh=1 CDN enforcement: the CDN serves the first byte (206)
                // but stalls actual AVURLAsset segment requests. fast non-rqh videos complete
                // loadTracks in ~0.4s, so 2s is a safe margin on both platforms.
                // fix1/tvOS: 2s validated correct. fix_task240: apply same 2s cap to iOS — log
                // shows 8s × 2 (race + serial) = 16s wasted on `cnsKl2JouOc` class of video.
                let isVRAttempt = clientParam == "ANDROID_VR"
                #if os(tvOS)
                let timeoutNs: UInt64 = isVRAttempt ? 2_000_000_000 : 3_000_000_000
                #else
                // fix30 (task #230): 1.5s for non-VR iOS first-video loads.
                // fix_task240: 2s for AndroidVR (was 8s) — false-positive probe scenario.
                let timeoutNs: UInt64 = isVRAttempt ? 2_000_000_000 : (needsQuickStartup ? 1_500_000_000 : 8_000_000_000)
                #endif
                Task.detached {
                    try? await Task.sleep(nanoseconds: timeoutNs)
                    raceCont.yield(nil)
                    raceCont.finish()
                }

                if let firstOrNil = await raceStream.first(where: { @Sendable _ in true }),
                   let box = firstOrNil {
                    vTracks = box.video
                    aTracks = box.audio
                } else {
                    #if os(tvOS)
                    let timeoutSec = isVRAttempt ? 2 : 3
                    #else
                    let timeoutSec = isVRAttempt ? 2 : (needsQuickStartup ? 1 : 8)  // VR=2s (fix_task240), non-VR quick=1.5s (fix30)
                    #endif
                    let reason = "timed out after \(timeoutSec)s or loadTracks failed"
                    playerLog.error("❌ [\(label)/adaptive] loadTracks \(reason) (rqh=\(videoRqh))")
                    return false
                }
            }

            guard let sourceVideoTrack = vTracks.first,
                  let sourceAudioTrack = aTracks.first else {
                playerLog.error("❌ [\(label)/adaptive] no tracks in remote assets (rqh=\(videoRqh))")
                return false
            }

            let videoDuration = try await videoAsset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: videoDuration)
            let composition = AVMutableComposition()

            guard let compVideo = composition.addMutableTrack(withMediaType: .video,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid),
                  let compAudio = composition.addMutableTrack(withMediaType: .audio,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid) else {
                playerLog.error("❌ [\(label)/adaptive] could not add composition tracks")
                return false
            }

            try compVideo.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            try compAudio.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)

            playerLog.notice("✅ [\(label)/adaptive] composition built — testing playback for \(video.id)")
            lastAttemptedStreamURL = videoURL
            let compositeItem = AVPlayerItem(asset: composition)
            compositeItem.audioTimePitchAlgorithm = .spectral
            // fix11: Fast-start — fire readyToPlay after 0.5 s of buffered content.
            // Without this, AVMutableComposition items use the system default heuristic
            // (effectively unconstrained), which adds 0.3–0.5 s to initial buffering.
            // Reset to system default (0) in a ramp Task so downstream buffering is
            // not constrained after startup (same pattern as HLS paths).
            compositeItem.preferredForwardBufferDuration = 0.5
            Task { [weak compositeItem] in
                try? await Task.sleep(for: .seconds(5))
                compositeItem?.preferredForwardBufferDuration = 0
            }
            // fix235: Guard cancellation and video identity before touching the player.
            guard !Task.isCancelled, currentVideo?.id == video.id else {
                playerLog.notice("⚠️ [\(label)/adaptive] fix235: task cancelled or video changed (current=\(currentVideo?.id ?? "nil") expected=\(video.id)) — aborting replaceCurrentItem")
                return false
            }
            player.replaceCurrentItem(with: compositeItem)
            itemObserverTask?.cancel()

            for await status in compositeItem.statusStream {
                switch status {
                case .readyToPlay:
                    playerLog.notice("[benchmark] readyToPlay — \(label)/adaptive — videoId=\(video.id) title=\(video.title)")
                    playerLog.notice("✅ [\(label)/adaptive] readyToPlay")
                    let compDur = compositeItem.duration.seconds
                    if compDur.isFinite && compDur > 0 {
                        let prevDur = self.duration
                        self.duration = compDur
                        playerLog.notice("[duration] updated from composition AVPlayerItem: \(String(format: "%.1f", compDur))s (was \(String(format: "%.1f", prevDur))s from metadata)")
                    } else if self.duration == 0 {
                        durationObserverTask?.cancel()
                        durationObserverTask = Task { [weak self, weak compositeItem] in
                            guard let self, let compositeItem else { return }
                            for await seconds in compositeItem.firstValidDurationStream {
                                guard !Task.isCancelled else { return }
                                let prev = self.duration
                                self.duration = seconds
                                playerLog.notice("[duration] deferred KVO update: \(String(format: "%.1f", seconds))s (was \(String(format: "%.1f", prev))s)")
                                break
                            }
                        }
                    }
                    if let pos = savedPositionToRestore, pos > 0 {
                        savedPositionToRestore = nil
                        seek(to: pos)
                    }
                    loadAudioTracks(from: compositeItem)
                    needsQuickStartup = false
                    isLoading = false
                    timeToPlayMs = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1000)
                    if timeToPlayMs > 4_000 {
                        CrashlyticsLogger.recordSlowVideoLoad(
                            videoId: video.id,
                            elapsedMs: timeToPlayMs,
                            streamType: "\(label)/adaptive",
                            hasError: false
                        )
                    }
                    player.rate = Float(settings.playbackSpeed)
                    isPlaying = true
                    launchPhase2(video: video, info: info)
                    return true
                case .failed:
                    let nsErr = compositeItem.error as? NSError
                    let httpStatus = (nsErr?.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == -12660 ? 403 : (nsErr?.code ?? -1)
                    playerLog.error("❌ [\(label)/adaptive] AVPlayerItem failed: domain=\(nsErr?.domain ?? "?") code=\(nsErr?.code ?? -1) httpStatus=\(httpStatus)")
                    return false
                case .unknown:
                    continue
                @unknown default:
                    continue
                }
            }
            return false
        } catch {
            let nsErr = error as NSError
            let httpStatus = (nsErr.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == -12660 ? 403 : nsErr.code
            playerLog.error("❌ [\(label)/adaptive] setup failed: domain=\(nsErr.domain) code=\(nsErr.code) httpStatus=\(httpStatus)")
            return false
        }
    }

    private func launchPhase2(video: Video, info: PlayerInfo, cached: CachedVideoData? = nil) {
        phase2Task?.cancel()
        phase2Task = Task(priority: .utility) { [weak self] in
            // Use the caller-supplied cached data when available so Phase 2 can use
            // already-consumed nextInfo/endCards/sponsorSegments instead of re-fetching.
            // Falls back to empty (full network fetch) when no cached data is passed
            // (e.g. from the 3-attempt retry loop which doesn't have the original cached struct).
            let p2Cached = cached ?? CachedVideoData(
                playerInfo: nil, trackingURLs: nil, nextInfo: nil,
                endCards: nil, sponsorSegments: nil, deArrowBranding: nil,
                staleFields: []
            )
            await self?.loadAsyncPhase2(
                video: video, cached: p2Cached, info: info,
                cachedTrackingURLs: cached?.trackingURLs ?? nil, authTrackingTask: nil,
                sponsorCached: cached?.sponsorSegments != nil
            )
        }
        // Background pre-warming runs alongside phase2:
        //  • muxed fallback → fetch AndroidVR playerInfo so quality-tap skips 403 recovery
        //  • adaptive playing → pre-warm tracks for the user's preferred quality tier
        prefetchTask?.cancel()
        if info.bestAdaptiveAudioURL == nil {
            prefetchTask = Task(priority: .utility) { [weak self] in
                await self?.fetchAndCacheAdaptivePlayerInfo(video: video, muxedInfo: info)
            }
        } else if settings.preferredQuality != .auto {
            prefetchTask = Task(priority: .utility) { [weak self] in
                await self?.prefetchPreferredQualityTracks(info: info)
            }
        }
    }

    /// Called from `launchPhase2` when muxed 360p is the only available stream
    /// (`info.bestAdaptiveAudioURL == nil`).  Fetches AndroidVR player info in the
    /// background and upgrades `self.playerInfo` so that the first quality-tap skips
    /// the 17-second 403-recovery cycle.
    private func fetchAndCacheAdaptivePlayerInfo(video: Video, muxedInfo: PlayerInfo) async {
        playerLog.notice("[prefetch] muxed fallback — fetching AndroidVR playerInfo in background")
        do {
            let vrInfo = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)
            guard !Task.isCancelled else { return }
            guard vrInfo.bestAdaptiveAudioURL != nil else {
                playerLog.notice("[prefetch] AndroidVR returned no adaptive audio — playerInfo not upgraded")
                return
            }
            guard currentVideo?.id == video.id, playerInfo?.bestAdaptiveAudioURL == nil else {
                playerLog.notice("[prefetch] playerInfo already upgraded or video changed — discarding prefetch result")
                return
            }
            playerInfo = vrInfo
            let vrFormats = Self.deduplicatedVideoFormats(vrInfo.formats)
            let maxCurrentH = availableFormats.map(\.height).max() ?? 0
            let maxVRH = vrFormats.map(\.height).max() ?? 0
            // Only update availableFormats (quality-picker options) when at least one format
            // is rqh-free. rqh=1 formats are immediately reverted by reloadDASHItem's rqh guard
            // and should not appear in the picker.
            let hasRqhFreeFormat = vrFormats.contains { fmt in
                guard let url = fmt.url else { return false }
                return !PlaybackQualityManager.urlHasRqhEnforcement(url)
            }
            if hasRqhFreeFormat && (vrFormats.count > availableFormats.count || maxVRH > maxCurrentH) {
                availableFormats = vrFormats
            }
            playerLog.notice("⚡ [prefetch] playerInfo upgraded to AndroidVR (\(vrFormats.count) formats) — quality switches skip 403 recovery")
            await prefetchPreferredQualityTracks(info: vrInfo)
        } catch {
            playerLog.notice("[prefetch] background AndroidVR fetch failed: \(error)")
        }
    }

    /// Pre-loads `AVAssetTrack` arrays for `settings.preferredQuality` into
    /// `AVAssetTrackCache` so that the first quality-tap after initial playback
    /// is a cache hit rather than a CDN round-trip.
    private func prefetchPreferredQualityTracks(info: PlayerInfo) async {
        guard settings.preferredQuality != .auto,
              let maxH = settings.preferredQuality.maxHeight else { return }
        guard let videoURL = PlaybackQualityManager.selectBestVideoFormat(
                  from: info.formats, preferredMaxHeight: maxH,
                  preferH264: settings.preferH264
              )?.url,
              let audioURL = info.bestAdaptiveAudioURL else { return }
        if AVAssetTrackCache.shared.videoTracks(for: videoURL) != nil { return }
        let itag = URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let ua = InnerTubeClients.iOS.userAgent
        let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
        let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
        playerLog.notice("[prefetch] pre-warming tracks for preferredQuality=\(maxH)p (itag=\(itag))")
        struct PrefetchTrackBox: @unchecked Sendable {
            let video: [AVAssetTrack]; let audio: [AVAssetTrack]
        }
        let (stream, cont) = AsyncStream<PrefetchTrackBox?>.makeStream()
        Task.detached {
            let box: PrefetchTrackBox? = try? await { () async throws -> PrefetchTrackBox in
                async let v = videoAsset.loadTracks(withMediaType: .video)
                async let a = audioAsset.loadTracks(withMediaType: .audio)
                let (vv, aa) = try await (v, a)
                return PrefetchTrackBox(video: vv, audio: aa)
            }()
            cont.yield(box)
            cont.finish()
        }
        Task.detached {
            try? await Task.sleep(for: .seconds(60))
            cont.yield(nil)
            cont.finish()
        }
        if let result = await stream.first(where: { @Sendable _ in true }),
           let box = result, !box.video.isEmpty, !box.audio.isEmpty {
            AVAssetTrackCache.shared.store(videoTracks: box.video, audioTracks: box.audio,
                                            videoURL: videoURL, audioURL: audioURL)
            playerLog.notice("⚡ [prefetch] tracks cached for preferredQuality=\(maxH)p (itag=\(itag))")
        } else {
            playerLog.notice("[prefetch] track prefetch timed out/failed for preferredQuality=\(maxH)p")
        }
    }

    /// Prefetches `AVAssetTrack` metadata for ALL available quality tiers at `.userInitiated`
    /// priority. Call this when the quality picker opens so that by the time the user taps a
    /// quality, the tracks are already cached and the switch completes in < 100ms (Fix 2A).
    func prefetchAllQualityTracks() async {
        guard let info = playerInfo else { return }
        guard info.hlsURL == nil else { return } // HLS doesn't need DASH track prefetch
        guard let audioURL = info.bestAdaptiveAudioURL else { return }
        guard !PlaybackQualityManager.urlHasRqhEnforcement(audioURL) else { return }

        let formats = Self.deduplicatedVideoFormats(info.formats)
        let ua = InnerTubeClients.iOS.userAgent

        // Load audio tracks once — shared across all video qualities.
        let audioTracks: [AVAssetTrack]
        if let cached = AVAssetTrackCache.shared.audioTracks(for: audioURL), !cached.isEmpty {
            audioTracks = cached
        } else {
            let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
            guard let loaded = try? await audioAsset.loadTracks(withMediaType: .audio), !loaded.isEmpty else { return }
            audioTracks = loaded
        }

        for fmt in formats.prefix(6) {
            guard !Task.isCancelled else { return }
            guard let videoURL = fmt.url else { continue }
            guard !PlaybackQualityManager.urlHasRqhEnforcement(videoURL) else { continue }
            guard AVAssetTrackCache.shared.videoTracks(for: videoURL) == nil else { continue }
            let itag = URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
            let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
            playerLog.notice("[prefetch/picker] pre-warming \(fmt.height)p itag=\(itag)")
            if let vTracks = try? await videoAsset.loadTracks(withMediaType: .video), !vTracks.isEmpty {
                AVAssetTrackCache.shared.store(videoTracks: vTracks, audioTracks: audioTracks,
                                               videoURL: videoURL, audioURL: audioURL)
                playerLog.notice("⚡ [prefetch/picker] cached \(fmt.height)p itag=\(itag)")
            }
        }
    }

    /// Rebuilds the `AVMutableComposition` during a quality switch for DASH/MP4-only videos
    /// (where `hlsURL == nil`). Mirrors `attemptComposition` but does not reset `playerInfo`
    /// or `availableFormats` and does not call `launchPhase2` — this is a mid-playback swap.
    func rebuildCompositionForQuality(videoURL: URL, audioURL: URL, seekTo: TimeInterval) async {
        let videoItag = URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let audioItag = URLComponents(url: audioURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        // Always use the iOS UA regardless of URL signing (c=ANDROID or c=IOS).
        // The initial attemptComposition path uses iOS UA for all URLs including
        // Android-client-signed ones, and it succeeds. Using Android UA for c=ANDROID
        // URLs was an incorrect assumption — it caused HTTP 403 instead of preventing it.
        let ua = InnerTubeClients.iOS.userAgent
        playerLog.notice("[quality/DASH] rebuilding composition — videoItag=\(videoItag) audioItag=\(audioItag) ua=iOS")

        let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
        let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])

        do {
            // ── loadTracks with 60-second timeout ────────────────────────────────────
            // Without a timeout, rqh=1 CDN URLs hold the TCP connection open indefinitely,
            // causing quality-switch composition to hang forever (player stays at 360p).
            // The AsyncStream + Task.detached pattern mirrors attemptComposition to avoid
            // @MainActor scheduling pressure on withThrowingTaskGroup child tasks.
            let vTracks: [AVAssetTrack]
            let aTracks: [AVAssetTrack]
            let cachedV = AVAssetTrackCache.shared.videoTracks(for: videoURL)
            let cachedA = AVAssetTrackCache.shared.audioTracks(for: audioURL)
            if let cv = cachedV, let ca = cachedA, !cv.isEmpty, !ca.isEmpty {
                vTracks = cv
                aTracks = ca
                playerLog.notice("⚡ [quality/DASH] loadTracks cache hit (itag=\(videoItag)) — skipping CDN round-trip")
            } else {
            do {
                struct TrackBox: @unchecked Sendable {
                    let video: [AVAssetTrack]
                    let audio: [AVAssetTrack]
                }
                let (raceStream, raceCont) = AsyncStream<TrackBox?>.makeStream()
                Task.detached {
                    let box: TrackBox? = try? await { () async throws -> TrackBox in
                        async let v = videoAsset.loadTracks(withMediaType: .video)
                        async let a = audioAsset.loadTracks(withMediaType: .audio)
                        let (vv, aa) = try await (v, a)
                        return TrackBox(video: vv, audio: aa)
                    }()
                    raceCont.yield(box)
                    raceCont.finish()
                }
                Task.detached {
                    try? await Task.sleep(for: .seconds(10))
                    raceCont.yield(nil)
                    raceCont.finish()
                }
                if let firstOrNil = await raceStream.first(where: { @Sendable _ in true }),
                   let box = firstOrNil {
                    vTracks = box.video
                    aTracks = box.audio
                    AVAssetTrackCache.shared.store(videoTracks: vTracks, audioTracks: aTracks,
                                                    videoURL: videoURL, audioURL: audioURL)
                } else {
                    playerLog.error("❌ [quality/DASH] loadTracks timed out after 10s — triggering 403 recovery retry")
                    selectedFormat = nil
                    if statsForNerdsVisible { updateStatsSnapshot() }
                    if let video = currentVideo {
                        await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                        HLSManifestCache.shared.invalidate(for: video.id)
                        await retryWith403Recovery(video: video, originalError: nil)
                    }
                    return
                }
            }
            } // end cache-miss else
            // ─────────────────────────────────────────────────────────────────────────

            guard let sourceVideoTrack = vTracks.first,
                  let sourceAudioTrack = aTracks.first else {
                playerLog.error("❌ [quality/DASH] no tracks in remote assets — triggering 403 recovery retry")
                selectedFormat = nil
                if statsForNerdsVisible { updateStatsSnapshot() }
                if let video = currentVideo {
                    await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                    HLSManifestCache.shared.invalidate(for: video.id)
                    await retryWith403Recovery(video: video, originalError: nil)
                }
                return
            }

            let videoDuration = try await videoAsset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: videoDuration)
            let composition = AVMutableComposition()

            guard let compVideo = composition.addMutableTrack(withMediaType: .video,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid),
                  let compAudio = composition.addMutableTrack(withMediaType: .audio,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid) else {
                playerLog.error("❌ [quality/DASH] could not add composition tracks")
                selectedFormat = nil
                if statsForNerdsVisible { updateStatsSnapshot() }
                return
            }

            try compVideo.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            try compAudio.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
            playerLog.notice("✅ [quality/DASH] composition built — swapping item")

            lastAttemptedStreamURL = videoURL
            let compositeItem = AVPlayerItem(asset: composition)
            isQualityChangePending = true
            isSwappingItem = true
            player.replaceCurrentItem(with: compositeItem)
            isSwappingItem = false
            itemObserverTask?.cancel()

            for await status in compositeItem.statusStream {
                switch status {
                case .readyToPlay:
                    let size = compositeItem.presentationSize
                    let benchVid = self.currentVideo?.id ?? "nil"
                    let benchTitle = self.currentVideo?.title ?? "nil"
                    playerLog.notice("[benchmark] readyToPlay — quality/DASH — videoId=\(benchVid) title=\(benchTitle)")
                    playerLog.notice("✅ [quality/DASH] readyToPlay — presentationSize=\(Int(size.width))x\(Int(size.height))")
                    isQualityChangePending = false
                    // Use currentTime (preserved by time observer freeze) instead of seekTo
                    // to honour any user seek that occurred during the DASH rebuild transition.
                    let seekTarget = currentTime > 0 ? currentTime : seekTo
                    playerLog.notice("[quality/DASH] readyToPlay — seekTarget=\(seekTarget)s (currentTime=\(currentTime)s savedSeekTo=\(seekTo)s)")
                    if seekTarget > 0 { seek(to: seekTarget) }
                    loadAudioTracks(from: compositeItem)
                    player.rate = Float(settings.playbackSpeed)
                    isPlaying = true
                    return
                case .failed:
                    let itemError = compositeItem.error
                    let errStr = itemError.map { "\($0)" } ?? "nil"
                    playerLog.error("❌ [quality/DASH] AVPlayerItem failed: \(errStr) — triggering 403 recovery retry")
                    selectedFormat = nil
                    if statsForNerdsVisible { updateStatsSnapshot() }
                    if let video = currentVideo {
                        await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                        HLSManifestCache.shared.invalidate(for: video.id)
                        await retryWith403Recovery(video: video, originalError: itemError)
                    }
                    return
                case .unknown:
                    continue
                @unknown default:
                    continue
                }
            }
        } catch {
            playerLog.error("❌ [quality/DASH] composition build error: \(error) — triggering 403 recovery retry")
            selectedFormat = nil
            if statsForNerdsVisible { updateStatsSnapshot() }
            if let video = currentVideo {
                await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                HLSManifestCache.shared.invalidate(for: video.id)
                await retryWith403Recovery(video: video, originalError: error)
            }
        }
    }

    // MARK: - Helpers

    /// Returns the AVFoundation User-Agent for `url` based on its `c=` signing parameter.
    /// NOTE: This helper is no longer used by `rebuildCompositionForQuality`, which now always
    /// uses iOS UA. Kept for reference — the original assumption (Android UA needed for
    /// c=ANDROID URLs) was incorrect; the initial `attemptComposition` path proves iOS UA
    /// works for all URL signing variants.
    static func userAgent(for url: URL) -> String {
        let client = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "c" })?.value ?? ""
        return client.hasPrefix("ANDROID") ? InnerTubeClients.Android.userAgent : InnerTubeClients.iOS.userAgent
    }

    /// Returns the best adaptive video-only MP4 URL, respecting the user's quality preference.
    /// When `preferredQuality != .auto`, filters to formats at or below `maxHeight`, sorts
    /// by height descending then bitrate descending. Falls back to highest bitrate when no
    /// format meets the height cap.
    /// When `preferredQuality == .auto`, caps at the display's native resolution so the
    /// player never fetches a resolution higher than the screen can render.
    ///
    /// H.264 (avc1) is preferred over AV1 (av01) at any given resolution because Android-client
    /// AV1 streams require a proof-of-origin token (pot) that the app does not supply, causing
    /// systematic HTTP 403 errors on adaptive composition. H.264 streams are served without
    /// that restriction and are well-supported by AVFoundation.
    private func qualityCapVideoURL(from formats: [VideoFormat]) -> URL? {
        let maxH: Int
        if settings.preferredQuality != .auto, let h = settings.preferredQuality.maxHeight {
            maxH = h
        } else {
            // Auto: cap at the display's native resolution — no benefit loading higher
            // than what the screen can actually render.
            maxH = Self.displayMaxVideoHeight()
        }
        return PlaybackQualityManager.selectBestVideoFormat(
            from: formats,
            preferredMaxHeight: maxH,
            preferH264: true
        )?.url
    }

    /// Returns the maximum video height (pixels) that this display can render for
    /// landscape 16:9 content. Used to cap quality in Auto mode.
    ///
    /// The shorter native-pixel dimension equals the landscape height — the maximum
    /// video height the screen can actually show for standard 16:9 YouTube content.
    static func displayMaxVideoHeight() -> Int {
        #if canImport(UIKit)
        let bounds = UIScreen.main.nativeBounds
        return Int(max(bounds.width, bounds.height))
        #else
        return 1080  // Conservative fallback for non-UIKit targets
        #endif
    }

    // MARK: - HLS n-descrambling (simulator only)

    #if targetEnvironment(simulator)
    /// Probes the first segment of an HLS variant playlist.
    /// Returns `variantURL` unchanged if the segment is already accessible (n is valid).
    /// If the segment returns 403 (scrambled n), applies the JS solver to descramble the n
    /// in `variantURL` and returns the corrected URL. When the CDN receives a request with
    /// the descrambled n, it embeds the descrambled n in all segment URLs it returns, so
    /// AVPlayer can fetch every segment without receiving 403.
    private func descrambledVariantURL(_ variantURL: URL, label: String) async -> (URL, HLSVariantProxy?) {
        let ua = "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)"

        // 1. Fetch the variant playlist to obtain segment URLs.
        var req = URLRequest(url: variantURL)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let text = String(data: data, encoding: .utf8) else {
            playerLog.notice("[\(label)] n-probe: playlist fetch failed — using original URL")
            return (variantURL, nil)
        }

        // 2. Find the first absolute segment URL in the playlist.
        let lines = text.components(separatedBy: .newlines)
        guard let segStr = lines.first(where: { !$0.hasPrefix("#") && !$0.isEmpty && $0.hasPrefix("http") }),
              let segURL = URL(string: segStr) else {
            playerLog.notice("[\(label)] n-probe: no segment URL found — using original URL")
            return (variantURL, nil)
        }

        // 3. HEAD-probe the segment to detect scrambled n.
        var segReq = URLRequest(url: segURL)
        segReq.httpMethod = "HEAD"
        segReq.setValue(ua, forHTTPHeaderField: "User-Agent")
        segReq.timeoutInterval = 5
        if let (_, resp) = try? await URLSession.shared.data(for: segReq),
           let http = resp as? HTTPURLResponse, http.statusCode == 200 {
            playerLog.notice("[\(label)] n-probe: segment 200 — n is valid, no descrambling needed")
            return (variantURL, nil)
        }

        // 4. Segment inaccessible (403) — extract scrambled n from the SEGMENT URL, not the
        //    variant playlist URL. The segment URLs inside the playlist carry an independent n
        //    that the CDN does NOT change based on the variant URL's n. Descrambling only the
        //    variant URL's n leaves segment n values scrambled → AVPlayer still gets 403.
        //    We must rewrite segment n values in the playlist content itself, then serve the
        //    modified playlist from a local temp file so AVPlayer fetches descrambled segments.
        playerLog.notice("[\(label)] n-probe: segment not 200 — rewriting segment n in playlist")

        // Extract n from segment URL (YouTube HLS uses path-based /n/VALUE/ format).
        let segPathParts = segURL.pathComponents
        let scrambledSegN: String?
        if let idx = segPathParts.firstIndex(of: "n"), idx + 1 < segPathParts.count,
           !segPathParts[idx + 1].isEmpty {
            scrambledSegN = segPathParts[idx + 1]
        } else if let nItem = URLComponents(url: segURL, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "n" }),
                  let val = nItem.value, !val.isEmpty {
            scrambledSegN = val
        } else {
            scrambledSegN = nil
        }

        guard let scrambledN = scrambledSegN else {
            playerLog.notice("[\(label)] n-probe: could not extract n from segment URL — using original")
            return (variantURL, nil)
        }

        // 5. Descramble the segment n via the JS solver.
        //    Build a synthetic path-format URL so YouTubeNDescrambler.extractNParam can locate n.
        guard let syntheticURL = URL(string: "https://googlevideo.com/videoplayback/n/\(scrambledN)/seg.ts") else {
            return (variantURL, nil)
        }
        let descrambledSynthetic = await YouTubeNDescrambler.shared.descrambleURL(syntheticURL)
        guard descrambledSynthetic != syntheticURL else {
            playerLog.notice("[\(label)] n-probe: solver returned unchanged URL for segment n — using original")
            return (variantURL, nil)
        }

        // Extract the descrambled n value from the synthetic result.
        let descParts = descrambledSynthetic.pathComponents
        guard let dIdx = descParts.firstIndex(of: "n"), dIdx + 1 < descParts.count,
              !descParts[dIdx + 1].isEmpty else {
            return (variantURL, nil)
        }
        let descrambledN = descParts[dIdx + 1]
        playerLog.notice("[\(label)] n-probe: segment n: \(scrambledN) → \(descrambledN)")

        // 6. Rewrite ALL n occurrences in the playlist (path + query-string formats).
        //    All segments in a YouTube HLS playlist share the same n value, so a single
        //    replace-all pass covers every segment URL.
        var rewritten = text
        rewritten = rewritten.replacingOccurrences(of: "/n/\(scrambledN)/", with: "/n/\(descrambledN)/")
        // Also handle query-string format (n=OLD covers ?n=OLD& and &n=OLD& and &n=OLD\n)
        rewritten = rewritten.replacingOccurrences(of: "n=\(scrambledN)", with: "n=\(descrambledN)")

        // 6b. Verify the rewrite: probe the first rewritten segment to confirm 200.
        //     If still 403, the descrambled n is wrong (solver/player.js mismatch).
        let rewrittenLines = rewritten.components(separatedBy: .newlines)
        if let firstRewrittenSeg = rewrittenLines.first(where: { !$0.hasPrefix("#") && !$0.isEmpty && $0.hasPrefix("http") }),
           let verifyURL = URL(string: firstRewrittenSeg) {
            playerLog.notice("[\(label)] n-probe: verifying rewritten seg n=\(descrambledN)")
            var verifyReq = URLRequest(url: verifyURL)
            verifyReq.httpMethod = "HEAD"
            verifyReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            verifyReq.timeoutInterval = 5
            if let (_, verifyResp) = try? await URLSession.shared.data(for: verifyReq),
               let verifyHTTP = verifyResp as? HTTPURLResponse {
                playerLog.notice("[\(label)] n-probe: post-rewrite verify → HTTP \(verifyHTTP.statusCode)")
                if verifyHTTP.statusCode == 403 {
                    playerLog.error("[\(label)] n-probe: VERIFY FAILED — descrambled n returns 403; reverting to original URL")
                    return (variantURL, nil)
                }
            } else {
                playerLog.notice("[\(label)] n-probe: post-rewrite verify timed out or failed — proceeding anyway")
            }
        }

        // 7. Serve the rewritten playlist via AVAssetResourceLoader (custom URL scheme).
        //    Using a file:// URL + AVURLAssetHTTPHeaderFieldsKey causes AVPlayer to silently hang
        //    in .unknown status indefinitely on the iOS Simulator — AVFoundation never fires
        //    readyToPlay. The file:// + HTTP-header-options combination appears to suppress the
        //    AVFoundation networking stack that fetches CDN segments, so the item never becomes
        //    ready. Using a custom non-http scheme instead routes the initial playlist request
        //    through AVAssetResourceLoader, which returns our pre-rewritten content. AVPlayer then
        //    fetches CDN segment URLs (https://) via its normal network stack — no file I/O needed.
        let proxy = HLSVariantProxy(playlistContent: rewritten)
        let proxyURL = HLSVariantProxy.makeProxyURL()
        playerLog.notice("[\(label)] n-probe: HLS proxy ready — serving \(rewritten.count) bytes")
        return (proxyURL, proxy)
    }
    #endif

    // MARK: - yt-dlp HLS simulator fast-path

    #if canImport(WebKit)
    /// Loads an HLS manifest URL extracted by `YouTubeWebViewHLSExtractor` directly into AVPlayer.
    ///
    /// The URL was obtained by intercepting the YouTube JS player's internal InnerTube call in a
    /// hidden WKWebView — the JS player computes the `spc=` token that bypasses `rqh=1` CDN
    /// restrictions. Segment URLs in the manifest are signed by YouTube and served without 403.
    ///
    /// Fetches the `hls_variant` master manifest, parses it for a per-quality `hls_playlist`
    /// URL at ≥720p, then loads that into AVPlayer via YTHLSProxyLoader so that ALL
    /// HLS requests (playlist + segments) are forwarded through URLSession with the
    /// correct desktop-Safari User-Agent that manifest.googlevideo.com requires.
    /// - Parameter poToken: When non-nil, the proxy rewrites variant playlist URIs to the
    ///   proxy scheme and injects ?pot=<token> into every segment URL so rqh=1-enforced
    ///   CDN requests are authenticated without needing googlevideo.com session cookies.
    /// - Parameter skipIfPfa1: When `true` (Phase -1a only), bail immediately if the selected
    ///   variant URL contains `pfa/1` and `poToken` is nil. The Phase -1a cached preWarm URL has
    ///   a STALE `xpc=` credential that CDN always rejects for pfa/1 videos. Racing paths and
    ///   serial-extraction paths pass `false` because those use a FRESH `xpc=` URL (earlyTask).
    private func tryWebViewHLS(_ masterURL: URL, nSolver: (unsolved: String, solved: String)?, poToken: String? = nil, skipIfPfa1: Bool = false, for video: Video) async -> Bool {
        playerLog.notice("[webView/HLS] fetching master manifest: \(masterURL.absoluteString.prefix(120))")

        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

        // 1. Download the master M3U8 via URLSession (spc= in URL = self-authenticating)
        var request = URLRequest(url: masterURL, timeoutInterval: 20)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let manifestText = String(data: data, encoding: .utf8) else {
            playerLog.error("❌ [webView/HLS] failed to fetch master manifest")
            return false
        }
        playerLog.notice("[webView/HLS] master manifest OK bytes=\(data.count)")

        // 2. Parse ALL variants for the quality picker and best ≥720p for initial playback.
        let allVariants = parseHLSAllVariants(from: manifestText, baseURL: masterURL)
        let bestURL = parseHLSBestVariant(from: manifestText, baseURL: masterURL, minHeight: 720)
                   ?? parseHLSBestVariant(from: manifestText, baseURL: masterURL, minHeight: 0)
        guard let bestURL else {
            playerLog.error("❌ [webView/HLS] no quality URL found in master manifest")
            return false
        }
        playerLog.notice("[webView/HLS] selected per-quality URL: \(bestURL.absoluteString.prefix(200))")

        // fix28: Fast-fail for pfa/1 urls in Phase -1a when no pot= is available.
        //
        // For pfa/1 variants the CDN rejects segment requests (-12660) unless the URL's
        // xpc= credential is FRESH (< ~5 s, minted by the YouTube player at wv.load() time).
        // When Phase -1a calls tryWebViewHLS with the CACHED preWarm URL (stored 90+ s ago),
        // that URL's xpc= is always stale → CDN rejects all segments → 1.1 s wasted.
        //
        // Returning false immediately lets the race start earlier. Race Path B awaits
        // wkHLSEarlyTask (priorityExtract), which has already extracted a FRESH xpc= URL.
        // Path B wins with that fresh URL, reducing c1 from ~2.87 s → ~1.0-1.4 s.
        //
        // IMPORTANT: this guard only fires when `skipIfPfa1 == true` (Phase -1a mode).
        // The race path (racePathB) and serial extraction after race-failed pass
        // `skipIfPfa1: false` so fresh liveRace URLs are never prematurely rejected.
        if skipIfPfa1, poToken == nil,
           (bestURL.absoluteString.contains("/pfa/1/") || bestURL.absoluteString.contains("pfa%2F1")) {
            playerLog.notice("[webView/HLS] Phase -1a pfa/1 + pot=nil — stale xpc= cannot auth CDN segments; bailing early (fix28)")
            return false
        }

        // Cache the master manifest URL so future loads of this video (or pre-extracted
        // neighbours) can skip the 5–9 s WKWebView extraction step entirely.
        await VideoPreloadCache.shared.store(wkHLSManifestURL: masterURL, for: video.id)

        // Extract WKWebView cookies for the proxy loader.
        // Note: segment URLs in variant playlists are served natively by AVPlayer (not proxied),
        // so the proxy does not need googlevideo.com cookies for rqh=1 content. The master
        // manifest URL is self-authenticated via spc=, and youtube.com session cookies
        // (VISITOR_INFO1_LIVE, YSC, etc.) are sufficient for CDN segment auth in practice.
        let webViewCookies = await extractWKWebViewCookies()
        let gvCount = webViewCookies.filter { $0.domain.contains("googlevideo") }.count
        playerLog.notice("[webView/HLS] extracted \(webViewCookies.count) cookies (\(gvCount) googlevideo) for proxy")

        // Populate the quality picker with the HLS variant heights from the master manifest.
        // These are the only formats guaranteed to work via the proxy — iOS adaptive rqh=1
        // streams are intentionally excluded from the picker.
        if !allVariants.isEmpty {
            hlsVariantURLs = allVariants
            wkHLSMasterURL = masterURL
            let syntheticFormats = allVariants.keys.sorted(by: >).map { h in
                VideoFormat(label: "\(h)p", width: 0, height: h, fps: 30,
                            mimeType: "video/mp4; codecs=\"avc1.640028\"",
                            url: allVariants[h], bitrate: nil)
            }
            availableFormats = syntheticFormats
            playerLog.notice("[webView/HLS] quality picker: \(syntheticFormats.map { $0.qualityLabel }.joined(separator: ", "))")
        }

        // 2b. Parse dubbed-audio language tracks from YT-EXT-AUDIO-CONTENT-ID attributes.
        //     YouTube encodes dubbed languages in #EXT-X-STREAM-INF lines (not #EXT-X-MEDIA
        //     TYPE=AUDIO), so loadMediaSelectionGroup returns nil. We parse them directly here
        //     and populate AudioTrackManager so the language selector appears immediately.
        let hlsLanguageTracks = parseHLSAudioLanguages(from: manifestText)
        playerLog.notice("[webView/HLS] YT-EXT-AUDIO-CONTENT-ID tracks: \(hlsLanguageTracks.count) — \(hlsLanguageTracks.map { $0.name }.joined(separator: ", "))")
        if !hlsLanguageTracks.isEmpty {
            audioManager.loadHLSVariantTracks(hlsLanguageTracks)
            // Wire language switching: when the user picks a track, reload the AVPlayerItem
            // with the proxy filtered for that language. The callback is cleared by reset()
            // when a new video loads.
            audioManager.onHLSLanguageChange = { [weak self] (track: AudioTrack?) in
                guard let self else { return }
                let savedPos = self.player.currentTime().seconds
                // Use contentID (the YT-EXT-AUDIO-CONTENT-ID value) for proxy filtering.
                // nil means original audio: for real originals that lack the attribute,
                // contentID is nil on the synthetic "Original" entry; for real originals
                // with the attribute (e.g. "en-US.4"), contentID equals the real value.
                // The "Auto" picker row passes track=nil → contentID=nil → original filter.
                let contentID = track?.contentID
                Task { [weak self] in
                    await self?.switchHLSLanguage(
                        to: contentID,
                        masterURL: masterURL,
                        manifestText: manifestText,
                        nSolver: nSolver,
                        webViewCookies: webViewCookies,
                        for: video,
                        seekTo: savedPos
                    )
                }
            }
        }

        // 3. Route through YTHLSProxyLoader using the MASTER manifest URL (not a per-quality
        //    variant URL). The proxy filters #EXT-X-STREAM-INF variants for the selected
        //    dubbed language (or original audio when none is selected). Without the proxy,
        //    AVPlayer would receive all N×M language+quality variant entries and could pick
        //    any language during ABR adaptation.
        guard let proxyURL = masterURL.proxyURL else {
            playerLog.error("❌ [webView/HLS] failed to build proxy URL for master")
            return false
        }
        // Determine the initial content ID: if the user has a saved language preference that
        // matches one of the HLS variant tracks, start with that language; otherwise nil (original).
        // Use contentID (not id) so the synthetic "Original" entry (id="yt-original-audio",
        // contentID=nil) correctly maps to nil → proxy keeps no-content-ID variants.
        let initialContentID: String?
        if let pref = settings.preferredAudioLanguage,
           let preferred = hlsLanguageTracks.first(where: { $0.languageCode == pref }) {
            initialContentID = preferred.contentID
        } else {
            initialContentID = nil
        }
        let langDisplay = initialContentID ?? "original"
        // fix20: Use the caller-supplied poToken (captured before wkHLSEarlyTask clears
        // extractedPoToken). With a non-nil poToken the proxy rewrites variant playlist URLs
        // to ytwebhls:// and injects ?pot=<token> into segment URLs, authenticating rqh=1
        // CDN requests without requiring googlevideo.com session cookies in the cookie jar.
        // Falls back to extractedPoToken in case the caller didn't supply one.
        let effectivePoToken = poToken ?? YouTubeWebViewHLSExtractor.shared.extractedPoToken
        let potDisplay = effectivePoToken.map { "\($0.count) chars" } ?? "nil"
        playerLog.notice("[webView/HLS] ✅ proxying master URL (lang=\(langDisplay), pot=\(potDisplay), YT-EXT-AUDIO-CONTENT-ID filter active)")
        let proxyLoader = YTHLSProxyLoader(ua: ua, nSolver: nSolver, webViewCookies: webViewCookies,
                                           selectedLanguageContentID: initialContentID,
                                           poToken: effectivePoToken)
        let asset = AVURLAsset(url: proxyURL)
        // Keep proxy loader alive for the lifetime of this asset
        asset.resourceLoader.setDelegate(proxyLoader, queue: DispatchQueue.global(qos: .userInitiated))
        // Store reference so ARC doesn't release the loader while AVPlayer uses the asset
        webHLSProxyLoader = proxyLoader

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        // Fast-start: require only 0.5 s of buffered content before readyToPlay fires
        // (matches the primary HLS path in loadAsync). Forward buffer is reset to system
        // default in the readyToPlay ramp task below.
        item.preferredForwardBufferDuration = 0.5
        // Fast-start ABR: cap initial variant at 360p so AVPlayer downloads the smallest
        // first segment, then ramp to preferred quality after readyToPlay.
        // Compute preferred height here so the ramp Task captures it.
        let preferredHeight: Int
        if settings.preferredQuality != .auto, let cap = settings.preferredQuality.maxHeight {
            preferredHeight = cap
        } else if let best = allVariants.keys.filter({ $0 >= 720 }).max()
                          ?? allVariants.keys.max() {
            preferredHeight = best
        } else {
            preferredHeight = 0
        }
        // Start at 360p (fast first-frame) regardless of preferred quality.
        item.preferredMaximumResolution = CGSize(width: 640, height: 360)
        playerLog.notice("[webView/HLS] fast-start ABR: initial cap 360p → ramp to \(preferredHeight > 0 ? "\(preferredHeight)p" : "Auto") after readyToPlay")
        // fix235: Final cancellation / video-identity check before touching the player.
        // A stale exhaustiveRetry task (cancelled by a subsequent load() or stop()) must not
        // call replaceCurrentItem — doing so would silently swap the visible video.
        guard !Task.isCancelled, currentVideo?.id == video.id else {
            playerLog.notice("⚠️ [webView/HLS] fix235: task cancelled or video changed (current=\(currentVideo?.id ?? "nil") expected=\(video.id)) — aborting replaceCurrentItem")
            return false
        }
        lastAttemptedStreamURL = masterURL
        player.replaceCurrentItem(with: item)
        itemObserverTask?.cancel()
        for await status in item.statusStream {
            switch status {
            case .readyToPlay:
                playerLog.notice("[benchmark] readyToPlay — webView/HLS — videoId=\(video.id) title=\(video.title)")
                playerLog.notice("✅ [webView/HLS] readyToPlay")
                // Refresh duration from AVPlayerItem — the YouTube API metadata may be
                // absent (nil) or inaccurate, leaving duration=0 and breaking scrubbing.
                let itemDur = item.duration.seconds
                if itemDur.isFinite && itemDur > 0 {
                    let prevDur = self.duration
                    self.duration = itemDur
                    playerLog.notice("[duration] updated from webView/HLS AVPlayerItem: \(String(format: "%.1f", itemDur))s (was \(String(format: "%.1f", prevDur))s)")
                } else if self.duration == 0 {
                    durationObserverTask?.cancel()
                    durationObserverTask = Task { [weak self, weak item] in
                        guard let self, let item else { return }
                        for await seconds in item.firstValidDurationStream {
                            guard !Task.isCancelled else { return }
                            let prev = self.duration
                            self.duration = seconds
                            playerLog.notice("[duration] deferred KVO update (webView/HLS): \(String(format: "%.1f", seconds))s (was \(String(format: "%.1f", prev))s)")
                            break
                        }
                    }
                }
                // Try the standard #EXT-X-MEDIA path (works if manifest has audio groups).
                // For YouTube's YT-EXT-AUDIO-CONTENT-ID format, loadAudioTracks returns nil
                // but tracks are already loaded via loadHLSVariantTracks above.
                loadAudioTracks(from: item)
                needsQuickStartup = false
                isLoading = false
                timeToPlayMs = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1000)
                lastSuccessfulStreamType = "webView/HLS"
                if timeToPlayMs > 4_000 {
                    CrashlyticsLogger.recordSlowVideoLoad(
                        videoId: video.id,
                        elapsedMs: timeToPlayMs,
                        streamType: "webView/HLS",
                        hasError: false
                    )
                }
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                qualityManager.isMuxedFallback = false
                // Fast-start quality ramp: first frame is on screen at 360p. Upgrade ABR hints
                // to preferred quality (same pattern as primary HLS path in loadAsync).
                Task { [weak self, weak item] in
                    try? await Task.sleep(for: .milliseconds(800))
                    guard let self, !Task.isCancelled else { return }
                    self.timeToHighQualityMs = Int(Date().timeIntervalSince(self.videoLoadStartedAt) * 1000)
                    item?.preferredForwardBufferDuration = 0
                    if preferredHeight > 0 {
                        item?.preferredMaximumResolution = CGSize(width: 7680, height: preferredHeight)
                        playerLog.notice("[webView/HLS] ABR ramp → \(preferredHeight)p + buffer unconstrained")
                    } else {
                        item?.preferredMaximumResolution = .zero
                        playerLog.notice("[webView/HLS] ABR ramp → Auto (unconstrained) + buffer unconstrained")
                    }
                }
                return true
            case .failed:
                let err = item.error?.localizedDescription ?? "nil"
                playerLog.error("❌ [webView/HLS] AVPlayerItem failed: \(err)")
                // If the CDN denied access (permission error), a fresh WKWebView extraction
                // will produce the same URL signed by the same CDN session → same 403.
                // Flag this so exhaustiveRetry skips the serial extraction entirely.
                if err.lowercased().contains("permission") || err.lowercased().contains("not have access") {
                    wkHLSPermissionDenied = true
                    playerLog.notice("[webView/HLS] CDN permission error — serial extraction will be skipped")
                }
                return false
            case .unknown: continue
            @unknown default: continue
            }
        }
        return false
    }

    /// Reloads the WKWebView HLS AVPlayerItem with the master manifest filtered for a
    /// dubbed-audio language (or original when contentID is nil). Called when the user
    /// selects an audio track from the picker via AudioTrackManager.onHLSLanguageChange.
    private func switchHLSLanguage(
        to contentID: String?,
        masterURL: URL,
        manifestText: String,
        nSolver: (unsolved: String, solved: String)?,
        webViewCookies: [HTTPCookie],
        for video: Video,
        seekTo position: Double
    ) async {
        let idDisplay = contentID ?? "original"
        playerLog.notice("[wkHLS/lang] switching to contentID=\(idDisplay)")

        // Update hlsVariantURLs so quality switching preserves the selected language.
        let langVariants = parseHLSVariantURLsForLanguage(contentID, from: manifestText,
                                                          baseURL: masterURL)
        if !langVariants.isEmpty {
            hlsVariantURLs = langVariants
            let variantSummary = langVariants.keys.sorted(by: >).map { "\($0)p" }.joined(separator: ", ")
            playerLog.notice("[wkHLS/lang] updated hlsVariantURLs: \(variantSummary)")
        }

        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        let proxyLoader = YTHLSProxyLoader(ua: ua, nSolver: nSolver, webViewCookies: webViewCookies,
                                           selectedLanguageContentID: contentID)
        guard let proxyURL = masterURL.proxyURL else {
            playerLog.error("❌ [wkHLS/lang] failed to build proxy URL")
            return
        }
        let asset = AVURLAsset(url: proxyURL)
        asset.resourceLoader.setDelegate(proxyLoader, queue: DispatchQueue.global(qos: .userInitiated))
        webHLSProxyLoader = proxyLoader

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        item.preferredForwardBufferDuration = 2.0
        if let best = langVariants.keys.filter({ $0 >= 720 }).max() ?? langVariants.keys.max(), best > 0 {
            item.preferredMaximumResolution = CGSize(width: 7680, height: best)
        }
        Task { [weak item] in
            try? await Task.sleep(for: .seconds(5))
            item?.preferredForwardBufferDuration = 0
        }

        player.replaceCurrentItem(with: item)
        for await status in item.statusStream {
            switch status {
            case .readyToPlay:
                let posStr = String(format: "%.1f", position)
                playerLog.notice("[benchmark] readyToPlay — wkHLS/lang — videoId=\(video.id) title=\(video.title)")
                playerLog.notice("✅ [wkHLS/lang] readyToPlay — seeking to \(posStr)s")
                if position > 0 {
                    let target = CMTime(seconds: position, preferredTimescale: 600)
                    await item.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                }
                player.rate = Float(settings.playbackSpeed)
                return
            case .failed:
                let err = item.error?.localizedDescription ?? "nil"
                playerLog.error("❌ [wkHLS/lang] AVPlayerItem failed: \(err)")
                return
            case .unknown: continue
            @unknown default: continue
            }
        }
    }

    /// Extracts all cookies from the WKWebView's httpCookieStore, including googlevideo.com
    /// cookies required for rqh=1-enforced CDN segment requests.
    private func extractWKWebViewCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let gvCount = cookies.filter { $0.domain.contains("googlevideo") }.count
                playerLog.notice("[webView/HLS] extracted \(cookies.count) cookies (\(gvCount) googlevideo) for proxy")
                cont.resume(returning: cookies)
            }
        }
    }

    /// Probes a cached WKWebView HLS master manifest URL with a lightweight HEAD request
    /// to detect expiry before constructing an AVPlayerItem.
    /// Returns `true` if the URL is still accessible (2xx/3xx); `false` on 4xx or timeout.
    private func isWKHLSURLValid(_ url: URL) async -> Bool {
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 8
        if let (_, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
           let http = response as? HTTPURLResponse {
            playerLog.notice("[wkHLS/probe] HEAD returned HTTP \(http.statusCode)")
            return http.statusCode < 400
        }
        playerLog.notice("[wkHLS/probe] HEAD probe timeout or failed — treating as expired")
        return false
    }

    /// Parses YouTube's HLS master manifest for dubbed-audio language tracks encoded via
    /// YT-EXT-AUDIO-CONTENT-ID attributes on #EXT-X-STREAM-INF lines.
    ///
    /// YouTube does NOT use standard #EXT-X-MEDIA:TYPE=AUDIO groups for dubbed content.
    /// Instead each quality level appears N times — once per audio language — with
    /// YT-EXT-AUDIO-CONTENT-ID="xx-XX.N" identifying the language. The original audio
    /// variant has no YT-EXT-AUDIO-CONTENT-ID and is NOT returned here.
    ///
    /// The YT-EXT-XTAGS attribute on each variant is base64-encoded protobuf containing
    /// "acont=original" or "acont=dubbed-auto" plus "lang=xx-XX". We use this to mark
    /// the `acont=original` track as isOriginal=true.
    ///
    /// Returns deduplicated AudioTrack array (original first if present, then dubbed).
    private func parseHLSAudioLanguages(from manifest: String) -> [AudioTrack] {
        SmartTubeIOSCore.parseHLSAudioLanguages(from: manifest)
    }

    /// Parses a map of stream height → variant URL from the HLS master manifest for a
    /// specific dubbed-audio content ID. Used by switchHLSLanguage to update hlsVariantURLs.
    /// If `contentID` is nil, returns original-audio variant URLs (no YT-EXT-AUDIO-CONTENT-ID).
    private func parseHLSVariantURLsForLanguage(
        _ contentID: String?,
        from manifest: String,
        baseURL: URL
    ) -> [Int: URL] {
        SmartTubeIOSCore.parseHLSVariantURLsForLanguage(contentID, from: manifest, baseURL: baseURL)
    }

    /// Extracts the value of a quoted HLS attribute (e.g. `ATTR="value"`) from a tag line.
    private func extractQuotedHLSAttribute(_ name: String, from line: String) -> String? {
        SmartTubeIOSCore.extractQuotedHLSAttribute(name, from: line)
    }

    /// Parses an HLS master M3U8 manifest and returns a map of stream height → variant URL
    /// for all streams present. Handles both absolute and relative URIs.
    /// Returns one URL per quality level — the first variant seen per height (original audio when
    /// available, first dubbed entry as fallback when the manifest omits no-CONTENT-ID variants).
    private func parseHLSAllVariants(from manifest: String, baseURL: URL) -> [Int: URL] {
        SmartTubeIOSCore.parseHLSAllVariants(from: manifest, baseURL: baseURL)
    }

    /// Parses an HLS master M3U8 manifest and returns the URL of the best stream at ≥ `minHeight`.
    /// Handles both absolute URIs and relative paths (resolved against `baseURL`).
    private func parseHLSBestVariant(from manifest: String, baseURL: URL, minHeight: Int) -> URL? {
        let result = SmartTubeIOSCore.parseHLSBestVariant(from: manifest, baseURL: baseURL, minHeight: minHeight)
        if let result {
            playerLog.notice("[webView/HLS] best variant ≥\(minHeight)p: \(result.absoluteString.prefix(80))")
        }
        return result
    }

    /// Proactively extracts and caches the WKWebView HLS master manifest URL for a neighbour
    /// video while the current video is already playing. Stores the result in VideoPreloadCache
    /// so that when the user swipes to the neighbour, exhaustiveRetry skips the 5–9 s
    /// WKWebView extraction step and plays from the cached URL directly.
    ///
    /// Skips silently if the URL is already cached or if extraction returns nil.
    func preExtractWKHLSForVideo(_ videoId: String) async {
        guard await VideoPreloadCache.shared.cachedWKHLSURL(for: videoId) == nil else {
            playerLog.notice("[wkHLS] pre-extract skipped — already cached for \(videoId)")
            return
        }
        playerLog.notice("[wkHLS] pre-extracting HLS URL for neighbour \(videoId)")
        guard let url = await YouTubeWebViewHLSExtractor.shared.extractHLSURL(videoId: videoId) else {
            playerLog.notice("[wkHLS] pre-extract returned nil for \(videoId)")
            return
        }
        await VideoPreloadCache.shared.store(wkHLSManifestURL: url, for: videoId)
        playerLog.notice("✅ [wkHLS] pre-extract done for \(videoId)")
    }
    #endif

    #if targetEnvironment(simulator)
    /// Loads a yt-dlp `hls_playlist` URL directly into AVPlayer. Kept for backward compatibility.
    private func tryYtDlpHLS(_ url: URL, for video: Video) async -> Bool {
        playerLog.notice("[ytDlp[sim]/HLS]: \(url.absoluteString.prefix(120))")
        let ua = "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)"
        let uaOpts: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]]
        let asset = AVURLAsset(url: url, options: uaOpts)
        let item  = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        item.preferredForwardBufferDuration = 2.0
        Task { [weak item] in
            try? await Task.sleep(for: .seconds(5))
            item?.preferredForwardBufferDuration = 0
        }
        player.replaceCurrentItem(with: item)
        itemObserverTask?.cancel()
        for await status in item.statusStream {
            switch status {
            case .readyToPlay:
                playerLog.notice("[benchmark] readyToPlay — ytDlp/HLS — videoId=\(video.id) title=\(video.title)")
                playerLog.notice("✅ [ytDlp[sim]/HLS] readyToPlay")
                needsQuickStartup = false
                isLoading = false
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                return true
            case .failed:
                let err = item.error?.localizedDescription ?? "nil"
                playerLog.error("❌ [ytDlp[sim]/HLS] AVPlayerItem failed: \(err)")
                return false
            case .unknown: continue
            @unknown default: continue
            }
        }
        return false
    }
    #endif

    // MARK: - Single-method probe (testing only)

    /// Exercises exactly one stream-fetching client for `video` and attempts to play.
    ///
    /// Called from `exhaustiveRetry` when `StreamMethodProbeSupport.forcedStreamMethod`
    /// is set (via `--uitesting-force-stream-method=<method>`).  The result — success or
    /// failure — is observable through the existing `player.titleLabel` /
    /// `player.errorBanner` accessibility identifiers so UI tests need no extra wiring.
    ///
    /// - Parameters:
    ///   - method: One of `StreamMethodProbeSupport.knownMethods`.
    ///   - video: The video to probe.
    func probeStreamMethod(_ method: String, video: Video) async {
        playerLog.notice("[probe] starting single-method probe: \(method) for \(video.id)")
        isLoading = true
        retryStatusMessage = "Probing \(method)…"

        do {
            let info: PlayerInfo

            switch method {
            case "ios":
                info = try await api.fetchPlayerInfo(videoId: video.id)

            case "ios-auth":
                info = try await api.fetchPlayerInfoiOSAuthenticated(videoId: video.id)

            case "tvembedded":
                info = try await api.fetchPlayerInfoTVEmbedded(videoId: video.id)

            case "tvauth":
                info = try await api.fetchPlayerInfoAuthenticated(videoId: video.id)

            case "websafari":
                info = try await api.fetchPlayerInfoWebSafari(videoId: video.id)

            case "mweb":
                info = try await api.fetchPlayerInfoMWEB(videoId: video.id)

            case "android":
                info = try await api.fetchPlayerInfoAndroid(videoId: video.id)

            case "android-vr":
                info = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)

            case "web-creator":
                info = try await api.fetchPlayerInfoWebCreator(videoId: video.id)

            case "web-auth":
                info = try await api.fetchPlayerInfoWebAuthenticated(videoId: video.id)

            #if canImport(WebKit)
            case "wkwebview-hls":
                let url = await YouTubeWebViewHLSExtractor.shared.serialExtract(videoId: video.id)
                let solver = YouTubeWebViewHLSExtractor.shared.extractedNSolver
                if let url, await tryWebViewHLS(url, nSolver: solver, for: video) {
                    probeStreamResult = "WKWebView-HLS"
                    playerLog.notice("[probe] ✅ wkwebview-hls succeeded for \(video.id)")
                } else {
                    playerLog.error("[probe] ❌ wkwebview-hls failed for \(video.id)")
                    error = APIError.unavailable("wkwebview-hls extraction failed")
                    isLoading = false
                }
                return
            #endif

            default:
                playerLog.error("[probe] unknown method '\(method)' — failing")
                error = APIError.unavailable("Unknown stream method '\(method)'")
                isLoading = false
                return
            }

            if await tryAllStreams(video: video, info: info, label: "probe/\(method)") {
                let desc = probeStreamDescription(for: info)
                probeStreamResult = desc
                playerLog.notice("[probe] ✅ \(method) succeeded for \(video.id) — \(desc)")
            } else {
                playerLog.error("[probe] ❌ \(method) returned no playable stream for \(video.id)")
                error = APIError.unavailable("No playable stream from \(method)")
                isLoading = false
            }
        } catch {
            playerLog.error("[probe] ❌ \(method) threw: \(error) for \(video.id)")
            self.error = error
            isLoading = false
        }
    }

    /// Returns a compact human-readable description of what a `PlayerInfo` offers:
    /// stream type + max video resolution. Used by `player.probeStreamResult` accessibility
    /// element so `StreamMethodProbeUITests` can capture the resolution per-test.
    private func probeStreamDescription(for info: PlayerInfo) -> String {
        let videoFormats = info.formats.filter {
            $0.mimeType.hasPrefix("video/") && !$0.mimeType.contains(", ") && $0.height > 0
        }
        let maxH = videoFormats.map(\.height).max() ?? 0
        let maxFPS = videoFormats.filter { $0.height == maxH }.map(\.fps).max() ?? 0
        let resLabel = maxH > 0 ? "\(maxH)p\(maxFPS > 30 ? "\(maxFPS)" : "")" : ""

        if info.hlsURL != nil {
            return resLabel.isEmpty ? "HLS" : "HLS \(resLabel)"
        }
        if maxH > 0 {
            let suffix = info.containsRqhAdaptiveFormats ? " rqh=1" : ""
            return "\(resLabel)\(suffix)"
        }
        // Muxed only
        let muxedFormats = info.formats.filter {
            $0.mimeType.hasPrefix("video/mp4") && $0.mimeType.contains(", ") && $0.height > 0
        }
        let muxedH = muxedFormats.map(\.height).max() ?? 0
        return muxedH > 0 ? "muxed \(muxedH)p" : "unknown"
    }
}

#if targetEnvironment(simulator)
/// Minimal `AVAssetResourceLoaderDelegate` that serves a pre-rewritten HLS variant playlist
/// via a custom `smarttubehls://` URL scheme. Simulator-only.
///
/// Background: `AVURLAsset(url: file://)` + `AVURLAssetHTTPHeaderFieldsKey` hangs indefinitely
/// in `.unknown` status — AVFoundation never transitions to `.readyToPlay` on the Simulator.
/// Routing the initial playlist fetch through `AVAssetResourceLoader` avoids the `file://` code
/// path while still letting AVPlayer request CDN segment URLs (`https://`) normally.
private final class HLSVariantProxy: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private let playlistData: Data

    init(playlistContent: String) {
        self.playlistData = playlistContent.data(using: .utf8) ?? Data()
    }

    /// Returns a unique `smarttubehls://` URL. Each call produces a new value to prevent caching.
    static func makeProxyURL() -> URL {
        let ts = UInt64(Date().timeIntervalSince1970 * 1_000)
        return URL(string: "smarttubehls://variant/\(ts).m3u8")!
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            // UTI for HLS / M3U8 playlists. AVFoundation uses this to decide how to parse
            // the returned bytes. "public.m3u-playlist" is the registered UTI for .m3u8.
            info.contentType = "public.m3u-playlist"
            info.contentLength = Int64(playlistData.count)
            info.isByteRangeAccessSupported = false
        }
        loadingRequest.dataRequest?.respond(with: playlistData)
        loadingRequest.finishLoading()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {}
}
#endif
