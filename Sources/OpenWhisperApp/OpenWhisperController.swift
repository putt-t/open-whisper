import Foundation

@MainActor
final class OpenWhisperController {
    enum State {
        case idle
        case recording
        case transcribing
        case error
    }

    var onStateChange: ((State) -> Void)?

    private let monitor = FunctionKeyMonitor()
    private let recorder = AudioRecorder()
    private let asrClient = ASRClient()
    private let textInjector = TextInjector()
    private var isBusy = false
    private var isRecording = false
    private var isLockedRecording = false
    private var ignoreNextFnRelease = false

    func start() {
        Permissions.requestMicrophonePermission()
        Permissions.requestAccessibilityTrustPrompt()

        monitor.onFnSpacePressed = { [weak self] in
            Task { @MainActor in
                self?.handleFnSpaceToggle()
            }
        }

        monitor.onFnPressedChanged = { [weak self] isPressed in
            Task { @MainActor in
                guard let self else { return }
                self.handleFnPressedChanged(isPressed)
            }
        }
        monitor.start()
    }

    private func handleFnPressedChanged(_ isPressed: Bool) {
        if isPressed {
            if isRecording, isLockedRecording {
                isLockedRecording = false
                ignoreNextFnRelease = true
                handleStopAndTranscribe()
            } else if !isRecording {
                handleStartRecording()
            }
            return
        }

        if ignoreNextFnRelease {
            ignoreNextFnRelease = false
            return
        }

        if isRecording, !isLockedRecording {
            handleStopAndTranscribe()
        }
    }

    private func handleFnSpaceToggle() {
        guard isRecording else { return }
        isLockedRecording = true
    }

    private func handleStartRecording() {
        guard !isBusy else { return }
        guard !isRecording else { return }
        do {
            try recorder.start()
            isRecording = true
            isLockedRecording = false
            onStateChange?(.recording)
        } catch {
            isRecording = false
            isLockedRecording = false
            onStateChange?(.error)
        }
    }

    private func handleStopAndTranscribe() {
        guard !isBusy else { return }
        guard isRecording else { return }
        isRecording = false
        isBusy = true
        recorder.stop { [weak self] audioURL in
            Task { @MainActor in
                guard let self else { return }
                guard let audioURL else {
                    self.isBusy = false
                    self.isLockedRecording = false
                    self.onStateChange?(.idle)
                    return
                }

                self.onStateChange?(.transcribing)
                print("[Open Whisper] transcribing audio...")

                self.asrClient.transcribe(audioFileURL: audioURL) { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        defer {
                            self.isBusy = false
                            self.isLockedRecording = false
                            self.onStateChange?(.idle)
                            try? FileManager.default.removeItem(at: audioURL)
                        }

                        switch result {
                        case .success(let text):
                            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleaned.isEmpty {
                                self.textInjector.insert(text: cleaned)
                            }
                        case .failure:
                            self.onStateChange?(.error)
                        }
                    }
                }
            }
        }
    }
}
