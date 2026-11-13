//
//  StreamScreenSampling.swift
//  Moonlight Vision
//
//  Lives in AppIntents/ only because that folder is a synchronized group the "Moonlight XrOS"
//  target already compiles, so adding this file needs no project.pbxproj edit.
//

import Metal
import RealityKit
import SwiftUI

/// Optional sampling modes for the 2D stream picture. Standard is the stock material, untouched.
enum StreamScreenSampling {
    /// UserDefaults key (Int). Absent or 0 = Standard.
    static let storageKey = "stream.screenSampling"
    static let standard = 0
    /// Trilinear, 8x anisotropic, clamp to edge.
    static let sharp = 1
    /// Mip level 0 only, clamp to edge. Sharpest; may shimmer when the picture is shown small.
    static let sharper = 2

    static var mode: Int { UserDefaults.standard.integer(forKey: storageKey) }

    /// Material for the 2D stream picture. Standard: exactly UnlitMaterial(texture:), as before.
    static func screenMaterial(texture: TextureResource) -> UnlitMaterial {
        var material = UnlitMaterial(texture: texture)
        let selected = mode
        guard selected == sharp || selected == sharper else { return material }
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = selected == sharper ? .notMipmapped : .linear
        descriptor.maxAnisotropy = selected == sharper ? 1 : 8
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        material.color.texture = MaterialParameters.Texture(texture, sampler: MaterialParameters.Texture.Sampler(descriptor))
        return material
    }
}

/// Row for SettingsView's "Additional Options" section. Owns its storage.
struct ScreenSamplingSettingRow: View {
    @AppStorage(StreamScreenSampling.storageKey) private var mode: Int = StreamScreenSampling.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Screen Sharpness (experimental)")
                Spacer()
                Picker("", selection: $mode) {
                    Text("Standard").tag(StreamScreenSampling.standard)
                    Text("Sharp").tag(StreamScreenSampling.sharp)
                    Text("Sharper").tag(StreamScreenSampling.sharper)
                }
                .pickerStyle(.menu)
            }

            Text("Curved Display. Standard leaves the picture exactly as before. Sharp adds 8x anisotropic filtering, which helps most toward the angled edges of a wide curved screen. Sharper also turns off mip blending and can shimmer.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}
