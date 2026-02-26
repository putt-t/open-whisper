import Foundation
import AVFoundation

final class AudioRecorder: NSObject {
    private var captureSession: AVCaptureSession?
    private var output: AVCaptureAudioFileOutput?
    private var fileURL: URL?
    private var stopCompletion: ((URL?) -> Void)?
    private let stateQueue = DispatchQueue(label: "open-whisper.audio-recorder.state")

    func start() throws {
        guard output?.isRecording != true else { return }

        let session = AVCaptureSession()
        guard let device = MicrophoneManager.resolvedDevice() else {
            throw RecorderError.noInputDevice
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecorderError.cannotAddInput
        }

        let fileOutput = AVCaptureAudioFileOutput()
        guard session.canAddOutput(fileOutput) else {
            throw RecorderError.cannotAddOutput
        }

        session.addInput(input)
        session.addOutput(fileOutput)

        guard let outputType = preferredOutputType() else {
            throw RecorderError.noSupportedOutputType
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-whisper-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension(for: outputType))

        captureSession = session
        output = fileOutput
        fileURL = url
        session.startRunning()
        fileOutput.startRecording(to: url, outputFileType: outputType, recordingDelegate: self)
    }

    func stop(completion: @escaping (URL?) -> Void) {
        stateQueue.sync {
            stopCompletion = completion
        }

        guard let output else {
            finishRecording(with: nil, error: nil)
            return
        }

        guard output.isRecording else {
            finishRecording(with: fileURL, error: nil)
            return
        }

        output.stopRecording()
    }

    private func preferredOutputType() -> AVFileType? {
        let availableTypes = AVCaptureAudioFileOutput.availableOutputFileTypes()
        if availableTypes.contains(AVFileType.wav) {
            return AVFileType.wav
        }
        if availableTypes.contains(AVFileType.m4a) {
            return AVFileType.m4a
        }
        return availableTypes.first
    }

    private func fileExtension(for fileType: AVFileType) -> String {
        switch fileType {
        case .wav:
            return "wav"
        case .m4a:
            return "m4a"
        case .aiff:
            return "aiff"
        default:
            return "caf"
        }
    }

    private func finishRecording(with outputFileURL: URL?, error: Error?) {
        let completion: ((URL?) -> Void)? = stateQueue.sync {
            let callback = stopCompletion
            stopCompletion = nil
            return callback
        }

        captureSession?.stopRunning()
        captureSession = nil
        output = nil
        fileURL = nil

        completion?(error == nil ? outputFileURL : nil)
    }
}

extension AudioRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        finishRecording(with: outputFileURL, error: error)
    }
}

extension AudioRecorder {
    enum RecorderError: LocalizedError {
        case noInputDevice
        case cannotAddInput
        case cannotAddOutput
        case noSupportedOutputType

        var errorDescription: String? {
            switch self {
            case .noInputDevice:
                return "No microphone input device is available."
            case .cannotAddInput:
                return "Could not add selected microphone input."
            case .cannotAddOutput:
                return "Could not add audio capture output."
            case .noSupportedOutputType:
                return "No supported audio output type found."
            }
        }
    }
}
