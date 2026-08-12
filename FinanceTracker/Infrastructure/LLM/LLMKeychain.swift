import Foundation
import Security

/// Minimal Keychain wrapper for storing the user's LLM API key.
/// UserDefaults is inappropriate for secrets — Keychain values are
/// encrypted at rest and don't leak through iCloud backup unless the
/// user explicitly opts in (we use `kSecAttrAccessibleAfterFirstUnlock`
/// so the key survives reboots but stays on-device).
enum LLMKeychain {

    private static let service = "com.sovinnour.FinanceTracker.llm"
    private static let account = "anthropic-api-key"

    /// Stores or replaces the API key. Empty string clears it.
    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear() }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // Upsert: try update first, fall back to add.
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        return false
    }

    /// Retrieves the API key, or nil if not set.
    static func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Returns a redacted preview like "sk-ant-...abc9" for display in
    /// Settings without exposing the full key.
    static func redactedPreview() -> String? {
        guard let key = apiKey(), key.count > 8 else { return nil }
        return "\(key.prefix(6))…\(key.suffix(4))"
    }
}
