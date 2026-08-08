import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedMode: InputMode = .smartEdit
    @Published var context = ""
    @Published var result = ""
    @Published var state: WorkState = .idle
    @Published var copiedAt: Date?

    let settings: SettingsStore
    let speech = SpeechRecognizer()
    let history = HistoryStore()

    private let cloudService = CloudTextService()
    private var workGeneration = 0

    init() {
        self.settings = SettingsStore()
    }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var canGenerate: Bool {
        let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedMode == .xReply { return !transcript.isEmpty || !reference.isEmpty }
        return !transcript.isEmpty
    }

    func toggleRecording() {
        if speech.isRecording {
            Task { await finishRecording() }
        } else {
            Task { await startRecording() }
        }
    }

    func startRecording() async {
        guard !state.isBusy else { return }
        state = .requestingPermission
        let allowed = await speech.requestPermissions()
        guard allowed else {
            state = .failed(localizedError(OpenTypeMobileError.permissionDenied))
            return
        }
        do {
            result = ""
            try speech.start(
                localeIdentifier: settings.speechLocaleIdentifier,
                preferOnDevice: settings.preferOnDeviceRecognition
            )
            state = .listening
        } catch {
            state = .failed(localizedError(error))
        }
    }

    func finishRecording() async {
        state = .recognizing
        let transcript = await speech.stopAndFinish()
        if transcript.isEmpty && !(selectedMode == .xReply && !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            state = .failed(localizedError(OpenTypeMobileError.emptyTranscript))
            return
        }
        await generate()
    }

    func generate() async {
        guard !speech.isRecording else { return }
        let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = selectedMode
        let provider = mode == .transcribe ? "system" : settings.provider.rawValue
        let modelName: String
        if mode == .transcribe {
            modelName = "platform-default"
        } else if mode == .english && settings.provider == .dashScope {
            modelName = CloudTextService.dashScopeTranslationModel
        } else {
            modelName = settings.model
        }
        let effectiveMode = mode == .smartEdit && !reference.isEmpty ? "selectedEdit" : mode.rawValue
        let requestId = UUID()
        workGeneration += 1
        let generation = workGeneration

        guard !transcript.isEmpty || (mode == .xReply && !reference.isEmpty) else {
            state = .failed(localizedError(OpenTypeMobileError.emptyTranscript))
            return
        }
        guard history.append(
            requestId: requestId,
            mode: mode,
            effectiveMode: effectiveMode,
            transcript: transcript,
            context: reference,
            result: "",
            outcome: "recognized",
            error: nil,
            provider: provider,
            model: modelName
        ) else {
            state = .failed(L10n.text(
                "无法写入本地审计记录，本次没有请求云端模型。",
                "The local audit record could not be written, so no cloud request was made.",
                language: settings.language
            ))
            return
        }
        if mode == .smartEdit,
           !reference.isEmpty,
           !PromptBuilder.hasExplicitEditIntent(transcript) {
            let message = L10n.text(
                "已提供原文时，请明确说出修改指令，例如“改得更口语一点”。",
                "When source text is present, give an explicit edit instruction, such as “make it more conversational.”",
                language: settings.language
            )
            _ = history.append(
                requestId: requestId,
                mode: mode,
                effectiveMode: effectiveMode,
                transcript: transcript,
                context: reference,
                result: "",
                outcome: "cancelled",
                error: message,
                provider: "none",
                model: ""
            )
            state = .cancelled(message)
            return
        }

        state = .processing
        do {
            let output: String
            if mode == .transcribe {
                output = Self.lightTranscription(transcript)
            } else {
                output = try await cloudService.transform(
                    transcript: transcript,
                    context: reference,
                    mode: mode,
                    settings: settings
                )
            }
            guard generation == workGeneration else {
                _ = history.append(
                    requestId: requestId,
                    mode: mode,
                    effectiveMode: effectiveMode,
                    transcript: transcript,
                    context: reference,
                    result: "",
                    outcome: "cancelled",
                    error: "A new draft replaced this request before delivery.",
                    provider: provider,
                    model: modelName
                )
                return
            }
            complete(
                output: output,
                originalTranscript: transcript,
                reference: reference,
                mode: mode,
                effectiveMode: effectiveMode,
                requestId: requestId,
                provider: provider,
                modelName: modelName
            )
        } catch {
            if generation != workGeneration {
                _ = history.append(
                    requestId: requestId,
                    mode: mode,
                    effectiveMode: effectiveMode,
                    transcript: transcript,
                    context: reference,
                    result: "",
                    outcome: "cancelled",
                    error: "A new draft replaced this request before delivery.",
                    provider: provider,
                    model: modelName
                )
                return
            }
            // The original transcript remains visible and auditable even when
            // the network or provider fails.
            let message = localizedError(error)
            _ = history.append(
                requestId: requestId,
                mode: mode,
                effectiveMode: effectiveMode,
                transcript: transcript,
                context: reference,
                result: "",
                outcome: "failed",
                error: message,
                provider: provider,
                model: modelName
            )
            state = .failed(message)
        }
    }

    func copyResult() {
        guard !result.isEmpty else { return }
        UIPasteboard.general.string = result
        SharedResultStore.save(result: result)
        copiedAt = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func startNewDraft() {
        workGeneration += 1
        if speech.isRecording { speech.cancel() }
        speech.transcript = ""
        context = ""
        result = ""
        state = .idle
    }

    private func complete(
        output: String,
        originalTranscript: String,
        reference: String,
        mode: InputMode,
        effectiveMode: String,
        requestId: UUID,
        provider: String,
        modelName: String
    ) {
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            let message = localizedError(OpenTypeMobileError.invalidResponse)
            _ = history.append(
                requestId: requestId,
                mode: mode,
                effectiveMode: effectiveMode,
                transcript: originalTranscript,
                context: reference,
                result: "",
                outcome: "failed",
                error: message,
                provider: provider,
                model: modelName
            )
            state = .failed(message)
            return
        }
        guard history.append(
            requestId: requestId,
            mode: mode,
            effectiveMode: effectiveMode,
            transcript: originalTranscript,
            context: reference,
            result: clean,
            outcome: "completed",
            error: nil,
            provider: provider,
            model: modelName
        ) else {
            result = clean
            state = .failed(L10n.text(
                "结果已生成，但无法写入本地审计记录，因此没有自动复制或同步到键盘。",
                "The result was generated, but the local audit record could not be written, so it was not copied or synced automatically.",
                language: settings.language
            ))
            return
        }
        result = clean
        UIPasteboard.general.string = clean
        SharedResultStore.save(result: clean)
        copiedAt = Date()
        state = .completed
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func localizedError(_ error: Error) -> String {
        if settings.language == .english { return error.localizedDescription }
        switch error {
        case OpenTypeMobileError.permissionDenied:
            return "需要麦克风与语音识别权限，请在系统设置中允许。"
        case OpenTypeMobileError.speechUnavailable:
            return "当前无法使用系统语音识别，请稍后再试。"
        case OpenTypeMobileError.emptyTranscript:
            return "没有识别到语音，可以再说一次或直接输入文字。"
        case OpenTypeMobileError.missingToken:
            return "请先在设置中保存云端模型 Token。"
        case OpenTypeMobileError.invalidConfiguration:
            return "模型或接口地址配置不完整。"
        case OpenTypeMobileError.invalidResponse:
            return "模型返回了无法读取的结果。"
        case OpenTypeMobileError.outputLanguageMismatch:
            return "翻译模型未返回忠实的完整英文，请再试一次。"
        default:
            return error.localizedDescription
        }
    }

    static func lightTranscription(_ input: String) -> String {
        var output = input.trimmingCharacters(in: .whitespacesAndNewlines)
        output = output.replacingOccurrences(
            of: #"^(嗯|呃|额)[，,、\s]+"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"([，,、\s])(嗯|呃|额)(?=[，,、\s])"#,
            with: "$1",
            options: .regularExpression
        )
        let terminal = CharacterSet(charactersIn: "。！？!?…")
        let questionSignals = ["为什么", "为啥", "怎么", "是否", "能不能", "可不可以", "吗", "呢"]
        if output.count <= 20,
           output.rangeOfCharacter(from: terminal, options: .backwards) == nil,
           questionSignals.contains(where: output.contains) {
            output.append("？")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
