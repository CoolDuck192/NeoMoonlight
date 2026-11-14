//
//  QuickConnect.swift
//  Moonlight Vision
//
//  One-tap "Continue" for the last PC and app. Lives in the AppIntents folder
//  because that folder is added to the app target automatically.
//

import SwiftUI

/// What was streamed last, remembered across launches (UserDefaults only).
struct LastSession {
    static let hostUUIDKey = "connect.last.hostUUID"
    static let hostNameKey = "connect.last.hostName"
    static let appIDKey = "connect.last.appID"
    static let appNameKey = "connect.last.appName"

    static func save(hostUUID: String, hostName: String, appID: String, appName: String) {
        guard !hostUUID.isEmpty, !appID.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.set(hostUUID, forKey: hostUUIDKey)
        defaults.set(hostName, forKey: hostNameKey)
        defaults.set(appID, forKey: appIDKey)
        defaults.set(appName, forKey: appNameKey)
    }
}

/// Card at the top of the Computers list: reconnect to the last PC and app in one tap.
struct ContinueCard: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.isEmbeddedInCurved) private var isEmbeddedInCurved

    @AppStorage(LastSession.hostUUIDKey) private var lastHostUUID = ""
    @AppStorage(LastSession.appIDKey) private var lastAppID = ""
    @AppStorage(LastSession.appNameKey) private var lastAppName = ""

    @State private var isConnecting = false
    @State private var statusMessage: String?

    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)

    /// The saved PC, if it is still in the list. A PC that lost its pairing keeps the
    /// card, so that connect(to:) can say it needs to be paired again.
    private var continueHost: TemporaryHost? {
        guard !lastHostUUID.isEmpty, !lastAppID.isEmpty else { return nil }
        return viewModel.hosts.first(where: { $0.uuid == lastHostUUID })
    }

    var body: some View {
        if let host = continueHost, !viewModel.activelyStreaming, !isEmbeddedInCurved {
            card(for: host)
        }
    }

    private func card(for host: TemporaryHost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(brandOrange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle(for: host))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                if isConnecting {
                    ProgressView()
                } else {
                    Button {
                        Task { await connect(to: host) }
                    } label: {
                        Text("Connect")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(brandOrange))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }

            if let message = statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20).fill(MenuCardStyle.fill))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(brandOrange.opacity(0.5), lineWidth: 1.5))
    }

    /// The app the PC says is still running, when it is a different one from last
    /// time and it is in the PC's known app list.
    private func runningApp(on host: TemporaryHost) -> TemporaryApp? {
        guard let running = host.currentGame, !running.isEmpty, running != "0", running != lastAppID else {
            return nil
        }
        return host.appList.first(where: { $0.id == running })
    }

    private func subtitle(for host: TemporaryHost) -> String {
        if let running = runningApp(on: host) {
            return "\(running.name) on \(host.name) (still running)"
        }
        let appName = lastAppName.isEmpty ? "Last app" : lastAppName
        return "\(appName) on \(host.name)"
    }

    @MainActor
    private func connect(to host: TemporaryHost) async {
        guard !isConnecting else { return }
        isConnecting = true
        statusMessage = nil
        defer { isConnecting = false }

        // 1. Make sure the PC answers before the menu is closed.
        if host.state != .online {
            await viewModel.updateHost(host: host, force: true)
        }
        guard host.state == .online else {
            statusMessage = "\(host.name) did not answer. Check that it is on and awake, then try again."
            return
        }
        guard host.pairState == .paired else {
            statusMessage = "\(host.name) needs to be paired again. Open it from the list below."
            return
        }

        // 2. The same safety waits the app list uses before it starts a stream.
        guard !viewModel.activelyStreaming else { return }
        viewModel.stopRefresh()
        if viewModel.streamState == .stopping {
            await viewModel.waitForTeardown()
        }
        let cooldown = viewModel.reconnectCooldownRemaining()
        if cooldown > 0 {
            try? await Task.sleep(for: .milliseconds(Int((cooldown * 1000).rounded()) + 50))
        }
        await ConnectionSerializer.shared.waitUntilReadyToStart()
        if let stale = _UIKitStreamView.controllerReference.object {
            stale.stopStream()
            _UIKitStreamView.controllerReference.object = nil
        }

        // 3. Pick the app. If the PC is still running a different known app, continue
        //    that one: the PC would bring it back whatever was asked for.
        let savedName = lastAppName.isEmpty ? lastAppID : lastAppName
        let app = runningApp(on: host) ?? TemporaryApp(id: lastAppID, name: savedName)
        app.setHost(host)

        viewModel.prepareForNewStream()
        guard let config = viewModel.stream(app: app) else {
            statusMessage = "Could not start the stream. Try again in a moment."
            return
        }

        // 4. Open the stream surface the same way the app list does.
        let renderer = viewModel.streamSettings.renderer
        dismissWindow(id: "flatDisplayWindow")
        dismissWindow(id: "classicStreamingWindow")

        if renderer == .curvedDisplay {
            dismissWindow(id: "mainView")
            try? await Task.sleep(for: .milliseconds(300))
            let result = await openImmersiveSpace(id: renderer.windowId, value: config)
            if case .opened = result {
                viewModel.isImmersiveSpaceOpen = true
            } else {
                print("[Continue] Immersive space did not open: \(result)")
                viewModel.abortStreamStart()
                openWindow(id: "mainView")
            }
        } else {
            if viewModel.isImmersiveSpaceOpen {
                await dismissImmersiveSpace()
                viewModel.isImmersiveSpaceOpen = false
            }
            try? await Task.sleep(for: .milliseconds(150))
            openWindow(id: renderer.windowId, value: config)
            try? await Task.sleep(for: .milliseconds(150))
            dismissWindow(id: "mainView")
        }
    }
}
