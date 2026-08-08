import CryptoKit
import Foundation
import Security

protocol ProviderTokenStoring {
    func read(provider: AIProvider) throws -> String?
    func save(_ token: String, provider: AIProvider) throws
    func delete(provider: AIProvider) throws
}

struct KeychainProviderTokenStore: ProviderTokenStoring {
    private let service = "ai.rain.opentype.provider-token"

    func read(provider: AIProvider) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw ProviderVaultError.keychain(status)
        }
        return token
    }

    func save(_ token: String, provider: AIProvider) throws {
        let data = Data(token.utf8)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ProviderVaultError.keychain(updateStatus)
        }

        var insert = identity
        insert[kSecValueData as String] = data
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw ProviderVaultError.keychain(insertStatus)
        }
    }

    func delete(provider: AIProvider) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderVaultError.keychain(status)
        }
    }
}

struct EncryptedFileProviderTokenStore: ProviderTokenStoring {
    private struct Payload: Codable {
        var tokens: [String: Data] = [:]
    }

    let directoryURL: URL
    let vaultURL: URL
    let keyURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.directoryURL = support.appendingPathComponent(
                "OpenType",
                isDirectory: true
            )
        }
        vaultURL = self.directoryURL.appendingPathComponent(
            "provider-tokens.vault"
        )
        keyURL = self.directoryURL.appendingPathComponent(
            ".provider-vault-key"
        )
    }

    func read(provider: AIProvider) throws -> String? {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return nil
        }
        let key = try existingKey()
        let payload = try loadPayload(using: key)
        guard let combined = payload.tokens[provider.rawValue] else { return nil }
        do {
            let sealed = try AES.GCM.SealedBox(combined: combined)
            let cleartext = try AES.GCM.open(sealed, using: key)
            guard let token = String(data: cleartext, encoding: .utf8) else {
                throw ProviderVaultError.localStore("凭据内容无法读取")
            }
            return token
        } catch let error as ProviderVaultError {
            throw error
        } catch {
            throw ProviderVaultError.localStore("本地凭据解密失败")
        }
    }

    func save(_ token: String, provider: AIProvider) throws {
        let key = try loadOrCreateKey()
        var payload = try loadPayloadIfPresent(using: key)
        do {
            let sealed = try AES.GCM.seal(Data(token.utf8), using: key)
            guard let combined = sealed.combined else {
                throw ProviderVaultError.localStore("本地凭据加密失败")
            }
            payload.tokens[provider.rawValue] = combined
            try persist(payload)
        } catch let error as ProviderVaultError {
            throw error
        } catch {
            throw ProviderVaultError.localStore("本地凭据保存失败")
        }
    }

    func delete(provider: AIProvider) throws {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else { return }
        let key = try existingKey()
        var payload = try loadPayload(using: key)
        payload.tokens.removeValue(forKey: provider.rawValue)
        if payload.tokens.isEmpty {
            try? FileManager.default.removeItem(at: vaultURL)
        } else {
            try persist(payload)
        }
    }

    private func loadPayloadIfPresent(using key: SymmetricKey) throws -> Payload {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return Payload()
        }
        return try loadPayload(using: key)
    }

    private func loadPayload(using key: SymmetricKey) throws -> Payload {
        do {
            let data = try Data(contentsOf: vaultURL)
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ProviderVaultError.localStore("本地凭据库无法读取")
        }
    }

    private func existingKey() throws -> SymmetricKey {
        guard FileManager.default.fileExists(atPath: keyURL.path) else {
            throw ProviderVaultError.localStore("本地凭据密钥丢失")
        }
        do {
            let data = try Data(contentsOf: keyURL)
            guard data.count == 32 else {
                throw ProviderVaultError.localStore("本地凭据密钥已损坏")
            }
            return SymmetricKey(data: data)
        } catch let error as ProviderVaultError {
            throw error
        } catch {
            throw ProviderVaultError.localStore("本地凭据密钥无法读取")
        }
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        if FileManager.default.fileExists(atPath: keyURL.path) {
            return try existingKey()
        }
        try prepareDirectory()
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        do {
            try data.write(to: keyURL, options: .atomic)
            try securePermissions(for: keyURL)
            return key
        } catch {
            throw ProviderVaultError.localStore("无法创建本地凭据密钥")
        }
    }

    private func persist(_ payload: Payload) throws {
        try prepareDirectory()
        let data = try JSONEncoder().encode(payload)
        try data.write(to: vaultURL, options: .atomic)
        try securePermissions(for: vaultURL)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    private func securePermissions(for url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

enum ProviderVaultError: LocalizedError {
    case keychain(OSStatus)
    case localStore(String)
    case missingToken(AIProvider)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
            return "无法访问 macOS Keychain：\(detail ?? "错误 \(status)")"
        case .localStore(let detail):
            return detail
        case .missingToken(let provider):
            return "请先在设置中添加 \(provider.title) 的 API Key"
        }
    }
}

final class ProviderVault {
    private let store: ProviderTokenStoring

    init(store: ProviderTokenStoring = EncryptedFileProviderTokenStore()) {
        self.store = store
    }

    func token(for provider: AIProvider) throws -> String {
        guard let token = try store.read(provider: provider)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ProviderVaultError.missingToken(provider)
        }
        return token
    }

    func hasToken(for provider: AIProvider) -> Bool {
        guard let token = try? store.read(provider: provider) else { return false }
        return token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func save(_ token: String, for provider: AIProvider) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        try store.save(normalized, provider: provider)
    }

    func delete(for provider: AIProvider) throws {
        try store.delete(provider: provider)
    }

    func migrateDashScopeIfNeeded(_ credential: DashScopeCredential?) {
        guard !hasToken(for: .dashScope), let credential else { return }
        try? save(credential.apiKey, for: .dashScope)
    }
}
