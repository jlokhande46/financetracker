import Foundation

/// User-facing flags for the LLM beta feature. Kept separate from Keychain
/// concerns (LLMKeychain) so views can bind to @AppStorage without
/// touching the secret store on every render.
enum LLMSettings {
    /// Master switch. Off by default — beta must be explicitly enabled and
    /// the user must add an API key before any SMS/PDF gets sent to the
    /// LLM.
    static let enabledKey = "llmBetaEnabled"
    /// Which provider slug is active — currently only "anthropic" is
    /// supported, but the enum leaves room for OpenAI / Gemini later.
    static let providerKey = "llmProvider"
    /// Chosen model id. Defaults to Haiku for speed + cost; Sonnet for
    /// harder statements the user can bump up manually.
    static let modelKey = "llmModel"

    enum Provider: String { case anthropic }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var provider: Provider {
        get { Provider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "anthropic") ?? .anthropic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "claude-haiku-4-5-20251001" }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// True iff enabled AND a key is present in Keychain — callers use
    /// this before falling back to LLM parsing.
    static var isReady: Bool {
        isEnabled && (LLMKeychain.apiKey()?.isEmpty == false)
    }
}
