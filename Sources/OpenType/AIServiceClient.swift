import Foundation

struct TextTransformResult {
    let text: String
    let model: String
}

struct AIServiceClient {
    static let dashScopeTranslationModel = "qwen-mt-flash"
    static let dashScopeTranslationFallbackModel = "qwen-mt-plus"

    private let selection: AIServiceSelection
    private let vault: ProviderVault
    private let session: URLSession

    init(
        selection: AIServiceSelection,
        vault: ProviderVault,
        session: URLSession = .shared
    ) {
        self.selection = selection
        self.vault = vault
        self.session = session
    }

    var isFullyConfigured: Bool {
        vault.hasToken(for: selection.speechProvider)
            && vault.hasToken(for: selection.textProvider)
    }

    var safeStatusDescription: String {
        let speech = vault.hasToken(for: selection.speechProvider)
            ? selection.speechProvider.shortTitle
            : OpenTypeL10n.text("\(selection.speechProvider.shortTitle) 未配置", english: "\(selection.speechProvider.shortTitle) not configured")
        let text = vault.hasToken(for: selection.textProvider)
            ? selection.textProvider.shortTitle
            : OpenTypeL10n.text("\(selection.textProvider.shortTitle) 未配置", english: "\(selection.textProvider.shortTitle) not configured")
        return OpenTypeL10n.text("语音：\(speech) · 文字：\(text)", english: "Speech: \(speech) · Text: \(text)")
    }

    func transcribe(
        audioURL: URL,
        personalVocabulary: [String]
    ) async throws -> String {
        let token = try vault.token(for: selection.speechProvider)
        switch selection.speechProvider {
        case .dashScope:
            return try await transcribeWithDashScope(
                audioURL: audioURL,
                token: token
            )
        case .openAI:
            return try await transcribeWithOpenAI(
                audioURL: audioURL,
                token: token,
                personalVocabulary: personalVocabulary
            )
        case .elevenLabs:
            return try await transcribeWithElevenLabs(
                audioURL: audioURL,
                token: token
            )
        case .volcengine, .anthropic:
            throw OpenTypeError.service(
                "\(selection.speechProvider.title) 当前不支持语音识别"
            )
        }
    }

    func transform(_ request: TransformRequest) async throws -> String {
        try await transformResult(request).text
    }

    func transformResult(
        _ request: TransformRequest
    ) async throws -> TextTransformResult {
        let token = try vault.token(for: selection.textProvider)

        if request.mode == .english,
           selection.textProvider == .dashScope {
            var model = Self.dashScopeTranslationModel
            var translated = try await translateWithDashScope(
                request,
                token: token,
                model: model
            )
            if NonAgenticOutputPolicy.needsCorrection(
                mode: request.mode,
                source: request.transcript,
                output: translated
            ) {
                model = Self.dashScopeTranslationFallbackModel
                translated = try await translateWithDashScope(
                    request,
                    token: token,
                    model: model
                )
            }
            guard !NonAgenticOutputPolicy.needsCorrection(
                mode: request.mode,
                source: request.transcript,
                output: translated
            ) else {
                throw OpenTypeError.service(
                    OpenTypeL10n.text(
                        "中转英未能忠实转换原话，请再试一次",
                        english: "English Mode did not faithfully transform the source. Please try again."
                    )
                )
            }
            return TextTransformResult(text: translated, model: model)
        }

        let candidate = try await transformOnce(
            request,
            token: token,
            rejectedCandidate: nil
        )
        guard NonAgenticOutputPolicy.needsCorrection(
            mode: request.mode,
            source: request.transcript,
            output: candidate
        ) else {
            return TextTransformResult(
                text: candidate,
                model: selection.textModel
            )
        }

        // Non-agentic modes get exactly one corrective pass when a provider
        // answers the speaker, carries out a dictated request, or violates the
        // English-only contract. Never recurse or spend unbounded calls.
        let corrected = try await transformOnce(
            request,
            token: token,
            rejectedCandidate: candidate
        )
        guard !NonAgenticOutputPolicy.needsCorrection(
            mode: request.mode,
            source: request.transcript,
            output: corrected
        ) else {
            let chineseMessage = request.mode == .clean
                ? "智能编辑未能忠实整理原话，请再试一次"
                : "中转英未能忠实转换原话，请再试一次"
            let englishMessage = request.mode == .clean
                ? "Smart Edit did not faithfully preserve the dictation. Please try again."
                : "English Mode did not faithfully transform the source. Please try again."
            throw OpenTypeError.service(
                OpenTypeL10n.text(
                    chineseMessage,
                    english: englishMessage
                )
            )
        }
        return TextTransformResult(
            text: corrected,
            model: selection.textModel
        )
    }

