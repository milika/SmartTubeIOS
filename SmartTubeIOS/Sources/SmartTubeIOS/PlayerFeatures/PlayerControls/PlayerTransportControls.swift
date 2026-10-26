#if !os(tvOS)
import SwiftUI

// MARK: - PlayerIconButton
//
// Shared circular icon button used by the direct player and the TOS transport
// overlay. `backgroundOpacity == 0` gives the borderless centre transport
// buttons; the default 0.4 matches the existing top-bar buttons.
struct PlayerIconButton: View {
    let systemName: String
    let accessibilityIdentifier: String
    var accessibilityLabel: String? = nil
    var iconSize: CGFloat = 20
    var padding: CGFloat = 9
    var backgroundOpacity: Double = 0.4
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .padding(padding)
                .background {
                    if backgroundOpacity > 0 {
                        Circle().fill(.black.opacity(backgroundOpacity))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

// MARK: - PlayerQuickAccessPill
//
// Shared compact pill used by the quick-access row (speed / quality /
// captions / audio track / sleep timer).
struct PlayerQuickAccessPill: View {
    let systemImage: String
    let label: String
    let accessibilityIdentifier: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.18))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
#endif
