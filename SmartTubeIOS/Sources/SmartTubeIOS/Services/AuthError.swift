import Foundation
import SmartTubeIOSCore

// MARK: - AuthError

public enum AuthError: LocalizedError {
    case cancelled
    case missingCode
    case tokenExchangeFailed
    case notSignedIn
    case configurationError
    case deviceCodeRequestFailed
    case authorizationPending
    case slowDown
    case deviceCodeExpired

    public var errorDescription: String? {
        switch self {
        case .cancelled: return L10n.string("Sign-in was cancelled")
        case .missingCode: return L10n.string("OAuth code was missing from callback")
        case .tokenExchangeFailed: return L10n.string("Failed to exchange code for tokens")
        case .notSignedIn: return L10n.string("You are not signed in")
        case .configurationError: return L10n.string("OAuth credentials could not be obtained")
        case .deviceCodeRequestFailed:
            return L10n.string("Could not start sign-in. Check your internet connection.")
        case .authorizationPending: return L10n.string("Waiting for authorisation…")
        case .slowDown: return L10n.string("Too many requests — slowing down")
        case .deviceCodeExpired: return L10n.string("The sign-in code expired. Please try again.")
        }
    }
}
