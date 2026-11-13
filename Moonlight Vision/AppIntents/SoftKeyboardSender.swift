//
//  SoftKeyboardSender.swift
//  Moonlight Vision
//
//  Sends on-screen keyboard edits to the host. Shared by the Curved and Flat stream views.
//  Lives in AppIntents/ only because that folder is compiled into the
//  "Moonlight XrOS" target without needing an entry in project.pbxproj.
//

import Foundation

enum SoftKeyboardSender {
    /// Every send goes through this serial queue, so sends keep their order and the 50 ms
    /// key hold never blocks the main thread.
    private static let sendQueue = DispatchQueue(label: "com.neomoonlight.softkeyboard")

    /// Sends the difference between the previous and the new text-field value: one Backspace
    /// for every character removed after the common prefix, then the new tail as text.
    /// Correct for appended text, deletions and in-place replacements alike.
    /// Call on the main thread; returns immediately.
    static func applyEdit(from oldValue: String, to newValue: String) {
        guard oldValue != newValue else { return }

        let oldChars = Array(oldValue)
        let newChars = Array(newValue)
        var common = 0
        while common < oldChars.count && common < newChars.count && oldChars[common] == newChars[common] {
            common += 1
        }

        let backspaceCount = oldChars.count - common
        let insertedText = String(newChars[common...])

        sendQueue.async {
            for _ in 0..<backspaceCount {
                tapKey(0x08) // VK_BACK
            }
            if !insertedText.isEmpty {
                sendText(insertedText)
            }
        }
    }

    /// Sends the Return key (VK_RETURN), behind any edits that are still queued.
    static func sendReturn() {
        sendQueue.async {
            tapKey(0x0D) // VK_RETURN
        }
    }

    private static func tapKey(_ keyCode: Int16) {
        _ = LiSendKeyboardEvent(keyCode, 0x03, 0) // KEY_ACTION_DOWN
        usleep(50 * 1000)
        _ = LiSendKeyboardEvent(keyCode, 0x04, 0) // KEY_ACTION_UP
    }

    private static func sendText(_ text: String) {
        let cString = text.cString(using: .utf8)
        cString?.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                LiSendUtf8TextEvent(base, UInt32(text.utf8.count))
            }
        }
    }
}
