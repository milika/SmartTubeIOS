import ActivityKit
import SwiftUI
import WidgetKit
import CasioClockWidget
import SmartTubeIOSCore

// Downloading is compiled out (App Store guideline 5.2.3). Define ENABLE_DOWNLOADS to build it.
#if ENABLE_DOWNLOADS
// MARK: - DownloadLiveActivity
//
// Live Activity widget displayed in the Dynamic Island and on the Lock Screen
// while VideoDownloadService is downloading a video.
//
// Dynamic Island compact:  progress arc + "Downloading" label
// Dynamic Island minimal:  just the arc
// Lock Screen banner:      title + phase label + progress bar

@available(iOS 16.1, *)
struct DownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            // Lock Screen / StandBy banner
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long press)
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.down.to.line.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: context.state.phase == .downloading
                                  ? context.state.progress : 1)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 32, height: 32)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.videoTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.state.phase.displayLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.to.line.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            } compactTrailing: {
                // Circular progress arc
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: context.state.phase == .downloading
                              ? context.state.progress : 1)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
            } minimal: {
                Image(systemName: "arrow.down.to.line.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Lock Screen Banner View

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<DownloadActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.to.line.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.videoTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(context.state.phase.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if context.state.phase == .downloading {
                    ProgressView(value: context.state.progress)
                        .tint(.primary)
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
        .activitySystemActionForegroundColor(.primary)
    }
}

// MARK: - Phase display label

@available(iOS 16.1, *)
private extension DownloadActivityAttributes.DownloadContentState.Phase {
    var displayLabel: String {
        switch self {
        case .fetching:    return "Preparing download…"
        case .downloading: return "Downloading…"
        case .saving:      return "Saving to Photos…"
        case .done:        return "Saved to Photos"
        case .failed:      return "Download failed"
        }
    }
}

#endif  // ENABLE_DOWNLOADS

// MARK: - Widget Bundle entry point

@available(iOS 16.1, *)
@main
struct SmartTubeDownloadWidgetBundle: WidgetBundle {
    var body: some Widget {
        // A widget extension needs at least one StaticConfiguration widget, or SpringBoard
        // fails with "Failed to get descriptors for extensionBundleID". The Home widget is it.
        HomeFeedWidget()
        // Experimental: self-contained package Widgets/CasioClockWidget — remove these lines
        // and the package dependency to drop it.
        CasioF91WWidget()
        CasioA158WWidget()
        CasioGMWB5000Widget()
        #if ENABLE_DOWNLOADS
        DownloadLiveActivityWidget()
        #endif
    }
}
