import SmartTubeIOSCore
import SwiftUI

// MARK: - Chapters overlay (#10, closes #68/#105)
//
// Mirrors CommentsOverlayView's dim-backdrop bottom sheet. Lets the user tap a
// chapter to jump directly to it, instead of only stepping prev/next or reading
// the chapter name off a scrub-bar tick mark.

/// Dim-backdrop bottom sheet listing a video's chapters; tapping one calls `onSelect`.
struct ChaptersOverlayView: View {
    let chapters: [Chapter]
    let onSelect: (Chapter) -> Void
    let onDismiss: () -> Void
    var accessibilityId: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Chapters", bundle: L10n.bundle)
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 4)
                Divider()
                if chapters.isEmpty {
                    Text("No chapters available.", bundle: L10n.bundle)
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(chapters) { chapter in
                                Button {
                                    onSelect(chapter)
                                } label: {
                                    HStack {
                                        Text(chapter.title)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(formatDuration(chapter.startTime))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("tosPlayer.chaptersOverlay.chapter.\(chapter.id)")
                                if chapter.id != chapters.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 400)
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 8)
            .safeAreaPadding(.horizontal)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier(accessibilityId)
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifier(_ id: String?) -> some View {
        if let id {
            self.accessibilityIdentifier(id)
        } else {
            self
        }
    }
}
