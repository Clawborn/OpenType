import AVFoundation
import AppKit
import Foundation
import Speech

@MainActor
final class LiveSpeechTranscriber {
    var onTranscript: ((String) -> Void)?
    var onAudioLevel: ((Double) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var inputTapInstalled = false

    var permissionStatus: PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func requestPermission() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            return true
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func start(localeIdentifier: String = "zh-CN") throws {
        guard permissionStatus == .granted else { return }
        stop()

        guard let recognizer = SFSpeechRecognizer(
            locale: Locale(identifier: localeIdentifier)
        ), recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak self, weak request] buffer, _ in
            guard let request else { return }
            request.append(buffer)
            let level = Self.normalizedLevel(from: buffer)
            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevel?(level)
            }
        }
        inputTapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.onTranscript?(text)
                }
                if error != nil || result?.isFinal == true {
                    self.onAudioLevel?(0)
                }
            }
        }

        recognitionRequest = request
        audioEngine = engine
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if let audioEngine {
            if inputTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        inputTapInstalled = false
        onAudioLevel?(0)
    }

    func openPermissionSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private nonisolated static func normalizedLevel(
        from buffer: AVAudioPCMBuffer
    ) -> Double {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        guard rms > 0 else { return 0 }

        let decibels = 20 * log10(Double(rms))
        return min(max((decibels + 55) / 45, 0), 1)
    }
}
