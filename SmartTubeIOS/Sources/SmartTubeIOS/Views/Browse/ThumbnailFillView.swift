import SwiftUI

// MARK: - ThumbnailFillView
//
// Loads a thumbnail URL and fills its frame with the image, cropped to fit
// (scaledToFill + clipped). Falls back through `fallbackURLs` on load error,
// including an HTTP error status (see `CheckedAsyncImage`).
//
// Uses GeometryReader to give the image explicit pixel dimensions so that
// scaledToFill is always constrained to exactly the offered frame — the only
// reliable way to prevent SwiftUI layout bleed with fill-mode images.

struct ThumbnailFillView: View {
    /// Primary URL to try first.
    let primaryURL: URL?
    /// Ordered fallbacks tried after `primaryURL` fails.
    var fallbackURLs: [URL] = []
    /// Shown while loading and once every URL has failed.
    var placeholder: Color = .secondary.opacity(0.15)
    /// Overlays a spinner on the placeholder while loading.
    var showsProgress = true

    @State private var fallbackIndex: Int = -1

    private var activeURL: URL? {
        if fallbackIndex < 0 { return primaryURL ?? fallbackURLs.first }
        guard fallbackIndex < fallbackURLs.count else { return nil }
        return fallbackURLs[fallbackIndex]
    }

    var body: some View {
        GeometryReader { geo in
            CheckedAsyncImage(url: activeURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                case .failure:
                    placeholder
                        .onAppear(perform: advance)
                default:
                    placeholder
                        .overlay {
                            if showsProgress { ProgressView().tint(.white) }
                        }
                }
            }
        }
        // Reset fallback chain when the primary URL changes (new video reused in cell).
        .task(id: primaryURL) { fallbackIndex = -1 }
    }

    private func advance() {
        var next = fallbackIndex < 0 ? 0 : fallbackIndex + 1
        // A nil primary already showed fallbackURLs[0].
        if fallbackIndex < 0, primaryURL == nil { next = 1 }
        if next < fallbackURLs.count { fallbackIndex = next }
    }
}
