import Foundation

enum L10n {
    static func text(_ chinese: String, _ english: String, language: AppLanguage) -> String {
        language == .chinese ? chinese : english
    }
}
