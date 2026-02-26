import Foundation
import AppKit
import CoreGraphics

final class TextInjector {
    func insert(text: String) {
        guard !text.isEmpty else { return }
        guard AXIsProcessTrusted() else { return }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendCommandV()

        if let previousString {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                pasteboard.clearContents()
                pasteboard.setString(previousString, forType: .string)
            }
        }
    }

    private func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

