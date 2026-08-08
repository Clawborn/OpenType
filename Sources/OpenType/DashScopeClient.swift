import Foundation

struct DashScopeClient {
    private let credential: DashScopeCredential
    private let session: URLSession

    init(
        credential: DashScopeCredential,
        session: URLSession = .shared
    ) {
        self.credential = credential
        self.session = session
    }

    func transcribe(
        audioURL: URL
    ) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        guard !audioData.isEmpty else { throw OpenTypeError.emptyRecording }

        let dataURI = "data:audio/wav;base64,\(audioData.base64EncodedString())"
        let body = ASRRequestBuilder.body(
            model: credential.asrModel,
            dataURI: dataURI
        )

        let data = try await post(
            path: "chat/completions",
            body: body,
            timeout: 90
        )
        let text = try ResponseParser.content(from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenTypeError.emptyRecording }
        return text
    }

    func transform(
        _ request: TransformRequest,
        model: String
    ) async throws -> String {
        let body: [String: Any]
        if request.mode == .english {
            body = [
                "model": AIServiceClient.dashScopeTranslationModel,
                "messages": [
                    ["role": "user", "content": request.transcript]
                ],
                "translation_options": [
                    "source_lang": "auto",
                    "target_lang": "English"
                ],
                "temperature": 0
            ]
        } else {
            body = [
                "model": model,
                "messages": [
                    [
                        "role": "system",
                        "content": PromptBuilder.systemPrompt(for: request)
                    ],
                    [
                        "role": "user",
                        "content": PromptBuilder.userPrompt(for: request)
                    ]
                ],
                "temperature": request.mode == .xReply
                    ? 0.45
                    : (request.mode == .clean ? 0 : 0.2)
            ]
        }

        let data = try await post(
            path: "chat/completions",
            body: body,
            timeout: 90
        )
        let text = try ResponseParser.content(from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenTypeError.invalidResponse }
        return text
    }

    private func post(
        path: String,
        body: [String: Any],
        timeout: TimeInterval
    ) async throws -> Data {
        let url = credential.compatibleBaseURL
            .appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(
            "Bearer \(credential.apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenTypeError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let serviceMessage = ResponseParser.errorMessage(from: data)
                ?? "DashScope 请求失败（HTTP \(http.statusCode)）"
            throw OpenTypeError.service(serviceMessage)
        }
        return data
    }
}

enum ASRRequestBuilder {
    static func body(
        model: String,
        dataURI: String,
        languageCode: String? = nil
    ) -> [String: Any] {
        var asrOptions: [String: Any] = ["enable_itn": true]
        if let languageCode {
            asrOptions["language"] = languageCode
        }

        return [
            "model": model,
            // DashScope's dedicated ASR task rejects text/system messages.
            // Personal vocabulary is applied during the following text
            // transformation instead of being mixed into this audio request.
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": dataURI
                            ]
                        ]
                    ]
                ]
            ],
            "stream": false,
            "asr_options": asrOptions
        ]
    }
}

enum ResponseParser {
    static func content(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw OpenTypeError.invalidResponse
        }

        if let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw OpenTypeError.service(message)
        }

        guard
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"]
        else {
            throw OpenTypeError.invalidResponse
        }

        if let text = content as? String {
            return text
        }

        if let parts = content as? [[String: Any]] {
            let strings = parts.compactMap {
                ($0["text"] as? String) ?? ($0["content"] as? String)
            }
            if !strings.isEmpty {
                return strings.joined()
            }
        }

        throw OpenTypeError.invalidResponse
    }

    static func errorMessage(from data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let message = root["message"] as? String {
            return message
        }
        return nil
    }
}
