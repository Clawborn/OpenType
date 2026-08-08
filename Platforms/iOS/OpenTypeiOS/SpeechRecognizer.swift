import AVFoundation
import Speech

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var level: Double = 0
    @Published private(set) var isRecording = false
    @Published private(set) var usingOnDeviceRecognition = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var receivedFinalResult = false
    private var tapIsInstalled = false

    func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    func start(localeIdentifier: String, preferOnDevice: Bool) throws {
        cancel()
        transcript = ""
        receivedFinalResult = false

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            throw OpenTypeMobileError.speechUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = preferOnDevice && recognizer.supportsOnDeviceRecognition
        usingOnDeviceRecognition = request.requiresOnDeviceRecognition
        recognitionRequest = request

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.receivedFinalResult = result.isFinal
                }
                if error != nil {
                    self.receivedFinalResult = true
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw OpenTypeMobileError.speechUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let value = Self.normalizedLevel(buffer)
            Task { @MainActor in self?.level = value }
        }
        tapIsInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopAndFinish() async -> String {
        guard isRecording else { return transcript }
        audioEngine.stop()
        if tapIsInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapIsInstalled = false
        }
        recognitionRequest?.endAudio()
        isRecording = false
        level = 0

        for _ in 0..<15 where !receivedFinalResult {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return value
    }

    func cancel() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapIsInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapIsInstalled = false
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        receivedFinalResult = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = data[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_01))
        return Double(max(0, min(1, (decibels + 55) / 55)))
    }
}
