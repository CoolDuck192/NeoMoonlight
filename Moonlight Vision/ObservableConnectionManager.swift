//
//  ObservableConnectionManager.swift
//  Moonlight
//
//  Created by tht7 on 29/12/2024.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//


import Foundation
import Combine
@MainActor
@objc class ObservableConnectionManager: NSObject, ObservableObject, ConnectionCallbacks {
    
    // Published properties for SwiftUI to observe
    @Published var connectionStatus: Int32 = 0
    @Published var currentStage: String = ""
    @Published var errorMessage: String?
    @Published var isHDRModeEnabled: Bool = false
    @Published var videoShown: Bool = false
    @Published var showAlert = false
    
    // Reference to ControllerSupport for rumble forwarding
    weak var controllerSupport: ControllerSupport?
    
    // Implement the protocol methods
    func connectionStarted() {
        print("Connection started")
    }
    
    func connectionTerminated(_ errorCode: Int32) {
        print("Connection terminated with error code: \(errorCode)")
        errorMessage = "Connection terminated with error code: \(errorCode)"
        showAlert = true

        // Post a separate notification so the ViewModel can trigger shouldCloseStream
        // for unexpected disconnects. We do NOT post RKStreamDidTeardown here because
        // that would set streamState to .idle before LiStopConnection() finishes.
        // The view's performCompleteTeardown will post RKStreamDidTeardown after
        // LiStopConnection() fully completes via stopStreamWithCompletion.
        print("[RKCallbacks] connectionTerminated - posting ConnectionLost for view cleanup")
        NotificationCenter.default.post(
            name: Notification.Name("ConnectionLost"),
            object: nil,
            userInfo: ["message": StreamEndReason.terminationMessage(errorCode: Int(errorCode)) ?? ""]
        )
    }
    
    func stageStarting(_ stageName: UnsafePointer<CChar>!) {
        if let stage = stageName {
            currentStage = String(cString: stage)
            print("Stage starting: \(currentStage)")
        }
    }
    
    func stageComplete(_ stageName: UnsafePointer<CChar>!) {
        if let stage = stageName {
            currentStage = String(cString: stage)
            print("Stage complete: \(currentStage)")
        }
    }
    
    func stageFailed(_ stageName: UnsafePointer<CChar>!, withError errorCode: Int32, portTestFlags: Int32) {
        if let stage = stageName {
            let stageStr = String(cString: stage)
            print("Stage failed: \(stageStr), Error code: \(errorCode), Port test flags: \(portTestFlags)")
            errorMessage = "Stage \(stageStr) failed with error \(errorCode)"
            showAlert = true

            print("[RKCallbacks] Posting StreamStartFailed from stageFailed")
            NotificationCenter.default.post(
                name: Notification.Name("StreamStartFailed"),
                object: nil,
                userInfo: ["message": StreamEndReason.stageFailureMessage(stage: stageStr, errorCode: Int(errorCode), portTestFlags: Int(portTestFlags))]
            )
        }
    }
    
    func launchFailed(_ message: String!) {
        print("Launch failed: \(message ?? "Unknown error")")
        errorMessage = message
        showAlert = true

        print("[RKCallbacks] Posting StreamStartFailed from launchFailed")
        NotificationCenter.default.post(
            name: Notification.Name("StreamStartFailed"),
            object: nil,
            userInfo: ["message": StreamEndReason.launchFailureMessage(message)]
        )
    }
    
    func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16) {
        controllerSupport?.rumble(controllerNumber, lowFreqMotor: lowFreqMotor, highFreqMotor: highFreqMotor)
    }
    
    func connectionStatusUpdate(_ status: Int32) {
        print("Connection status updated to: \(status)")
        connectionStatus = status
    }
    
    func setHdrMode(_ enabled: Bool) {
        print("HDR Mode set to: \(enabled)")
        isHDRModeEnabled = enabled
    }
    
    func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16) {
        controllerSupport?.rumbleTriggers(controllerNumber, leftTrigger: leftTrigger, rightTrigger: rightTrigger)
    }
    
    func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16) {
        print("Set motion event state: Controller \(controllerNumber), Motion type \(motionType), Report rate \(reportRateHz) Hz")
    }
    
    func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8) {
        print("Set LED for controller \(controllerNumber): R \(r), G \(g), B \(b)")
    }
    
    func videoContentShown() {
        print("Video content shown")
        videoShown = true
        showAlert = false

        print("[RKCallbacks] Posting RKStreamFirstFrameShown")
        NotificationCenter.default.post(name: Notification.Name("RKStreamFirstFrameShown"), object: nil)
    }
}

/// Turns raw failure details from the streaming core into a sentence a person can act on.
/// Pure text: no state, safe to call from any thread.
enum StreamEndReason {
    /// Steps where a failure means the PC could not be reached over the network.
    private static let networkStages: Set<String> = [
        "name resolution",
        "RTSP handshake",
        "control stream establishment",
        "video stream establishment",
        "audio stream establishment",
        "input stream establishment",
    ]

    /// Steps that are set up on the headset itself.
    private static let localStages: Set<String> = [
        "platform initialization",
        "audio stream initialization",
        "control stream initialization",
        "video stream initialization",
        "input stream initialization",
    ]

    static func stageFailureMessage(stage: String, errorCode: Int, portTestFlags: Int) -> String {
        if networkStages.contains(stage) {
            var text = "Could not reach your PC while starting the stream (step: \(stage), error \(errorCode)). Check that the PC is awake and on the same network as this headset."
            let ports = portList(from: portTestFlags)
            if !ports.isEmpty {
                text += " If a firewall or router sits in between, these ports must be open: \(ports)."
            }
            return text
        }
        if localStages.contains(stage) {
            return "The stream could not be set up on this headset (step: \(stage), error \(errorCode)). Try again; if it keeps happening, try a different codec or resolution in Settings."
        }
        // Unknown or unreadable step name: never show it, it may not be real text.
        return "The stream could not start (error \(errorCode)). Wait a few seconds and try again."
    }

    /// nil means the PC ended the session normally and there is nothing to report.
    static func terminationMessage(errorCode: Int) -> String? {
        switch errorCode {
        case 0:
            return nil
        case -100:
            return "No video arrived from your PC. This usually means UDP port 47998 is blocked by a firewall or router."
        case -101:
            return "The connection is too unstable to show video. Try a lower bitrate in Settings."
        case -102:
            return "Your PC ended the stream right after it started. Something on the PC is stopping it from capturing the screen (for example protected content, or a display that is off or locked)."
        case -103:
            return "Your PC stopped the stream because protected content is on screen."
        case -104:
            return "Your PC could not convert the picture for streaming. This usually happens with HDR on when the PC's display resolution does not match the stream resolution."
        default:
            return "The connection to your PC was lost (error \(errorCode))."
        }
    }

    static func launchFailureMessage(_ raw: String?) -> String {
        let detail = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "Could not start the stream. Check that your PC is on and reachable."
        }
        return "Could not start the stream: \(detail)"
    }

    private static func portList(from flags: Int) -> String {
        let table: [(Int, String)] = [
            (0x0001, "TCP 47984"),
            (0x0002, "TCP 47989"),
            (0x0004, "TCP 48010"),
            (0x0100, "UDP 47998"),
            (0x0200, "UDP 47999"),
            (0x0400, "UDP 48000"),
            (0x0800, "UDP 48010"),
        ]
        return table.filter { (flags & $0.0) != 0 }.map { $0.1 }.joined(separator: ", ")
    }
}
