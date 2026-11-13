//
//  ConnectionSettingsSection.swift
//  Moonlight Vision
//
//  Settings > Connection. Lives in the AppIntents folder because that folder is
//  added to the app target automatically.
//

import SwiftUI

struct ConnectionSettingsSection: View {
    @AppStorage("connect.keepAppRunningOnDisconnect") private var keepAppRunning = false

    var body: some View {
        SettingsSection(title: "Connection") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Keep App Running After Disconnect", isOn: $keepAppRunning)

                Text("Off: Disconnect also closes the app on your PC. On: the app keeps running on your PC, so the next connection picks up where you left off. To close it, long-pinch the app in the list and choose Quit App.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 4)
        }
    }
}
