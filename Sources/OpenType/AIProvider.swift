import Foundation

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case dashScope
    case volcengine
    case openAI
    case anthropic
    case elevenLabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashScope: return OpenTypeL10n.text("阿里云百炼", english: "Alibaba Cloud Model Studio")
        case .volcengine: return OpenTypeL10n.text("豆包 · 火山方舟", english: "Doubao · Volcano Ark")
        case .openAI: return "OpenAI"
        case .anthropic: return "Claude"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var shortTitle: String {
        switch self {
        case .dashScope: return OpenTypeL10n.text("阿里", english: "Alibaba")
        case .volcengine: return OpenTypeL10n.text("豆包", english: "Doubao")
        case .openAI: return "OpenAI"
        case .anthropic: return "Claude"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var symbol: String {
        switch self {
        case .dashScope: return "cloud.fill"
        case .volcengine: return "flame.fill"
        case .openAI: return "sparkles"
        case .anthropic: return "brain.head.profile"
        case .elevenLabs: return "waveform"
        }
    }

    var supportsSpeechRecognition: Bool {
        switch self {
        case .dashScope, .openAI, .elevenLabs: return true
        case .volcengine, .anthropic: return false
        }
    }

    var supportsTextGeneration: Bool {
        switch self {
        case .dashScope, .volcengine, .openAI, .anthropic: return true
        case .elevenLabs: return false
        }
    }

    var defaultSpeechModel: String? {
        switch self {
        case .dashScope: return "qwen3-asr-flash"
        case .openAI: return "gpt-4o-mini-transcribe"
        case .elevenLabs: return "scribe_v2"
        default: return nil
        }
    }

    var defaultTextModel: String? {
        switch self {
        case .dashScope: return "qwen-plus"
        case .volcengine: return "doubao-seed-2-0-lite-260215"
        case .openAI: return "gpt-5-mini"
        case .anthropic: return "claude-sonnet-5"
        case .elevenLabs: return nil
        }
    }

    var tokenHint: String {
        switch self {
        case .dashScope: return "DashScope API Key"
        case .volcengine: return "ARK API Key"
        case .openAI: return "OpenAI API Key"
        case .anthropic: return "Anthropic API Key"
        case .elevenLabs: return "ElevenLabs API Key"
        }
    }

    static var speechProviders: [AIProvider] {
        allCases.filter(\.supportsSpeechRecognition)
    }

    static var textProviders: [AIProvider] {
        allCases.filter(\.supportsTextGeneration)
    }
}

enum TranscriptionLanguage: String, CaseIterable, Codable, Identifiable {
    case automatic
    case chinese
    case cantonese
    case english
    case japanese
    case korean
    case german
    case french
    case spanish
    case italian
    case portuguese
    case russian
    case arabic
    case hindi
    case indonesian
    case thai
    case turkish
    case vietnamese
    case ukrainian
    case czech
    case danish
    case filipino
    case finnish
    case icelandic
    case malay
    case norwegian
    case polish
    case swedish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return OpenTypeL10n.text("自动识别（支持混合语言）", english: "Auto-detect (mixed languages)")
        case .chinese: return OpenTypeL10n.text("中文", english: "Chinese")
        case .cantonese: return OpenTypeL10n.text("粤语", english: "Cantonese")
        case .english: return OpenTypeL10n.text("英语", english: "English")
        case .japanese: return OpenTypeL10n.text("日语", english: "Japanese")
        case .korean: return OpenTypeL10n.text("韩语", english: "Korean")
        case .german: return OpenTypeL10n.text("德语", english: "German")
        case .french: return OpenTypeL10n.text("法语", english: "French")
        case .spanish: return OpenTypeL10n.text("西班牙语", english: "Spanish")
        case .italian: return OpenTypeL10n.text("意大利语", english: "Italian")
        case .portuguese: return OpenTypeL10n.text("葡萄牙语", english: "Portuguese")
        case .russian: return OpenTypeL10n.text("俄语", english: "Russian")
        case .arabic: return OpenTypeL10n.text("阿拉伯语", english: "Arabic")
        case .hindi: return OpenTypeL10n.text("印地语", english: "Hindi")
        case .indonesian: return OpenTypeL10n.text("印尼语", english: "Indonesian")
        case .thai: return OpenTypeL10n.text("泰语", english: "Thai")
        case .turkish: return OpenTypeL10n.text("土耳其语", english: "Turkish")
        case .vietnamese: return OpenTypeL10n.text("越南语", english: "Vietnamese")
        case .ukrainian: return OpenTypeL10n.text("乌克兰语", english: "Ukrainian")
        case .czech: return OpenTypeL10n.text("捷克语", english: "Czech")
        case .danish: return OpenTypeL10n.text("丹麦语", english: "Danish")
        case .filipino: return OpenTypeL10n.text("菲律宾语", english: "Filipino")
        case .finnish: return OpenTypeL10n.text("芬兰语", english: "Finnish")
        case .icelandic: return OpenTypeL10n.text("冰岛语", english: "Icelandic")
        case .malay: return OpenTypeL10n.text("马来语", english: "Malay")
        case .norwegian: return OpenTypeL10n.text("挪威语", english: "Norwegian")
        case .polish: return OpenTypeL10n.text("波兰语", english: "Polish")
        case .swedish: return OpenTypeL10n.text("瑞典语", english: "Swedish")
        }
    }

    func code(for provider: AIProvider) -> String? {
        switch self {
        case .automatic:
            return nil
        case .cantonese:
            return provider == .openAI ? "zh" : "yue"
        case .filipino:
            return provider == .openAI ? "tl" : "fil"
        case .chinese: return "zh"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .german: return "de"
        case .french: return "fr"
        case .spanish: return "es"
        case .italian: return "it"
        case .portuguese: return "pt"
        case .russian: return "ru"
        case .arabic: return "ar"
        case .hindi: return "hi"
        case .indonesian: return "id"
        case .thai: return "th"
        case .turkish: return "tr"
        case .vietnamese: return "vi"
        case .ukrainian: return "uk"
        case .czech: return "cs"
        case .danish: return "da"
        case .finnish: return "fi"
        case .icelandic: return "is"
        case .malay: return "ms"
        case .norwegian: return "no"
        case .polish: return "pl"
        case .swedish: return "sv"
        }
    }

    var appleLocaleIdentifier: String {
        switch self {
        case .automatic, .chinese: return "zh-CN"
        case .cantonese: return "yue-Hant-HK"
        case .english: return "en-US"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .german: return "de-DE"
        case .french: return "fr-FR"
        case .spanish: return "es-ES"
        case .italian: return "it-IT"
        case .portuguese: return "pt-PT"
        case .russian: return "ru-RU"
        case .arabic: return "ar-SA"
        case .hindi: return "hi-IN"
        case .indonesian: return "id-ID"
        case .thai: return "th-TH"
        case .turkish: return "tr-TR"
        case .vietnamese: return "vi-VN"
        case .ukrainian: return "uk-UA"
        case .czech: return "cs-CZ"
        case .danish: return "da-DK"
        case .filipino: return "fil-PH"
        case .finnish: return "fi-FI"
        case .icelandic: return "is-IS"
        case .malay: return "ms-MY"
        case .norwegian: return "nb-NO"
        case .polish: return "pl-PL"
        case .swedish: return "sv-SE"
        }
    }
}

struct AIServiceSelection {
    let speechProvider: AIProvider
    let speechModel: String
    let transcriptionLanguage: TranscriptionLanguage
    let textProvider: AIProvider
    let textModel: String
}
