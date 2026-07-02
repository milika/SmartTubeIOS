import Foundation
import AVFoundation
import Testing
@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - PerVideoQualityOverrideTests
//
// The quality picker's per-video pick must be temporary: it overrides the
// persisted default (AppSettings.preferredQuality) for the current video only.
// PlaybackQualityManager records the pick in `perVideoQuality` (survives
// CDN-failure reverts of `selectedFormat`) and exposes `effectiveQuality`
// (per-video pick ?? persisted default) for recovery/stream-selection paths.

// MARK: - Mocks

private final class MockPlayer: PlayerItemSwappable {
    var rate: Float = 0
    func replaceCurrentItem(with item: AVPlayerItem?) {}
}

@MainActor
private final class MockQualityDelegate: QualityContext, QualityEventHandler {
    var playerInfo: PlayerInfo? = nil
    var settings = AppSettings()
    var currentVideo: Video? = nil
    var currentTime: TimeInterval = 0
    var toastMessage: String? = nil
    var isSwappingItem = false
    var isQualityChangePending = false
    func qualityItemDidBecomeReady(_ item: AVPlayerItem, seekTo: TimeInterval) {}
    func qualityItemDidFail(error: Error?, quality: AppSettings.VideoQuality, hasAppliedH264Cap: Bool) async {}
    func qualitySelectDASHFormat(videoURL: URL, audioURL: URL, seekTo: TimeInterval) async {}
}

// MARK: - Tests

@Suite("Per-video quality override")
struct PerVideoQualityOverrideTests {

    private func makeFormat(height: Int) -> VideoFormat {
        VideoFormat(
            label: "\(height)p",
            width: height * 16 / 9, height: height, fps: 30,
            mimeType: "video/mp4; codecs=\"avc1.640028\"",
            url: URL(string: "https://example.com/\(height)")
        )
    }

    @MainActor
    private func makeManager(default quality: AppSettings.VideoQuality)
        -> (PlaybackQualityManager, MockQualityDelegate) {
        let mgr = PlaybackQualityManager(player: MockPlayer())
        let delegate = MockQualityDelegate()
        delegate.settings.preferredQuality = quality
        mgr.delegate = delegate
        return (mgr, delegate)  // caller keeps delegate alive (mgr.delegate is weak)
    }

    @Test("Picking a format records perVideoQuality and leaves the default untouched")
    @MainActor
    func pickRecordsIntentWithoutTouchingDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(makeFormat(height: 720))
        #expect(mgr.perVideoQuality == .q720)
        #expect(delegate.settings.preferredQuality == .q480)
        #expect(mgr.effectiveQuality == .q720)
    }

    @Test("Explicitly picking Auto overrides a non-auto default")
    @MainActor
    func explicitAutoOverridesDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(nil)
        _ = delegate  // keep weak delegate alive through the assertions
        #expect(mgr.perVideoQuality == .auto)
        #expect(mgr.effectiveQuality == .auto)
    }

    @Test("With no pick, effectiveQuality falls back to the persisted default")
    @MainActor
    func noPickFallsBackToDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        _ = delegate
        #expect(mgr.perVideoQuality == nil)
        #expect(mgr.effectiveQuality == .q480)
    }

    @Test("reset() clears the per-video pick — next video starts at the default")
    @MainActor
    func resetClearsPerVideoPick() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(makeFormat(height: 1080))
        mgr.reset()
        _ = delegate
        #expect(mgr.perVideoQuality == nil)
        #expect(mgr.effectiveQuality == .q480)
    }

    @Test("setSelectedFormatForCurrentPreference prefers the per-video pick over the default")
    @MainActor
    func cdnRevertRestoresPerVideoPick() {
        let (mgr, delegate) = makeManager(default: .q1080)
        mgr.availableFormats = [makeFormat(height: 1080), makeFormat(height: 720), makeFormat(height: 480)]
        mgr.selectFormat(makeFormat(height: 720))
        mgr.selectedFormat = nil  // simulate CDN-failure revert
        mgr.setSelectedFormatForCurrentPreference()
        _ = delegate
        #expect(mgr.selectedFormat?.height == 720)
    }

    @Test("setSelectedFormatForCurrentPreference uses the default when no pick exists")
    @MainActor
    func cdnRevertUsesDefaultWithoutPick() {
        let (mgr, delegate) = makeManager(default: .q720)
        mgr.availableFormats = [makeFormat(height: 1080), makeFormat(height: 720), makeFormat(height: 480)]
        mgr.setSelectedFormatForCurrentPreference()
        _ = delegate
        #expect(mgr.selectedFormat?.height == 720)
    }
}
