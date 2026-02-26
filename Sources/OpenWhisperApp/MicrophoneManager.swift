import Foundation
import AVFoundation

enum MicrophoneManager {
    private static let selectedMicrophoneIDKey = "selected_microphone_id"

    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
            .sorted { lhs, rhs in
                lhs.localizedName.localizedCaseInsensitiveCompare(rhs.localizedName) == .orderedAscending
            }
    }

    static func defaultDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .audio) ?? availableDevices().first
    }

    static func selectedDeviceID() -> String? {
        UserDefaults.standard.string(forKey: selectedMicrophoneIDKey)
    }

    static func setSelectedDeviceID(_ deviceID: String?) {
        let trimmed = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: selectedMicrophoneIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedMicrophoneIDKey)
        }
    }

    static func resolvedDevice() -> AVCaptureDevice? {
        let devices = availableDevices()
        if let selectedID = selectedDeviceID(),
           let selected = devices.first(where: { $0.uniqueID == selectedID }) {
            return selected
        }
        return defaultDevice()
    }
}
