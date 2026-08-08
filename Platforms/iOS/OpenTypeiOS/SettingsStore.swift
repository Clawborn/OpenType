import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            SharedResultStore.save(language: language)
        }
    }
    @Published var provider: CloudProvider {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }
    @Published var compatibleBaseURL: String {
        didSet { defaults.set(compatibleBaseURL, forKey: Keys.compatibleBaseURL) }
    }
    @Published var preferOnDeviceRecognition: Bool {
        didSet { defaults.set(preferOnDeviceRecognition, forKey: Keys.preferOnDevice) }
    }
    @Published var speechLocaleIdentifier: String {
        didSet { defaults.set(speechLocaleIdentifier, forKey: Keys.speechLocale) }
    }
    @Published private(set) var tokenIsSaved = false

    private let defaults: UserDefaults
    private let keychain = KeychainStore()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .chinese
        provider = CloudProvider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .dashScope
        model = defaults.string(forKey: Keys.model) ?? CloudProvider.dashScope.defaultModel
        compatibleBaseURL = defaults.string(forKey: Keys.compatibleBaseURL) ?? ""
        preferOnDeviceRecognition = defaults.object(forKey: Keys.preferOnDevice) as? Bool ?? true
        speechLocaleIdentifier = defaults.string(forKey: Keys.speechLocale) ?? "zh-CN"
        tokenIsSaved = (try? keychain.token(for: provider))?.isEmpty == false
        SharedResultStore.save(language: language)
    }

    var endpoint: URL? {
        let raw = provider == .compatible ? compatibleBaseURL : provider.defaultBaseURL
        return URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func selectProvider(_ newProvider: CloudProvider) {
        guard provider != newProvider else { return }
        provider = newProvider
        model = newProvider.defaultModel
        refreshTokenStatus()
    }

    func currentToken() throws -> String {
        guard let token = try keychain.token(for: provider), !token.isEmpty else {
            throw OpenTypeMobileError.missingToken
        }
        return token
    }

    func saveToken(_ token: String) throws {
        try keychain.save(token, for: provider)
        refreshTokenStatus()
    }

    func deleteToken() throws {
        try keychain.delete(for: provider)
        refreshTokenStatus()
    }

    func refreshTokenStatus() {
        tokenIsSaved = (try? keychain.token(for: provider))?.isEmpty == false
    }

    private enum Keys {
        static let language = "interfaceLanguage"
        static let provider = "textProvider"
        static let model = "textModel"
        static let compatibleBaseURL = "compatibleBaseURL"
        static let preferOnDevice = "preferOnDeviceRecognition"
        static let speechLocale = "speechLocaleIdentifier"
    }
}
