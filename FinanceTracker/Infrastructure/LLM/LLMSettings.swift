import Foundation

/// User-facing flags for the LLM beta feature. Kept separate from Keychain
/// concerns (LLMKeychain) so views can bind to @AppStorage without
/// touching the secret store on every render.
enum LLMSettings {
    static let enabledKey  = "llmBetaEnabled"
    static let providerKey = "llmProvider"
    static let modelKey    = "llmModel"

    enum Provider: String, CaseIterable, Identifiable {
        case nemotron   // NVIDIA — integrate.api.nvidia.com (OpenAI-compatible)
        case anthropic  // Anthropic — api.anthropic.com

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .nemotron:  return "NVIDIA Nemotron"
            case .anthropic: return "Anthropic Claude"
            }
        }

        /// Human-readable name for the API key so the settings sheet
        /// prompts for the right thing.
        var keyLabel: String {
            switch self {
            case .nemotron:  return "NVIDIA API Key"
            case .anthropic: return "Anthropic API Key"
            }
        }

        /// Placeholder shown in the key entry field.
        var keyPlaceholder: String {
            switch self {
            case .nemotron:  return "nvapi-…"
            case .anthropic: return "sk-ant-…"
            }
        }

        /// Where the user can generate a key (surfaced as a subtitle).
        var keyHelpLine: String {
            switch self {
            case .nemotron:  return "Get one at build.nvidia.com → account → API keys."
            case .anthropic: return "Get one at console.anthropic.com → API Keys."
            }
        }

        /// Sensible default model for this provider.
        var defaultModel: String {
            switch self {
            case .nemotron:  return "nvidia/llama-3.3-nemotron-super-49b-v1"
            case .anthropic: return "claude-haiku-4-5-20251001"
            }
        }

        /// Menu of picker-friendly models for this provider.
        var availableModels: [(id: String, label: String, subtitle: String)] {
            switch self {
            case .nemotron:
                return [
                    ("nvidia/llama-3.3-nemotron-super-49b-v1", "Nemotron Super 49B", "Recommended — fast + strong extraction"),
                    ("nvidia/llama-3.1-nemotron-70b-instruct", "Nemotron 70B",       "Larger, slightly slower"),
                    ("meta/llama-3.3-70b-instruct",             "Llama 3.3 70B",    "Meta model on NVIDIA endpoint"),
                ]
            case .anthropic:
                return [
                    ("claude-haiku-4-5-20251001", "Haiku 4.5", "Fast + cheap (recommended)"),
                    ("claude-sonnet-5",           "Sonnet 5",  "Smarter for tricky formats"),
                ]
            }
        }
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Currently active provider. Defaults to Nemotron for new installs.
    static var provider: Provider {
        get {
            let raw = UserDefaults.standard.string(forKey: providerKey) ?? Provider.nemotron.rawValue
            return Provider(rawValue: raw) ?? .nemotron
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: providerKey)
            // Snap the model to the provider's default if the stored model
            // is one from the OTHER provider (avoids sending a Claude model
            // id to NVIDIA and vice versa).
            let current = model
            if !newValue.availableModels.contains(where: { $0.id == current }) {
                model = newValue.defaultModel
            }
        }
    }

    /// Model id used for the next call. Callers should NOT default this
    /// themselves — the getter falls back to the current provider's default
    /// when the stored value is empty.
    static var model: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelKey) ?? ""
            return stored.isEmpty ? provider.defaultModel : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// True iff enabled AND the current provider has a key stored.
    /// Callers use this before falling back to LLM parsing.
    static var isReady: Bool {
        isEnabled && (LLMKeychain.currentAPIKey()?.isEmpty == false)
    }
}
