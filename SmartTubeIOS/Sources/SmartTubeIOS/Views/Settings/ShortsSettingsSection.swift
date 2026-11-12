import SmartTubeIOSCore
import SwiftUI

#if os(iOS)
/// Settings › Shorts. Auto-scroll is also in the Shorts player's ⋯ sheet.
struct ShortsSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Toggle(isOn: $store.settings.shortsAutoScroll) { Text("Auto-scroll", bundle: .module) }
                .accessibilityIdentifier(AccessibilityID.Settings.shortsAutoScrollToggle)
        } header: {
            Text("Shorts", bundle: .module)
        } footer: {
            Text("Automatically scroll to the next Short when one ends. When off, Shorts loop.", bundle: .module)
        }
        Section {
            Toggle(isOn: $store.settings.shortsFillScreen) { Text("Fill Screen", bundle: .module) }
                .accessibilityIdentifier(AccessibilityID.Settings.shortsFillScreenToggle)
        } footer: {
            Text(
                "Zoom Shorts in so the video starts at the top of the screen, behind the status bar, like the YouTube app. The sides are cropped.",
                bundle: .module)
        }
        Section {
            Toggle(isOn: $store.settings.shortsSponsorBlock) { Text("SponsorBlock for Shorts", bundle: .module) }
                .disabled(!store.settings.sponsorBlockEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.shortsSponsorBlockToggle)
        } footer: {
            Text(
                "Skip SponsorBlock segments in Shorts too, using your SponsorBlock categories. Needs SponsorBlock turned on.",
                bundle: .module)
        }
    }
}
#endif
