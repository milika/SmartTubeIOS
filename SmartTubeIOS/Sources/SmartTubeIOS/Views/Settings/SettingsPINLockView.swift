import SmartTubeIOSCore
import SwiftUI

// MARK: - SettingsPINLockView (#126)
//
// Shown by SettingsView in place of the settings Form whenever a PIN is configured and
// the current visit hasn't been unlocked yet (see SettingsView.body's overlay logic).
// Verifies the entered digits against `AppSettings.settingsPINHash` and calls
// `onUnlock()` on a match; on a mismatch it shows an error and clears the pad so the
// user can retry, without ever getting access to the settings underneath.

struct SettingsPINLockView: View {
    let expectedHash: String
    let onUnlock: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        PINKeypadView(
            title: L10n.string("Settings Locked"),
            subtitle: L10n.string("Enter PIN to continue"),
            errorMessage: errorMessage
        ) { pin in
            if SettingsPINHasher.hash(pin) == expectedHash {
                errorMessage = nil
                onUnlock()
            } else {
                errorMessage = L10n.string("Incorrect PIN")
            }
        }
        .accessibilityIdentifier("settingsPINLock")
    }
}
