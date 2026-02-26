import Foundation
import AVFoundation

final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() throws {
        guard recorder?.isRecording != true else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-whisper-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.prepareToRecord()
        newRecorder.record()

        recorder = newRecorder
        fileURL = url
    }

    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        self.recorder = nil
        let url = fileURL
        fileURL = nil
        return url
    }
}
