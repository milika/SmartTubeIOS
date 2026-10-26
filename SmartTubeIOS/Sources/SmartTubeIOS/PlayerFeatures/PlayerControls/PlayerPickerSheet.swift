#if !os(tvOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - PlayerPickerOption

/// Presentation-only row model shared by the direct player and the TOS
/// transport overlay. Domain models (`VideoFormat`, `CaptionTrack`,
/// `AudioTrack`, TOS quality/track options) are mapped into this at the
/// boundary so the sheet never depends on a particular playback engine.
struct PlayerPickerOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let isSelected: Bool

    init(id: String, title: String, subtitle: String? = nil, isSelected: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
    }
}

// MARK: - PlayerPickerSheet

/// Generic bottom sheet used for quality, speed, captions, audio track and
/// sleep-timer selection. Mirrors the direct player's existing sheet layout.
/// Render it inside the player's ZStack — never as a UIKit `.sheet` — so
/// presenting/dismissing it cannot tear down playback.
struct PlayerPickerSheet: View {
    let title: String
    let options: [PlayerPickerOption]
    let accessibilityIdentifier: String
    let onSelect: (PlayerPickerOption) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack {
                    Button("Cancel", action: onDismiss)
                        .padding()
                    Spacer()
                    Text(title)
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 70, height: 44)
                }
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.title)
                                            .foregroundStyle(.primary)
                                        if let subtitle = option.subtitle {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if option.isSelected {
                                        Image(systemName: AppSymbol.checkmark)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(accessibilityIdentifier).option.\(option.id)")
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .frame(maxWidth: sheetMaxWidth)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier(accessibilityIdentifier)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
    }

    private var sheetMaxWidth: CGFloat {
        #if os(iOS)
        min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.8
        #else
        460
        #endif
    }
}
#endif
