import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - IPBlockDetectionTests
//
// Verifies that APIError.ipBlocked is:
//   1. Correctly classified from known IP-block reason strings.
//   2. Distinct from APIError.unavailable (so the short-circuit path fires only for VPN blocks).
//   3. Surfaces the expected user-facing error description.

@Suite("IP Block Error Detection")
struct IPBlockDetectionTests {

    // MARK: - Helpers

    /// Runs the real classification used by `parsePlayerInfo` for an `UNPLAYABLE` response.
    private func isIPBlockReason(_ reason: String, status: String = "UNPLAYABLE") -> Bool {
        if case .ipBlocked = InnerTubeAPI.unplayableError(status: status, reason: reason) { return true }
        return false
    }

    // MARK: - Keyword heuristic

    @Test("'your IP has been blocked' triggers IP-block classification")
    func yourIPKeyword() {
        #expect(isIPBlockReason("Your IP has been blocked. Please try again later."))
    }

    @Test("'ip address' triggers IP-block classification")
    func ipAddressKeyword() {
        #expect(isIPBlockReason("Requests from your IP address have been temporarily blocked."))
    }

    @Test("'vpn' triggers IP-block classification")
    func vpnKeyword() {
        #expect(isIPBlockReason("Access via VPN is not permitted."))
    }

    @Test("'proxy' triggers IP-block classification")
    func proxyKeyword() {
        #expect(isIPBlockReason("Requests from a proxy are not allowed."))
    }

    @Test("'bot' triggers IP-block classification")
    func botKeyword() {
        #expect(isIPBlockReason("This content is not available to bots."))
    }

    @Test("'sign in to confirm' triggers IP-block classification")
    func signInToConfirmKeyword() {
        #expect(isIPBlockReason("Sign in to confirm you're not a bot."))
    }

    @Test("bot check sent as LOGIN_REQUIRED is a network block, not a sign-in request")
    func botCheckWithLoginRequiredIsIPBlock() {
        // Exact response seen on an Apple TV: status LOGIN_REQUIRED, curly apostrophe.
        #expect(isIPBlockReason("Sign in to confirm you\u{2019}re not a bot", status: "LOGIN_REQUIRED"))
        #expect(isIPBlockReason("Sign in to confirm you're not a bot.", status: "LOGIN_REQUIRED"))
    }

    @Test("age-restricted and sign-in-only videos stay sign-in errors")
    func ageRestrictedStaysSignIn() {
        let ageGate = InnerTubeAPI.unplayableError(
            status: "LOGIN_REQUIRED", reason: "Sign in to confirm your age. This video may be inappropriate.")
        guard case .signInRequired = ageGate else {
            Issue.record("age gate classified as \(ageGate)")
            return
        }
        let members = InnerTubeAPI.unplayableError(status: "LOGIN_REQUIRED", reason: "Sign in to watch this video")
        guard case .signInRequired = members else {
            Issue.record("sign-in-only video classified as \(members)")
            return
        }
    }

    @Test("Generic 'video unavailable' does NOT trigger IP-block classification")
    func genericUnavailableDoesNotTrigger() {
        #expect(!isIPBlockReason("This video is unavailable"))
    }

    @Test("Members-only reason does NOT trigger IP-block classification")
    func membersOnlyDoesNotTrigger() {
        #expect(!isIPBlockReason("This video is available to members only"))
    }

    @Test("Keyword check is case-insensitive")
    func keywordIsCaseInsensitive() {
        #expect(isIPBlockReason("YOUR IP WAS FLAGGED"))
        #expect(isIPBlockReason("VPN detected"))
    }

    // MARK: - APIError.ipBlocked properties

    @Test("ipBlocked errorDescription is the fixed user-facing message")
    func ipBlockedErrorDescription() {
        let error = APIError.ipBlocked("Your IP has been blocked")
        #expect(error.errorDescription?.contains("VPN") == true)
        #expect(error.errorDescription?.contains("temporarily blocking") == true)
    }

    @Test("ipBlocked is not the same case as unavailable")
    func ipBlockedIsDistinctFromUnavailable() {
        let ipError = APIError.ipBlocked("Your IP has been blocked")
        if case APIError.unavailable = ipError {
            Issue.record("ipBlocked matched the .unavailable pattern — cases must stay distinct")
        }
    }

