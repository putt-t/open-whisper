import Foundation
import AppKit
import CoreGraphics

final class TextInjector {
    func insert(text: String) {
        guard !text.isEmpty else { return }
        guard AXIsProcessTrusted() else { return }
        let parsed = parseTrailingVoiceCommand(text)

        if !parsed.textToPaste.isEmpty {
            pasteText(parsed.textToPaste)
        }

        if parsed.shouldPressEnter {
            sendKeystroke(virtualKey: 36, flags: [])
        }
    }

    private func parseTrailingVoiceCommand(_ text: String) -> (textToPaste: String, shouldPressEnter: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", false) }

        let commandPattern = "(?i)\\benter[\\p{Punct}\\s]*$"
        guard let range = trimmed.range(of: commandPattern, options: .regularExpression) else {
            return (trimmed, false)
        }

        let withoutCommand = String(trimmed[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (withoutCommand, true)
    }

    private func pasteText(_ text: String) {
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
        sendKeystroke(virtualKey: 9, flags: .maskCommand)
    }

    private func sendKeystroke(virtualKey: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
