import SmartTubeIOSCore
import SwiftUI

// MARK: - SponsorSegment.Category + SwiftUI color
//
// Maps each SponsorBlock category to its canonical colour.
// Mirrors the colour values used in Android's SponsorBlockData.

extension SponsorSegment.Category {
    /// The representative SwiftUI Color for this category.
    var color: Color {
        switch self {
        case .sponsor: return Color(red: 0.00, green: 0.83, blue: 0.00)  // #00d400
        case .selfPromo: return Color(red: 1.00, green: 1.00, blue: 0.00)  // #ffff00
        case .interaction: return Color(red: 0.80, green: 0.00, blue: 1.00)  // #cc00ff
        case .intro: return Color(red: 0.00, green: 1.00, blue: 1.00)  // #00ffff
        case .outro: return Color(red: 0.01, green: 0.01, blue: 0.93)  // #0202ed
        case .preview: return Color(red: 0.00, green: 0.56, blue: 0.84)  // #008fd6
        case .filler: return Color(red: 0.45, green: 0.00, blue: 0.67)  // #7300ab
        case .musicOfftopic: return Color(red: 1.00, green: 0.60, blue: 0.00)  // #ff9900
        case .poiHighlight: return Color(red: 1.00, green: 0.09, blue: 0.52)  // #ff1684
        }
    }

    /// Human-readable label shown in the skip toast and settings UI.
    var displayName: String {
        switch self {
        case .sponsor: return L10n.string("Sponsor")
        case .selfPromo: return L10n.string("Self-Promotion")
        case .interaction: return L10n.string("Interaction Reminder")
        case .intro: return L10n.string("Intro/Recap")
        case .outro: return L10n.string("Outro/Credits")
        case .preview: return L10n.string("Preview/Hook")
        case .filler: return L10n.string("Filler Tangent")
        case .musicOfftopic: return L10n.string("Music (Off-Topic)")
        case .poiHighlight: return L10n.string("Highlight")
        }
    }
}
