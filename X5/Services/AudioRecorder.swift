import Foundation
import AVFoundation

/// Lightweight wrapper around AVAudioRecorder for press-and-hold voice messages
/// in chats. Records mono AAC at 32kbps to a temporary .m4a file.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var recordingURL: URL?

    private var recorder: AVAudioRecorder?
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }

    func start() async {
        guard !isRecording else { return }
        // Request mic permission if not yet granted.
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            session.requestRecordPermission { ok in cont.resume(returning: ok) }
        }
        guard granted else {
            permissionDenied = true
            return
        }
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString.prefix(6)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 32_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 32_000
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record()
            recorder = r
            recordingURL = url
            isRecording = true
        } catch {
            isRecording = false
        }
    }

    /// Stops recording. Returns (data, mime, ext) for upload, or nil if nothing recorded.
    @discardableResult
    func stop() -> (data: Data, mime: String, ext: String)? {
        guard let r = recorder else { return nil }
        r.stop()
        isRecording = false
        try? session.setActive(false)
        guard let url = recordingURL,
              let data = try? Data(contentsOf: url),
              !data.isEmpty
        else { return nil }
        return (data, "audio/mp4", "m4a")
    }

    func cancel() {
        recorder?.stop()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        isRecording = false
        try? session.setActive(false)
    }
}