    func effectiveTextModel(for mode: InputMode) -> String {
        if mode == .english,
           selection.textProvider == .dashScope {
            return Self.dashScopeTranslationModel
        }
        return selection.textModel
    }

    private func transformOnce(
        _ request: TransformRequest,
        token: String,
        rejectedCandidate: String?
    ) async throws -> String {

        switch selection.textProvider {
        case .dashScope, .volcengine, .openAI:
            return try await transformOpenAICompatible(
                request,
                provider: selection.textProvider,
                token: token,
                rejectedCandidate: rejectedCandidate
            )
        case .anthropic:
            return try await transformWithAnthropic(
                request,
                token: token,
                rejectedCandidate: rejectedCandidate
            )
        case .elevenLabs:
            throw OpenTypeError.service("ElevenLabs 当前不支持文字生成")
        }
    }

    private func translateWithDashScope(
        _ request: TransformRequest,
        token: String,
        model: String
    ) async throws -> String {
        var translationOptions: [String: Any] = [
            "source_lang": "auto",
            "target_lang": "English"
        ]
        let terms = Self.translationTerms(
            from: request.personalDictionary,
            source: request.transcript
        )
        if !terms.isEmpty {
            translationOptions["terms"] = terms
        }

        let body: [String: Any] = [
            "model": model,
            // Qwen-MT is a single-purpose translation model. The transcript is
            // inert source data, not a chat instruction, and system messages
            // are intentionally omitted from this request.
            "messages": [
                ["role": "user", "content": request.transcript]
            ],
            "translation_options": translationOptions,
            "temperature": 0
        ]
        let data = try await postJSON(
            url: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
            headers: ["Authorization": "Bearer \(token)"],
            body: body,
            timeout: 90
        )
        let text = try ResponseParser.content(from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenTypeError.invalidResponse }
        return text
    }

