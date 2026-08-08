import Foundation

struct DashScopeCredential: Equatable {
    let apiKey: String
    let dashScopeBaseURL: URL
    let compatibleBaseURL: URL
    let asrModel: String

    var safeSourceDescription: String
}

enum EnvironmentFileParser {
    static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let normalized = line.hasPrefix("export ")
                ? String(line.dropFirst("export ".count))
                : line
            guard let separator = normalized.firstIndex(of: "=") else { continue }

            let key = normalized[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var value = normalized[normalized.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            }

            guard !key.isEmpty else { continue }
            result[key] = value
        }

        return result
    }
}

struct CredentialProvider {
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func load() throws -> DashScopeCredential {
        if let key = environment["DASHSCOPE_API_KEY"], !key.isEmpty {
            return makeCredential(values: environment, key: key, source: "环境变量")
        }

        let openClawEnv = homeDirectory
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent(".env")
        if let data = try? Data(contentsOf: openClawEnv),
           let contents = String(data: data, encoding: .utf8) {
            let values = EnvironmentFileParser.parse(contents)
            if let key = values["DASHSCOPE_API_KEY"], !key.isEmpty {
                return makeCredential(
                    values: values,
                    key: key,
                    source: "~/.openclaw/.env"
                )
            }
        }

        throw OpenTypeError.missingCredential
    }

    private func makeCredential(
        values: [String: String],
        key: String,
        source: String
    ) -> DashScopeCredential {
        let dashScopeString = values["DASHSCOPE_BASE_URL"]
            ?? "https://dashscope.aliyuncs.com/api/v1"
        let dashScopeBaseURL = URL(string: dashScopeString)
            ?? URL(string: "https://dashscope.aliyuncs.com/api/v1")!

        let compatibleString: String
        if dashScopeString.contains("/api/v1") {
            compatibleString = dashScopeString.replacingOccurrences(
                of: "/api/v1",
                with: "/compatible-mode/v1"
            )
        } else {
            compatibleString = dashScopeString
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                + "/compatible-mode/v1"
        }

        return DashScopeCredential(
            apiKey: key,
            dashScopeBaseURL: dashScopeBaseURL,
            compatibleBaseURL: URL(string: compatibleString)
                ?? URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            asrModel: values["DASHSCOPE_ASR_MODEL"] ?? "qwen3-asr-flash",
            safeSourceDescription: source
        )
    }
}
