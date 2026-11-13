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
            Toggle(isOn: $store.settings.shortsFillScreen) { Text("Fill Screen", bundle: .module) }
                .accessibilityIdentifier(AccessibilityID.Settings.shortsFillScreenToggle)
            Toggle(isOn: shortsSponsorBlock) { Text("SponsorBlock for Shorts", bundle: .module) }
                .disabled(!store.settings.sponsorBlockEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.shortsSponsorBlockToggle)
        } header: {
            Text("Shorts", bundle: .module)
        }
    }

    /// Shows off while SponsorBlock itself is off, without changing the stored
    /// choice, so turning SponsorBlock back on brings the Shorts setting back.
    private var shortsSponsorBlock: Binding<Bool> {
        Binding(
            get: { store.settings.shortsSponsorBlockActive },
            set: { store.settings.shortsSponsorBlock = $0 })
    }
}
#endif
