import SmartTubeIOSCore
import SwiftUI

#if os(iOS)
/// Settings › Shorts. The same toggle is also in the Shorts player's ⋯ sheet.
struct ShortsSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Toggle("Auto-scroll", isOn: $store.settings.shortsAutoScroll)
                .accessibilityIdentifier(AccessibilityID.Settings.shortsAutoScrollToggle)
        } header: {
            Text("Shorts")
        } footer: {
            Text("Automatically scroll to the next Short when one ends. When off, Shorts loop.")
        }
    }
}
#endif
