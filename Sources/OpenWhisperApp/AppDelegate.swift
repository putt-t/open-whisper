import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private let microphoneSubmenu = NSMenu(title: "Microphone")
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

        statusMenu.delegate = self

        let microphoneItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        microphoneItem.submenu = microphoneSubmenu
        statusMenu.addItem(microphoneItem)
        statusMenu.addItem(NSMenuItem.separator())

        let permissionsItem = NSMenuItem(title: "Open Permissions", action: #selector(openPermissions), keyEquivalent: "p")
        permissionsItem.target = self
        statusMenu.addItem(permissionsItem)
        statusMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
        statusItem.menu = statusMenu

        rebuildMicrophoneMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMicrophoneMenu()
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        if sender.representedObject is NSNull {
            MicrophoneManager.setSelectedDeviceID(nil)
        } else {
            MicrophoneManager.setSelectedDeviceID(sender.representedObject as? String)
        }
        rebuildMicrophoneMenu()
    }

    private func rebuildMicrophoneMenu() {
        microphoneSubmenu.removeAllItems()
        let selectedID = MicrophoneManager.selectedDeviceID()
        let defaultName = MicrophoneManager.defaultDevice()?.localizedName ?? "No default device"

        let defaultItem = NSMenuItem(
            title: "System Default (\(defaultName))",
            action: #selector(selectMicrophone(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.representedObject = NSNull()
        defaultItem.state = selectedID == nil ? .on : .off
        microphoneSubmenu.addItem(defaultItem)
        microphoneSubmenu.addItem(NSMenuItem.separator())

        let devices = MicrophoneManager.availableDevices()
        if devices.isEmpty {
            let emptyItem = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            microphoneSubmenu.addItem(emptyItem)
            return
        }

        for device in devices {
            let item = NSMenuItem(
                title: device.localizedName,
                action: #selector(selectMicrophone(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.uniqueID
            item.state = selectedID == device.uniqueID ? .on : .off
            microphoneSubmenu.addItem(item)
        }
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