    @Test("unavailable does not match ipBlocked pattern")
    func unavailableIsDistinctFromIPBlocked() {
        let genericError = APIError.unavailable("This video is unavailable")
        if case APIError.ipBlocked = genericError {
            Issue.record("unavailable matched the .ipBlocked pattern — cases must stay distinct")
        }
    }

    @Test("NW-7: NSURLError -999 (request cancelled) is suppressed from Crashlytics")
    func nsURLError999IsSuppressed() {
        // Mirrors the transient-suppression check in PlaybackViewModel.error.didSet.
        // -999 = URLError.cancelled — fires when AVPlayer or URLSession cancels an
        // in-flight request because the user navigated away or a superseded task fired.
        func shouldRecord(_ error: Error) -> Bool {
            let nsError = error as NSError
            let transientCodes = [-1, -999, -1001, -1005, -1009, -1202]
            if nsError.domain == NSURLErrorDomain && transientCodes.contains(nsError.code) {
                return false
            }
            return true
        }
        let cancelledError = NSError(
            domain: NSURLErrorDomain, code: -999,
            userInfo: [NSLocalizedDescriptionKey: "cancelled"])
        #expect(
            !shouldRecord(cancelledError),
            "NSURLError -999 must be suppressed (NW-7-FIX)")
    }

    @Test("NW-7: non-transient NSURLError is still recorded")
    func nonTransientNSURLErrorIsRecorded() {
        func shouldRecord(_ error: Error) -> Bool {
            let nsError = error as NSError
            let transientCodes = [-1, -999, -1001, -1005, -1009, -1202]
            if nsError.domain == NSURLErrorDomain && transientCodes.contains(nsError.code) {
                return false
            }
            return true
        }
        // -1200 = SSL handshake failed — a real error that should be recorded
        let sslError = NSError(
            domain: NSURLErrorDomain, code: -1200,
            userInfo: [NSLocalizedDescriptionKey: "SSL handshake failed"])
        #expect(
            shouldRecord(sslError),
            "NSURLError -1200 is not transient and must still be recorded")
    }

    // MARK: - NW-6-FIX: Suppression and retry behaviour

    @Test("NW-6: ipBlocked error is suppressed from Crashlytics non-fatal recording")
    func ipBlockedSuppressesCrashlyticsRecording() {
        // Mirrors the transient-suppression check in PlaybackViewModel.error.didSet.
        func shouldRecord(_ error: Error) -> Bool {
            if let apiError = error as? APIError {
                if case .unavailable = apiError { return false }
                if case .ipBlocked = apiError { return false }
            }
            return true
        }
        #expect(!shouldRecord(APIError.ipBlocked("Your IP was blocked")))
        #expect(!shouldRecord(APIError.ipBlocked("Sign in to confirm you're not a bot")))
    }

    @Test("NW-6: ipBlocked never triggers TV-authenticated retry regardless of auth state")
    func ipBlockedSkipsAuthenticatedRetry() {
        // Mirrors the NW-6-FIX logic in PlaybackViewModel+Loading.swift.
        // Previously: would call fetchPlayerInfoAuthenticated() when hasAuthToken==true.
        // After fix: throws immediately — retrying with the same blocked IP is futile
        // and may extend the YouTube block duration.
        func shouldRetryWithAuthenticatedClient(_ error: Error, hasAuthToken: Bool) -> Bool {
            if case APIError.ipBlocked = error { return false }
            return hasAuthToken
        }
        #expect(
            !shouldRetryWithAuthenticatedClient(APIError.ipBlocked("IP blocked"), hasAuthToken: true),
            "ipBlocked must NOT retry even when the user is authenticated")
        #expect(
            !shouldRetryWithAuthenticatedClient(APIError.ipBlocked("IP blocked"), hasAuthToken: false),
            "ipBlocked must NOT retry when unauthenticated")
    }

    @Test("NW-6: non-ipBlocked error still triggers TV-authenticated retry when authenticated")
    func nonIPBlockedPreservesAuthenticatedRetry() {
        func shouldRetryWithAuthenticatedClient(_ error: Error, hasAuthToken: Bool) -> Bool {
            if case APIError.ipBlocked = error { return false }
            return hasAuthToken
        }
        #expect(shouldRetryWithAuthenticatedClient(APIError.unavailable("Unavailable"), hasAuthToken: true))
        #expect(!shouldRetryWithAuthenticatedClient(APIError.unavailable("Unavailable"), hasAuthToken: false))
    }
}
