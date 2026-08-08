import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    var permissionStatus: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        default:
            return false
        }
    }

    func start() async throws {
        guard !isRecording else { return }
        guard await requestPermission() else {
            throw OpenTypeError.microphoneDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentype-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw OpenTypeError.recordingFailed("无法启动录音")
            }
            self.recorder = recorder
            currentURL = url
        } catch let error as OpenTypeError {
            throw error
        } catch {
            throw OpenTypeError.recordingFailed(error.localizedDescription)
        }
    }

    func stop() throws -> URL {
        guard let recorder, recorder.isRecording, let url = currentURL else {
            throw OpenTypeError.emptyRecording
        }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? NSNumber
        guard duration >= 0.25, (size?.intValue ?? 0) > 1_000 else {
            try? FileManager.default.removeItem(at: url)
            throw OpenTypeError.emptyRecording
        }
        return url
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }
        currentURL = nil
    }
}
