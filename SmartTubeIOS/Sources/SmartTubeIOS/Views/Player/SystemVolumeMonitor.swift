#if os(iOS)
import AVFoundation
import Foundation
import Observation
import SwiftUI
import os

private let volumeLog = Logger(subsystem: "com.void.smarttube.app", category: "TOSPlayer")

// MARK: - SystemVolumeMonitor
//
// Detects hardware volume-key presses (and Control Center / AirPods / route
// volume changes) while the full-screen TOS player is on screen, so the app can
// draw its own volume indicator.
//
// Why an app-drawn indicator is needed: the full-screen TOS player embeds a
// hidden MPVolumeView (`SystemVolumeControl`) to drive volume from the
// edge-swipe gesture, and a side effect of having an MPVolumeView in the
// hierarchy is that iOS suppresses its own system volume HUD. Without this,
// pressing the hardware volume keys shows nothing at all.
//
// iOS posts no notification for volume changes. KVO on
// `AVAudioSession.sharedInstance().outputVolume` is the documented mechanism,
// but it is unreliable on recent iOS (it can stop delivering or miss steps), so
// this also polls `outputVolume` at a low rate as a fallback. Both paths feed
// the same de-duplicated `handleChange`.
@MainActor
@Observable
final class SystemVolumeMonitor {

    /// Current output volume (0...1) while the indicator should be visible;
    /// `nil` hides it.
    private(set) var level: Float?

    /// How long the indicator stays visible after the last change. Each new
    /// change cancels the pending hide, so holding a volume key keeps it up.
    @ObservationIgnored private let hideDelay: Duration

    /// Fallback polling cadence for `outputVolume`.
    @ObservationIgnored private let pollInterval: Duration

    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Last volume seen from either path, so KVO + polling don't double-fire.
    @ObservationIgnored private var lastVolume: Float?

    init(hideDelay: Duration = .seconds(1), pollInterval: Duration = .milliseconds(250)) {
        self.hideDelay = hideDelay
        self.pollInterval = pollInterval
    }

    /// Begins observing the system output volume. Idempotent.
    func start() {
        guard observation == nil, pollTask == nil else { return }
        let session = AVAudioSession.sharedInstance()
        lastVolume = session.outputVolume
        volumeLog.notice(
            "[volumeMonitor] observing outputVolume (initial=\(self.lastVolume ?? -1, format: .fixed(precision: 2)))"
        )

        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in self?.handleChange(value) }
        }

        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { return }
                self.handleChange(AVAudioSession.sharedInstance().outputVolume)
            }
        }
    }

    /// Stops observing and hides the indicator.
    func stop() {
        volumeLog.notice("[volumeMonitor] stop()")
        observation?.invalidate()
        observation = nil
        pollTask?.cancel()
        pollTask = nil
        hideTask?.cancel()
        hideTask = nil
        level = nil
        lastVolume = nil
    }

    /// De-duplicates the two change sources before showing the indicator.
    private func handleChange(_ value: Float) {
        let changed = lastVolume.map { abs($0 - value) > 0.0005 } ?? true
        lastVolume = value
        guard changed else { return }
        show(level: value)
    }

    /// Shows the indicator at `value` and schedules the auto-hide.
    func show(level value: Float) {
        volumeLog.notice("[volumeMonitor] outputVolume → \(value, format: .fixed(precision: 2))")
        level = value
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: hideDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.level = nil }
        }
    }
}
#endif
