#if !os(tvOS)
import Foundation
import Testing

@testable import SmartTubeIOS

// MARK: - TOSSignInURLTests (#158)
//
// On a flagged IP the embed shows "Sign in to confirm you're not a bot". Its button opens a
// Google sign-in page, which the TOS player now turns into a fallback to the standard player.

@Suite("TOSPlayerViewModel.isSignInURL (#158)")
struct TOSSignInURLTests {

    @Test(
        "sign-in pages are detected",
        arguments: [
            "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com",
            "https://accounts.google.com/v3/signin/identifier?continue=x",
            "https://www.youtube.com/signin?action_handle_signin=true&next=%2Fwatch",
            "https://m.youtube.com/ServiceLogin",
            "https://www.google.com/ServiceLogin?passive=true",
        ])
    func detectsSignIn(_ string: String) throws {
        #expect(TOSPlayerViewModel.isSignInURL(try #require(URL(string: string))))
    }

    @Test(
        "embed and ordinary pages are not sign-in",
        arguments: [
            "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.example.com/",
            "https://www.google.com/search?q=signin",
            "https://notyoutube.com/signin",
            "about:blank",
            "https://accounts.youtube.com/accounts/CheckConnection?pmpo=https%3A%2F%2Faccounts.google.com",
            "https://accounts.google.com/RotateCookiesPage?origin=https://www.youtube.com",
            "https://accounts.youtube.com/accounts/SetSID",
        ])
    func ignoresOtherPages(_ string: String) throws {
        #expect(!TOSPlayerViewModel.isSignInURL(try #require(URL(string: string))))
    }

    @Test("signInRequired is fatal, so the view falls back to the standard player")
    func signInRequiredIsFatal() {
        #expect(TOSPlayerError.signInRequired.isFatal)
    }
}
#endif
