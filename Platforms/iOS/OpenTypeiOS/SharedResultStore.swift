import Foundation

enum SharedResultStore {
    static let appGroupIdentifier = "group.ai.opentype.shared"
    static let latestResultKey = "latestGeneratedResult"
    static let latestResultDateKey = "latestGeneratedResultDate"
    static let languageKey = "interfaceLanguage"

    static func save(result: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(result, forKey: latestResultKey)
        defaults.set(Date().timeIntervalSince1970, forKey: latestResultDateKey)
    }

    static func save(language: AppLanguage) {
        UserDefaults(suiteName: appGroupIdentifier)?.set(language.rawValue, forKey: languageKey)
    }
}
