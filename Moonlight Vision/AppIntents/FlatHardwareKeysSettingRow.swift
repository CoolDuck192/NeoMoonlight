//
//  FlatHardwareKeysSettingRow.swift
//  Moonlight Vision
//
//  Settings row for raw hardware-keyboard events in Flat Display.
//  Owns its storage so SettingsView and TemporarySettings need no new state.
//  Lives in AppIntents/ only because that folder is compiled into the
//  "Moonlight XrOS" target without needing an entry in project.pbxproj.
//

import SwiftUI

/// UserDefaults.standard key "keyboard.flatRawKeys" (Bool, default true).
/// Read by FlatInputCaptureUIView.forwardsHardwareKeys on every key press.
struct FlatHardwareKeysSettingRow: View {
    @AppStorage("keyboard.flatRawKeys") private var enabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Full Hardware Keyboard in Flat Display", isOn: $enabled)

            Text("Sends every key press and release to the PC, so shortcuts, arrows, Esc, function keys and held keys work as in Curved Display. Keys are sent by position: set Windows to the same keyboard layout as your keyboard. Turn off to send typed text only.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
        .onChange(of: enabled) { _, _ in
            // The meaning of key presses just changed: make sure nothing stays held on the host.
            KeyboardSupport.releaseAllKeys()
        }
    }
}
