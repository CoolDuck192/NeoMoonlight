//
//  OpenStreamAppIntent.swift
//  Moonlight
//
//  Created by tht7 on 06/02/2025.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//
import AppIntents

@MainActor
struct OpenMoonlightApp: AppIntent {
    
    public static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Host")
    var host: TemporaryHost
    
    @Parameter(title: "Steamed App")
    var app: TemporaryApp
    
    @Parameter(title: "Display Mode")
    var renderer: Renderer

    static var title: LocalizedStringResource = "Start streaming app"


    @MainActor
    func perform() async throws -> some IntentResult {
        let viewModel = MainViewModel.shared

        // Never disturb a stream that is already running or starting.
        guard !viewModel.activelyStreaming,
              viewModel.streamState == .idle || viewModel.streamState == .stopping else {
            print("[Shortcut] A stream is already active. Not starting another one.")
            return .result()
        }
        if viewModel.streamState == .stopping {
            await viewModel.waitForTeardown()
        }

        // Prefer the PC object the menu uses (it has a working address); fall back to
        // the copy Shortcuts loaded from the database and give it an address.
        if viewModel.hosts.isEmpty {
            viewModel.loadSavedHosts()
        }
        let wantedUUID = host.uuid
        let liveHost = viewModel.hosts.first(where: { $0.uuid == wantedUUID }) ?? host
        if liveHost.activeAddress == nil {
            liveHost.activeAddress = liveHost.localAddress ?? liveHost.externalAddress ?? liveHost.address ?? liveHost.ipv6Address
        }
        app.setHost(liveHost)

        viewModel.streamSettings.renderer = self.renderer
        // Persist renderer selection so App Intent launches don't revert on reboot
        viewModel.streamSettings.save()

        viewModel.prepareForNewStream()
        guard let config = viewModel.stream(app: app) else {
            print("[Shortcut] Could not prepare the stream (not ready, or the PC has no known address).")
            return .result()
        }

        let activity = NSUserActivity(activityType: "dummy")
        activity.targetContentIdentifier = "dummy" // IMPORTANT
        do {
            try activity.setTypedPayload(config)
        } catch {
            print("[Shortcut] Could not hand the stream over to the app window: \(error)")
            viewModel.abortStreamStart()
            return .result()
        }
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil)
        print("perform intent")
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Stream from \(\.$host), stream app \(\.$app) with display mode \(\.$renderer)")
    }
  
    init() {
        self.renderer = MainViewModel.shared.streamSettings.renderer
    }

    init(app: TemporaryApp) {
        self.renderer = MainViewModel.shared.streamSettings.renderer
        self.app = app
    }
}