import Foundation

struct CloudTextService {
    static let dashScopeTranslationModel = "qwen-mt-flash"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transform(
        transcript: String,
        context: String,
        mode: InputMode,
        settings: SettingsStore
    ) async throws -> String {
        let token = try await MainActor.run { try settings.currentToken() }
        guard let endpoint = await MainActor.run(body: { settings.endpoint }) else {
            throw OpenTypeMobileError.invalidConfiguration
        }
        let provider = await MainActor.run { settings.provider }
        let model = await MainActor.run { settings.model.trimmingCharacters(in: .whitespacesAndNewlines) }
        let usesDedicatedTranslation = mode == .english && provider == .dashScope
        guard usesDedicatedTranslation || !model.isEmpty else {
            throw OpenTypeMobileError.invalidConfiguration
        }

        let hasContext = !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let initialRequest = usesDedicatedTranslation
            ? try makeDashScopeTranslationRequest(
                endpoint: endpoint,
                token: token,
                transcript: transcript
            )
            : try makeRequest(
                endpoint: endpoint,
                token: token,
                model: model,
                provider: provider,
                system: PromptBuilder.systemPrompt(
                    mode: mode,
                    hasContext: hasContext
                ),
                user: PromptBuilder.userPrompt(
                    mode: mode,
                    transcript: transcript,
                    context: context
                ),
                temperature: mode == .xReply ? 0.45 : 0.2
            )
        let initial = try await send(initialRequest, provider: provider)

        if usesDedicatedTranslation {
            guard !PromptBuilder.englishOutputNeedsRepair(
                initial,
                source: transcript
            ) else {
                throw OpenTypeMobileError.outputLanguageMismatch
            }
            return initial
        }

        guard mode == .english else { return initial }
        return try await Self.resolvedEnglishOutput(
            initial: initial,
            source: transcript
        ) {
            let repairRequest = try makeRequest(
                endpoint: endpoint,
                token: token,
                model: model,
                provider: provider,
                system: PromptBuilder.englishRepairSystemPrompt(),
                user: PromptBuilder.englishRepairUserPrompt(
                    original: transcript,
                    draft: initial
                ),
                temperature: 0
            )
            return try await send(repairRequest, provider: provider)
        }
    }

    static func dashScopeTranslationBody(transcript: String) -> [String: Any] {
        [
            "model": dashScopeTranslationModel,
            "messages": [
                ["role": "user", "content": transcript]
            ],
            "translation_options": [
                "source_lang": "auto",
                "target_lang": "English"
            ],
            "temperature": 0
        ]
    }

    static func resolvedEnglishOutput(
        initial: String,
        source: String = "",
        repair: () async throws -> String
    ) async throws -> String {
        let normalized = initial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PromptBuilder.englishOutputNeedsRepair(
            normalized,
            source: source
        ) else {
            return normalized
        }

        // Exactly one corrective pass keeps latency and token use bounded.
        let repaired = try await repair()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !PromptBuilder.englishOutputNeedsRepair(
            repaired,
            source: source
        ) else {
            throw OpenTypeMobileError.outputLanguageMismatch
        }
        return repaired
    }

    private func makeRequest(
        endpoint: URL,
        token: String,
        model: String,
        provider: CloudProvider,
        system: String,
        user: String,
        temperature: Double
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .anthropic {
            request.setValue(token, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "max_tokens": 2_048,
                "system": system,
                "messages": [["role": "user", "content": user]]
            ])
        } else {
            var body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ]
            ]
            // New OpenAI and Claude models may reject explicit sampling
            // parameters. Prompt instructions carry the style instead.
            if provider != .openAI && provider != .anthropic {
                body["temperature"] = temperature
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func makeDashScopeTranslationRequest(
        endpoint: URL,
        token: String,
        transcript: String
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.dashScopeTranslationBody(
                transcript: transcript
            )
        )
        return request
    }

    private func send(_ request: URLRequest, provider: CloudProvider) async throws -> String {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenTypeMobileError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.serverMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw OpenTypeMobileError.server(message)
        }
        return provider == .anthropic
            ? try Self.anthropicResponseText(from: data)
            : try Self.responseText(from: data)
    }

    static func responseText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] else {
            throw OpenTypeMobileError.invalidResponse
        }

        let text: String
        if let value = content as? String {
            text = value
        } else if let blocks = content as? [[String: Any]] {
            text = blocks.compactMap { $0["text"] as? String }.joined()
        } else {
            throw OpenTypeMobileError.invalidResponse
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw OpenTypeMobileError.invalidResponse }
        return normalized
    }

    static func anthropicResponseText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["content"] as? [[String: Any]] else {
            throw OpenTypeMobileError.invalidResponse
        }
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenTypeMobileError.invalidResponse }
        return text
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = root["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return root["message"] as? String
    }
}
