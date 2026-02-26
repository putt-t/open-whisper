import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = OpenWhisperController()
    private let hud = OpenWhisperHUD()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Open Whisper] launched")
        setupStatusItem()
        controller.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.updateTitle(for: state)
            }
        }
        controller.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = ""
        statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Open Whisper")
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        let permissionsItem = NSMenuItem(title: "Open Permissions", action: #selector(openPermissions), keyEquivalent: "p")
        permissionsItem.target = self
        menu.addItem(permissionsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func updateTitle(for state: OpenWhisperController.State) {
        hud.update(state: state)
        statusItem.button?.image = NSImage(
            systemSymbolName: state == .idle ? "mic.fill" : "waveform",
            accessibilityDescription: "Open Whisper"
        )
    }

    @objc private func openPermissions() {
        Permissions.openSecurityPrivacySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