    private static func translationTerms(
        from personalDictionary: [String],
        source: String
    ) -> [[String: String]] {
        let normalizedSource = source.lowercased()
        return personalDictionary
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 80 }
            // Qwen-MT can be distracted by unrelated terminology. Only send
            // entries that actually occur in this utterance.
            .filter { normalizedSource.contains($0.lowercased()) }
            // Preserve product names such as OpenType and OpenClaw. Chinese
            // entries are not pinned to themselves because the target must
            // remain English-only.
            .filter { term in
                !term.unicodeScalars.contains { scalar in
                    (0x3400...0x4DBF).contains(scalar.value)
                        || (0x4E00...0x9FFF).contains(scalar.value)
                        || (0xF900...0xFAFF).contains(scalar.value)
                }
            }
            .prefix(50)
            .map { ["source": $0, "target": $0] }
    }

    private func transcribeWithDashScope(
        audioURL: URL,
        token: String
    ) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        guard !audioData.isEmpty else { throw OpenTypeError.emptyRecording }
        let dataURI = "data:audio/wav;base64,\(audioData.base64EncodedString())"
        let body = ASRRequestBuilder.body(
            model: selection.speechModel,
            dataURI: dataURI,
            languageCode: selection.transcriptionLanguage.code(for: .dashScope)
        )
        let data = try await postJSON(
            url: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
            headers: ["Authorization": "Bearer \(token)"],
            body: body,
            timeout: 90
        )
        let text = try ResponseParser.content(from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenTypeError.emptyRecording }
        return text
    }

    private func transcribeWithOpenAI(
        audioURL: URL,
        token: String,
        personalVocabulary: [String]
    ) async throws -> String {
        var multipart = MultipartFormDataBuilder()
        multipart.addField(name: "model", value: selection.speechModel)
        if let languageCode = selection.transcriptionLanguage.code(for: .openAI) {
            multipart.addField(name: "language", value: languageCode)
        }
        if !personalVocabulary.isEmpty {
            multipart.addField(
                name: "prompt",
                value: "Vocabulary: \(personalVocabulary.joined(separator: ", "))"
            )
        }
        try multipart.addFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: "audio/wav",
            fileURL: audioURL
        )
        let data = try await postMultipart(
            url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            headers: ["Authorization": "Bearer \(token)"],
            multipart: multipart,
            timeout: 90
        )
        return try transcriptionText(from: data)
    }

    private func transcribeWithElevenLabs(
        audioURL: URL,
        token: String
    ) async throws -> String {
        var multipart = MultipartFormDataBuilder()
        multipart.addField(name: "model_id", value: selection.speechModel)
        if let languageCode = selection.transcriptionLanguage.code(for: .elevenLabs) {
            multipart.addField(name: "language_code", value: languageCode)
        }
        try multipart.addFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: "audio/wav",
            fileURL: audioURL
        )
        let data = try await postMultipart(
            url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
            headers: ["xi-api-key": token],
            multipart: multipart,
            timeout: 90
        )
        return try transcriptionText(from: data)
    }

    private func transformOpenAICompatible(
        _ request: TransformRequest,
        provider: AIProvider,
        token: String,
        rejectedCandidate: String?
    ) async throws -> String {
        let url: URL
        switch provider {
        case .dashScope:
            url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        case .volcengine:
            url = URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")!
        case .openAI:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
        default:
            throw OpenTypeError.invalidResponse
        }

        var body: [String: Any] = [
            "model": selection.textModel,
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt(for: request)],
                [
                    "role": "user",
                    "content": rejectedCandidate.map {
                        PromptBuilder.correctionUserPrompt(
                            for: request,
                            rejectedCandidate: $0
                        )
                    } ?? PromptBuilder.userPrompt(for: request)
                ]
            ]
        ]
        if provider != .openAI {
            body["temperature"] = Self.temperature(for: request.mode)
        }

        let data = try await postJSON(
            url: url,
            headers: ["Authorization": "Bearer \(token)"],
            body: body,
            timeout: 90
        )
        let text = try ResponseParser.content(from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenTypeError.invalidResponse }
        return text
    }

    private func transformWithAnthropic(
        _ request: TransformRequest,
        token: String,
        rejectedCandidate: String?
    ) async throws -> String {
        let body: [String: Any] = [
            "model": selection.textModel,
            "max_tokens": 2_048,
            "system": PromptBuilder.systemPrompt(for: request),
            "messages": [
                [
                    "role": "user",
                    "content": rejectedCandidate.map {
                        PromptBuilder.correctionUserPrompt(
                            for: request,
                            rejectedCandidate: $0
                        )
                    } ?? PromptBuilder.userPrompt(for: request)
                ]
            ]
        ]
        let data = try await postJSON(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: [
                "x-api-key": token,
                "anthropic-version": "2023-06-01"
            ],
            body: body,
            timeout: 90
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["content"] as? [[String: Any]] else {
            throw OpenTypeError.invalidResponse
        }
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenTypeError.invalidResponse }
        return text
    }

    private static func temperature(for mode: InputMode) -> Double {
        switch mode {
        case .english, .clean:
            return 0
        case .xReply:
            return 0.45
        case .instruction, .command, .raw:
            return 0.2
        }
    }

    private func transcriptionText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["text"] as? String else {
            throw OpenTypeError.invalidResponse
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw OpenTypeError.emptyRecording }
        return normalized
    }

    private func postJSON(
        url: URL,
        headers: [String: String],
        body: [String: Any],
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func postMultipart(
        url: URL,
        headers: [String: String],
        multipart: MultipartFormDataBuilder,
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(
            "multipart/form-data; boundary=\(multipart.boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = multipart.finalizedData()
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenTypeError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let serviceMessage = ResponseParser.errorMessage(from: data)
                ?? anthropicErrorMessage(from: data)
                ?? "模型请求失败（HTTP \(http.statusCode)）"
            throw OpenTypeError.service(serviceMessage)
        }
        return data
    }

    private func anthropicErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}

struct MultipartFormDataBuilder {
    let boundary = "OpenType-\(UUID().uuidString)"
    private var data = Data()

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(
        name: String,
        filename: String,
        mimeType: String,
        fileURL: URL
    ) throws {
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(try Data(contentsOf: fileURL))
        append("\r\n")
    }

    func finalizedData() -> Data {
        var result = data
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}
