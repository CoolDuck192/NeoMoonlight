//
//  StreamKeyCaptureUIView.swift
//  Moonlight Vision
//
//  Hardware-keyboard handling shared by the stream input capture views:
//  InputCaptureUIView (Curved) and FlatInputCaptureUIView (Flat).
//
//  This file sits in AppIntents/ only because that folder is compiled into the
//  "Moonlight XrOS" target without needing an entry in project.pbxproj.
//

import UIKit

/// Base class of the views that hold first responder while a stream is running.
///
/// Forwards hardware key presses to the host through KeyboardSupport and makes sure that every
/// key that went down also goes up: when a press is cancelled, when the view stops being first
/// responder, and when it leaves its window. All of this runs on the main thread, in UIKit's
/// responder callbacks.
class StreamKeyCaptureUIView: UIView {

    /// A subclass returns false to leave hardware keys to UIKit's text input
    /// (UIKeyInput.insertText / deleteBackward) instead of sending raw key events.
    var forwardsHardwareKeys: Bool { true }

    /// Presses that carry no UIKey (direction presses from a remote or game controller) are sent
    /// as arrow keys when this is true. Curved has always done that; a subclass can turn it off.
    var forwardsKeylessArrowPresses: Bool { true }

    /// Sends key-down or key-up for every press KeyboardSupport can translate.
    /// Returns true when at least one press was sent.
    private func forwardKeys(_ presses: Set<UIPress>, down: Bool) -> Bool {
        var handled = false

        for press in presses {
            if press.key == nil && !forwardsKeylessArrowPresses {
                continue
            }
            if KeyboardSupport.sendKeyEvent(for: press, down: down) {
                handled = true
            }
        }

        return handled
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forwardsHardwareKeys || !forwardKeys(presses, down: true) {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forwardsHardwareKeys || !forwardKeys(presses, down: false) {
            super.pressesEnded(presses, with: event)
        }
    }

    /// A cancelled press never gets pressesEnded. Treat it as a key-up so nothing stays held on the host.
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forwardsHardwareKeys || !forwardKeys(presses, down: false) {
            super.pressesCancelled(presses, with: event)
        }
    }

    /// Once this view is no longer first responder it will not see the key-ups: release everything.
    @discardableResult
    override func resignFirstResponder() -> Bool {
        let wasFirstResponder = isFirstResponder
        let resigned = super.resignFirstResponder()
        if wasFirstResponder && resigned {
            KeyboardSupport.releaseAllKeys()
        }
        return resigned
    }

    /// The view is being removed (a panel opened, the stream is closing): release everything.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            KeyboardSupport.releaseAllKeys()
        }
    }
}
