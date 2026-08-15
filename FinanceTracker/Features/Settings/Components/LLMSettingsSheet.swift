import SwiftUI

/// Configures the LLM parser beta — provider picker, API key entry,
/// model selector, and privacy warning. Reachable from Settings →
/// "AI Parsing (Beta)".
struct LLMSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LLMSettings.enabledKey) private var enabled: Bool = false
    @AppStorage(LLMSettings.providerKey) private var providerRaw: String = LLMSettings.Provider.nemotron.rawValue
    @AppStorage(LLMSettings.modelKey) private var model: String = ""

    @State private var apiKeyDraft: String = ""
    @State private var hasStoredKey: Bool = false
    @State private var showKey: Bool = false
    @State private var testResult: String? = nil
    @State private var isTesting: Bool = false

    private var provider: LLMSettings.Provider {
        LLMSettings.Provider(rawValue: providerRaw) ?? .nemotron
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        betaBadge
                        privacyCallout
                        enableToggle
                        if enabled {
                            providerPicker
                            apiKeySection
                            modelSection
                            if let result = testResult { testResultView(result) }
                            testButton
                        }
                        howItWorksCallout
                    }
                    .padding(Spacing.base)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .navigationTitle("AI Parsing (Beta)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .onAppear { refreshStoredKeyStatus() }
            .onChange(of: providerRaw) { _, _ in
                // Provider switched — snap model to new provider's default
                // if the stored model isn't in the new provider's menu.
                let currentProvider = provider
                if !currentProvider.availableModels.contains(where: { $0.id == model }) {
                    model = currentProvider.defaultModel
                }
                apiKeyDraft = ""
                testResult = nil
                refreshStoredKeyStatus()
            }
        }
    }

    // MARK: - Sections

    private var betaBadge: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color.brandAccent)
            Text("BETA")
                .font(.micro)
                .fontWeight(.bold)
                .foregroundStyle(Color.brandAccent)
                .kerning(1.4)
            Spacer()
            Text("Fallback when built-in parser can't read a bank format")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(Spacing.md)
        .background(Color.brandAccent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.brandAccent.opacity(0.3), lineWidth: 1)
        )
    }

    private var privacyCallout: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.warningAmber)
                Text("Privacy note")
                    .font(.titleMedium)
                    .foregroundStyle(Color.textPrimary)
            }
            Text("With this on, every unrecognised SMS or PDF gets sent to the selected LLM provider (NVIDIA or Anthropic) over the network for parsing. Built-in parsers still run first and always stay offline. Turn this off any time to go back to fully-local parsing.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.base)
        .background(Color.warningAmber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.warningAmber.opacity(0.3), lineWidth: 1)
        )
    }

    private var enableToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable AI parsing")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(enabled ? "LLM will run when native parser fails" : "Native parser only")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $enabled)
                .labelsHidden()
                .tint(Color.brandPrimary)
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PROVIDER")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 0) {
                ForEach(LLMSettings.Provider.allCases) { p in
                    Button {
                        withAnimation(.springy) { providerRaw = p.rawValue }
                    } label: {
                        Text(p.displayName)
                            .font(.bodyMedium)
                            .foregroundStyle(providerRaw == p.rawValue ? .white : Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(providerRaw == p.rawValue ? Color.brandPrimary : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(provider.keyLabel.uppercased())
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if hasStoredKey, let preview = LLMKeychain.redactedPreview(provider: provider) {
                    Text(preview)
                        .font(.micro)
                        .foregroundStyle(Color.incomeGreen)
                        .monospaced()
                }
            }

            HStack(spacing: Spacing.sm) {
                Group {
                    if showKey {
                        TextField(provider.keyPlaceholder, text: $apiKeyDraft)
                    } else {
                        SecureField(provider.keyPlaceholder, text: $apiKeyDraft)
                    }
                }
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.brandPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button { showKey.toggle() } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            HStack(spacing: Spacing.sm) {
                Button {
                    _ = LLMKeychain.setAPIKey(apiKeyDraft, provider: provider)
                    refreshStoredKeyStatus()
                    apiKeyDraft = ""
                    showKey = false
                    testResult = hasStoredKey ? "Key saved to Keychain for \(provider.displayName)." : "Save failed."
                } label: {
                    Text("Save Key")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(apiKeyDraft.isEmpty ? Color.bgElevated : Color.brandPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(apiKeyDraft.isEmpty)

                if hasStoredKey {
                    Button(role: .destructive) {
                        _ = LLMKeychain.clear(provider: provider)
                        refreshStoredKeyStatus()
                        testResult = "\(provider.displayName) key removed from Keychain."
                    } label: {
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(Color.expenseRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.expenseRed.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(provider.keyHelpLine)
                .font(.micro)
                .foregroundStyle(Color.textTertiary)
            Text("Stored in iOS Keychain — encrypted at rest, never in iCloud backup. Each provider's key is stored separately.")
                .font(.micro)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("MODEL")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            VStack(spacing: 0) {
                let models = provider.availableModels
                ForEach(models, id: \.id) { m in
                    Button {
                        withAnimation(.springy) { model = m.id }
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: model == m.id ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(model == m.id ? Color.brandPrimary : Color.textTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.label)
                                    .font(.bodyMedium)
                                    .foregroundStyle(Color.textPrimary)
                                Text(m.subtitle)
                                    .font(.micro)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(Spacing.base)
                    }
                    .buttonStyle(.plain)
                    if m.id != models.last?.id {
                        Divider()
                            .background(Color.textTertiary.opacity(0.15))
                            .padding(.leading, 56)
                    }
                }
            }
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var testButton: some View {
        Button {
            runTestParse()
        } label: {
            HStack(spacing: Spacing.sm) {
                if isTesting {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isTesting ? "Testing…" : "Test with a sample SMS")
                    .font(.bodyMedium)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm + 2)
            .background(hasStoredKey ? Color.brandPrimary : Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(!hasStoredKey || isTesting)
    }

    private func testResultView(_ result: String) -> some View {
        Text(result)
            .font(.caption)
            .foregroundStyle(Color.textPrimary)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var howItWorksCallout: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("HOW IT WORKS")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            Text("The built-in parser always runs first — it covers the top Indian bank formats offline. When a message doesn't match any known format, the raw text is sent to the selected provider for a best-effort extraction. LLM results appear in the feed with the same review workflow.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.base)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private func refreshStoredKeyStatus() {
        hasStoredKey = LLMKeychain.apiKey(provider: provider) != nil
    }

    private func runTestParse() {
        isTesting = true
        testResult = nil
        let sampleSMS = "Your OneCard ending 4567 has been used for INR 1,234.50 at STARBUCKS INDIA on 12-Nov-26. Available limit: INR 87,650."
        Task {
            let result = await LLMParser.shared.parseSMS(sampleSMS)
            await MainActor.run {
                isTesting = false
                if let r = result {
                    testResult = "✓ Parsed via \(provider.displayName): \(r.type.rawValue.capitalized) ₹\(r.amount) at \(r.merchantRaw)"
                } else {
                    testResult = "✗ No result — check the \(provider.keyLabel), network, or model availability."
                }
            }
        }
    }
}
