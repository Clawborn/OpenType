import Foundation

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var locale: Locale {
        Locale(identifier: self == .chinese ? "zh-Hans" : "en")
    }
}

/// Runtime localization for model values that SwiftUI receives as `String`
/// rather than `LocalizedStringKey`. Literal labels are localized by the
/// standard Localizable.strings catalog; this bridge keeps status and mode
/// names in sync with the language selected inside OpenType.
enum OpenTypeL10n {
    static var language: InterfaceLanguage = .chinese

    static func text(_ chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}
