import Foundation
import Security

public protocol TokenStore {
    func saveToken(_ token: GoogleToken) throws
    func loadToken() throws -> GoogleToken?
    func clearToken() throws
    func saveCredentials(_ creds: GoogleCredentials) throws
    func loadCredentials() throws -> GoogleCredentials?
}

public final class InMemoryTokenStore: TokenStore {
    private var token: GoogleToken?
    private var creds: GoogleCredentials?
    public init() {}
    public func saveToken(_ token: GoogleToken) throws { self.token = token }
    public func loadToken() throws -> GoogleToken? { token }
    public func clearToken() throws { token = nil }
    public func saveCredentials(_ creds: GoogleCredentials) throws { self.creds = creds }
    public func loadCredentials() throws -> GoogleCredentials? { creds }
}

/// Real store: one generic-password Keychain item per key, holding JSON.
/// Build-verified + exercised by live use (the `ClaudeRunner` pattern); not unit-tested.
public final class KeychainTokenStore: TokenStore {
    private let service: String
    private let tokenKey = "google.token"
    private let credsKey = "google.credentials"

    public init(service: String = "com.mustard.google-calendar") { self.service = service }

    public func saveToken(_ token: GoogleToken) throws { try set(tokenKey, try JSONEncoder().encode(token)) }
    public func loadToken() throws -> GoogleToken? {
        guard let data = try get(tokenKey) else { return nil }
        return try JSONDecoder().decode(GoogleToken.self, from: data)
    }
    public func clearToken() throws { try delete(tokenKey) }
    public func saveCredentials(_ creds: GoogleCredentials) throws { try set(credsKey, try JSONEncoder().encode(creds)) }
    public func loadCredentials() throws -> GoogleCredentials? {
        guard let data = try get(credsKey) else { return nil }
        return try JSONDecoder().decode(GoogleCredentials.self, from: data)
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
    private func set(_ key: String, _ data: Data) throws {
        SecItemDelete(query(key) as CFDictionary)
        var add = query(key); add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw GoogleAuthError.server("keychain write \(status)") }
    }
    private func get(_ key: String) throws -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GoogleAuthError.server("keychain read \(status)") }
        return out as? Data
    }
    private func delete(_ key: String) throws { SecItemDelete(query(key) as CFDictionary) }
}
