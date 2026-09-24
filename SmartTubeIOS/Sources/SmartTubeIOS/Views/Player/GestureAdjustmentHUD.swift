import SwiftUI

// MARK: - GestureAdjustmentHUD (#19)
//
// Transient icon + fill-bar shown while the user drags to adjust brightness
// (left half) or volume (right half) — same visual language as iOS Control
// Center's own brightness/volume sliders, so it reads as a system-level
// adjustment rather than an app-specific control.
//
// Not #if os(iOS)-gated: nothing here is iOS-specific (only its call site in
// TOSPlayerView.swift is), and keeping it cross-platform lets `adjustedValue`'s
// pure math run under `swift test`, which always builds for the macOS host —
// an iOS-gated file would never be compiled or tested by that command at all.

/// Which edge strip a vertical drag began in (#148). Only the outer edges of the screen
/// adjust brightness/volume, so a stray vertical drag in the middle of the video doesn't.
enum GestureEdgeZone: Equatable {
    case left  // brightness
    case right  // volume

    /// `nil` when `startX` is in the middle region (or `viewWidth` is unusable).
    static func zone(forStartX startX: CGFloat, viewWidth: CGFloat, edgeFraction: CGFloat = 0.2) -> GestureEdgeZone? {
        guard viewWidth > 0 else { return nil }
        let edge = viewWidth * edgeFraction
        if startX <= edge { return .left }
        if startX >= viewWidth - edge { return .right }
        return nil
    }
}

struct GestureAdjustmentInfo: Equatable {
    enum Kind: Equatable {
        case brightness
        case volume
    }
    let kind: Kind
    let value: Float  // 0...1

    /// Pure function so the drag math (dragging up increases the value, clamped to
    /// 0...1, relative to wherever the value started) can be unit-tested without a
    /// live UIScreen/AVAudioSession or an actual gesture recognizer (#19).
    static func adjustedValue(start: Float, translationY: CGFloat, viewHeight: CGFloat) -> Float {
        guard viewHeight > 0 else { return start }
        let delta = Float(-translationY / viewHeight)
        return min(1, max(0, start + delta))
    }

    var systemImage: String {
        switch kind {
        case .brightness: return value < 0.3 ? "sun.min.fill" : "sun.max.fill"
        case .volume: return value == 0 ? "speaker.slash.fill" : value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
        }
    }
}

struct GestureAdjustmentHUD: View {
    let info: GestureAdjustmentInfo

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: info.systemImage)
                .font(.system(size: 22, weight: .semibold))
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.25))
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white)
                            .frame(height: geo.size.height * CGFloat(info.value))
                    }
            }
            .frame(width: 6)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(width: 56, height: 140)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier(
            info.kind == .brightness ? "tosPlayer.brightnessHUD" : "tosPlayer.volumeHUD"
        )
        .accessibilityLabel(
            "\(info.kind == .brightness ? "Brightness" : "Volume") \(Int(info.value * 100)) percent"
        )
    }
}
