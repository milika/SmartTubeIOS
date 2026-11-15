import SmartTubeIOSCore
import SwiftUI

// MARK: - Comments overlay
//
// Shared between PlayerView (standard player, including tvOS) and
// TOSPlayerView — both rendered an identical dim-backdrop bottom sheet
// listing `CommentRowView`s. tvOS-only focus handling stays behind
// `#if os(tvOS)` since PlayerView renders this on tvOS too.

/// Dim-backdrop bottom sheet listing video comments, or a loading/empty state.
struct CommentsOverlayView: View {
    let comments: [Comment]
    let isLoading: Bool
    let onDismiss: () -> Void
    #if os(tvOS)
    var focusNamespace: Namespace.ID
    #endif
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
                    Text("Comments", bundle: L10n.bundle)
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 4)
                Divider()
                if isLoading {
                    ProgressView()
                        .padding(40)
                } else if comments.isEmpty {
                    Text("No comments available.", bundle: L10n.bundle)
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(comments) { comment in
                                CommentRowView(comment: comment)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 400)
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            #if os(tvOS)
            .focusScope(focusNamespace)
            .onExitCommand { onDismiss() }
            #endif
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
