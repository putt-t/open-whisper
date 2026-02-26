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

    func start() {
        Permissions.requestMicrophonePermission()
        Permissions.requestAccessibilityTrustPrompt()

        monitor.onFnPressedChanged = { [weak self] isPressed in
            Task { @MainActor in
                guard let self else { return }
                if isPressed {
                    self.handleStartRecording()
                } else {
                    self.handleStopAndTranscribe()
                }
            }
        }
        monitor.start()
    }

    private func handleStartRecording() {
        guard !isBusy else { return }
        do {
            try recorder.start()
            onStateChange?(.recording)
        } catch {
            onStateChange?(.error)
        }
    }

    private func handleStopAndTranscribe() {
        guard !isBusy else { return }
        isBusy = true
        recorder.stop { [weak self] audioURL in
            Task { @MainActor in
                guard let self else { return }
                guard let audioURL else {
                    self.isBusy = false
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
