//
//  UltrawideLayout.swift
//  Moonlight Vision
//
//  Lives in AppIntents/ only because that folder is a synchronized group the "Moonlight XrOS"
//  target already compiles, so adding this file needs no project.pbxproj edit.
//

import SwiftUI

/// Sizing rules for streams wider than 16:9 (21:9, 32:9). aspect is always height / width.
enum UltrawideLayout {
    /// UserDefaults key (Bool). Absent means on.
    static let adaptiveSizeKey = "ultrawide.adaptiveSize"
    /// height / width of the 16:9 reference picture.
    static let referenceAspect: Float = 9.0 / 16.0
    /// A stream is ultrawide when height / width is below this. 16:9 is 0.5625; the gap keeps 16:9 modes
    /// with rounded heights, and everything taller, on the old path.
    static let ultrawideAspectThreshold: Float = 0.5575
    /// Largest widening of the default curved screen. 2.0 lets a 32:9 stream reach the full 16:9 height.
    static let maxWidthFactor: Float = 2.0

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: adaptiveSizeKey) as? Bool ?? true
    }

    static func isUltrawide(aspect: Float) -> Bool {
        aspect.isFinite && aspect > 0 && aspect < ultrawideAspectThreshold
    }

    /// Multiplier for the default curved-screen scale. Exactly 1.0 for 16:9 and taller, or when the switch
    /// is off; otherwise (9/16) / aspect, capped at maxWidthFactor.
    static func widthFactor(aspect: Float, enabled: Bool) -> Float {
        guard enabled, isUltrawide(aspect: aspect) else { return 1.0 }
        return min(referenceAspect / aspect, maxWidthFactor)
    }

    /// Flat-window size in points with the same area as the 16:9 window (2000 x 1125).
    /// nil means: use the existing sizing.
    static func flatWindowSize(streamWidth: CGFloat, streamHeight: CGFloat, enabled: Bool) -> CGSize? {
        guard enabled, streamWidth > 0, streamHeight > 0,
              isUltrawide(aspect: Float(streamHeight / streamWidth)) else { return nil }
        let ratio = streamWidth / streamHeight
        let width = (2000.0 * 1125.0 * ratio).squareRoot().rounded()
        let height = (width / ratio).rounded()
        guard height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// Row for SettingsView's "Display Settings" section. Owns its storage so SettingsView and
/// TemporarySettings need no new state.
struct UltrawideSizeSettingRow: View {
    @AppStorage(UltrawideLayout.adaptiveSizeKey) private var enabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Ultrawide Screen Size", isOn: $enabled)
                .foregroundColor(.white)

            Text("Streams wider than 16:9 (21:9, 32:9) open as tall as a 16:9 screen and wider, instead of as a short strip. Applies to Curved Display and the Flat window. Turn off for the previous size. 16:9 streams are not affected.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
