//
//  CommandKeySettingRow.swift
//  Moonlight Vision
//
//  Settings row: what the Command key of a hardware keyboard sends to the PC.
//  Owns its storage so SettingsView and TemporarySettings need no new state.
//  Lives in AppIntents/ only because that folder is compiled into the
//  "Moonlight XrOS" target without needing an entry in project.pbxproj.
//

import SwiftUI

/// UserDefaults.standard key "keyboard.commandKeyMode" (Int, default 0).
/// 0 = Windows key, 1 = Ctrl, 2 = Ctrl and the Control key sends the Windows key.
/// Read by +[KeyboardSupport sendKeyEvent:down:] on every key event (visionOS only).
struct CommandKeySettingRow: View {
    @AppStorage("keyboard.commandKeyMode") private var mode: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Command Key on Hardware Keyboard")
                    .foregroundColor(.white)
                Spacer()
                Picker("", selection: $mode) {
                    Text("Windows key").tag(0)
                    Text("Ctrl").tag(1)
                    Text("Ctrl (Control = Windows key)").tag(2)
                }
                .pickerStyle(.menu)
            }
            Text("What Command sends to the PC. Ctrl makes Command-C / Command-V copy and paste. The third option also turns the Control key into the Windows key, so Windows shortcuts stay reachable. Shortcuts that visionOS keeps for itself are never sent.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
        .onChange(of: mode) { _, _ in
            // Key codes for held modifiers just changed: make sure nothing stays held on the host.
            KeyboardSupport.releaseAllKeys()
        }
    }
}
