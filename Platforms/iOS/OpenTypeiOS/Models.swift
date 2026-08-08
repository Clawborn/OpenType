import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }
}

enum InputMode: String, CaseIterable, Identifiable {
    case smartEdit
    case english
    case agent
    case xReply
    case transcribe

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .smartEdit: return "wand.and.stars"
        case .english: return "globe.americas.fill"
        case .agent: return "brain.head.profile"
        case .xReply: return "bubble.left.and.bubble.right.fill"
        case .transcribe: return "waveform"
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.smartEdit, .chinese): return "智能编辑"
        case (.smartEdit, .english): return "Smart Edit"
        case (.english, .chinese): return "中转英"
        case (.english, .english): return "English"
        case (.agent, .chinese): return "Agent 模式"
        case (.agent, .english): return "Agent"
        case (.xReply, _): return "X Reply"
        case (.transcribe, .chinese): return "文字转写"
        case (.transcribe, .english): return "Transcribe"
        }
    }

    func subtitle(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.smartEdit, .chinese): return "口述整理 · 按指令改写"
        case (.smartEdit, .english): return "Clean dictation · Edit by instruction"
        case (.english, .chinese): return "中文 → 地道英文"
        case (.english, .english): return "Chinese → natural English"
        case (.agent, .chinese): return "说出目标，生成成品"
        case (.agent, .english): return "Describe a goal, get a finished draft"
        case (.xReply, .chinese): return "加入对话，不写套话"
        case (.xReply, .english): return "Join the conversation naturally"
        case (.transcribe, .chinese): return "轻度整理，保留原话"
        case (.transcribe, .english): return "Light cleanup, preserve your words"
        }
    }

    var supportsContext: Bool {
        self == .smartEdit || self == .agent || self == .xReply
    }
}

enum CloudProvider: String, CaseIterable, Identifiable {
    case dashScope
    case volcengine
    case openAI
    case anthropic
    case compatible

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .dashScope:
            return language == .chinese ? "阿里云百炼" : "Alibaba Cloud Model Studio"
        case .openAI:
            return "OpenAI"
        case .volcengine:
            return language == .chinese ? "豆包 · 火山方舟" : "Doubao · Volcano Ark"
        case .anthropic:
            return "Claude"
        case .compatible:
            return language == .chinese ? "OpenAI 兼容" : "OpenAI Compatible"
        }
    }

    var defaultModel: String {
        switch self {
        case .dashScope: return "qwen-plus"
        case .volcengine: return "doubao-seed-2-0-lite-260215"
        case .openAI: return "gpt-5-mini"
        case .anthropic: return "claude-sonnet-5"
        case .compatible: return ""
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .dashScope:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .volcengine:
            return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .compatible:
            return ""
        }
    }
}

enum WorkState: Equatable {
    case idle
    case requestingPermission
    case listening
    case recognizing
    case processing
    case completed
    case cancelled(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .requestingPermission, .recognizing, .processing: return true
        default: return false
        }
    }
}

enum OpenTypeMobileError: LocalizedError {
    case permissionDenied
    case speechUnavailable
    case emptyTranscript
    case missingToken
    case invalidConfiguration
    case invalidResponse
    case outputLanguageMismatch
    case server(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone or Speech Recognition permission was denied."
        case .speechUnavailable: return "Speech Recognition is currently unavailable."
        case .emptyTranscript: return "No speech was recognized."
        case .missingToken: return "Add an API token in Settings before using AI modes."
        case .invalidConfiguration: return "The model or endpoint configuration is incomplete."
        case .invalidResponse: return "The model returned an unreadable response."
        case .outputLanguageMismatch: return "The translation model did not return a faithful English result."
        case .server(let message): return message
        }
    }
}
