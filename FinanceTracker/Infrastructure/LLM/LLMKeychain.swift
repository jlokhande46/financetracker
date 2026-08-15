import Foundation
import Security

/// Minimal Keychain wrapper for storing the user's LLM API key.
/// UserDefaults is inappropriate for secrets — Keychain values are
/// encrypted at rest and don't leak through iCloud backup unless the
/// user explicitly opts in (we use `kSecAttrAccessibleAfterFirstUnlock`
/// so the key survives reboots but stays on-device).
enum LLMKeychain {

    private static let service = "com.sovinnour.FinanceTracker.llm"

    /// Per-provider account name so switching Anthropic ↔ Nemotron
    /// doesn't overwrite the other provider's stored key.
    private static func account(for provider: LLMSettings.Provider) -> String {
        "\(provider.rawValue)-api-key"
    }

    /// Stores or replaces the API key for the given provider. Empty
    /// string clears it.
    @discardableResult
    static func setAPIKey(_ key: String, provider: LLMSettings.Provider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear(provider: provider) }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
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

    /// Retrieves the API key for the given provider, or nil if not set.
    static func apiKey(provider: LLMSettings.Provider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Convenience: key for the currently-selected provider.
    static func currentAPIKey() -> String? {
        apiKey(provider: LLMSettings.provider)
    }

    @discardableResult
    static func clear(provider: LLMSettings.Provider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Returns a redacted preview like "sk-ant-...abc9" (Anthropic) or
    /// "nvapi-...xyz9" (Nemotron) for display without exposing the full key.
    static func redactedPreview(provider: LLMSettings.Provider) -> String? {
        guard let key = apiKey(provider: provider), key.count > 8 else { return nil }
        return "\(key.prefix(6))…\(key.suffix(4))"
    }
}
