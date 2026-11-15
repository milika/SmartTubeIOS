import SmartTubeIOSCore
import SwiftUI

// MARK: - ParentalControlsSheet (#126)
//
// Handles all three PIN-management flows from SettingsView's "Parental Controls"
// section: setting a PIN for the first time, changing it, and removing it. Change and
// remove both require the *current* PIN first — otherwise anyone with the app open
// (which is exactly who this feature is meant to gate) could clear the lock without
// knowing the PIN, defeating the point.

enum ParentalControlsMode: Identifiable, Hashable {
    case set
    case change
    case remove

    var id: Self { self }
}

struct ParentalControlsSheet: View {
    let mode: ParentalControlsMode
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case verifyCurrent
        case enterNew
        case confirmNew(firstPIN: String)
    }

    @State private var step: Step
    @State private var errorMessage: String?

    init(mode: ParentalControlsMode) {
        self.mode = mode
        _step = State(initialValue: mode == .set ? .enterNew : .verifyCurrent)
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("Cancel")) { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .verifyCurrent:
            PINKeypadView(
                title: L10n.string("Enter Current PIN"),
                errorMessage: errorMessage
            ) { pin in
                guard SettingsPINHasher.hash(pin) == store.settings.settingsPINHash else {
                    errorMessage = L10n.string("Incorrect PIN")
                    return
                }
                errorMessage = nil
                switch mode {
                case .change:
                    step = .enterNew
                case .remove:
                    store.settings.settingsPINHash = nil
                    dismiss()
                case .set:
                    break  // unreachable — .set starts at .enterNew
                }
            }
            .accessibilityIdentifier("parentalControls.verifyCurrent")

        case .enterNew:
            PINKeypadView(
                title: L10n.string("Enter New PIN"),
                errorMessage: errorMessage
            ) { pin in
                errorMessage = nil
                step = .confirmNew(firstPIN: pin)
            }
            .accessibilityIdentifier("parentalControls.enterNew")

        case .confirmNew(let firstPIN):
            PINKeypadView(
                title: L10n.string("Confirm New PIN"),
                errorMessage: errorMessage
            ) { pin in
                guard pin == firstPIN else {
                    errorMessage = L10n.string("PINs didn't match. Try again.")
                    step = .enterNew
                    return
                }
                store.settings.settingsPINHash = SettingsPINHasher.hash(pin)
                dismiss()
            }
            .accessibilityIdentifier("parentalControls.confirmNew")
        }
    }
}
