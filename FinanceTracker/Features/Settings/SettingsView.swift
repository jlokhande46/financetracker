import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.appContainer) private var container

    @AppStorage("faceIDEnabled") private var faceIDEnabled: Bool = false
    @AppStorage("userName") private var userName: String = "Jayesh Lokhande"
    @AppStorage("userEmail") private var userEmail: String = "jayesh@example.com"
    @AppStorage("themePreference") private var themePreference: String = "dark"
    @AppStorage("budgetAlertsEnabled") private var budgetAlertsEnabled: Bool = true

    @State private var showDocumentPicker: Bool = false
    @State private var showClearDataAlert: Bool = false
    @State private var isProcessingPDF: Bool = false
    @State private var toastMessage: String = ""
    @State private var showToast: Bool = false
    @State private var toastType: ToastType = .success
    @State private var pendingImport: PDFImportPayload? = nil
    @State private var showDeveloperOptions: Bool = false
    @State private var showLLMSettings: Bool = false

    /// Held in @State between parse and user confirmation. Carries the parsed
    /// result + the suggested account so the sheet can pre-fill.
    struct PDFImportPayload: Identifiable {
        let id = UUID()
        let parsed: PDFParseResult
        let suggestedAccount: AccountEntity?
        let filename: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.xl) {
                        profileSection
                        notificationsSection
                        appearanceSection
                        dataImportSection
                        privacySection
                        aboutSection
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.base)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
        }
        .toast(isPresented: $showToast, message: toastMessage, type: toastType)
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handlePDFImport(result: result)
        }
        .sheet(item: $pendingImport) { payload in
            PDFImportConfirmSheet(
                parsed: payload.parsed,
                suggestedAccount: payload.suggestedAccount,
                filename: payload.filename
            ) { chosenAccount, effectiveTxns in
                // Sheet returns the merged native + LLM transaction set;
                // swap it into the parsed struct so performImport's existing
                // save path applies uniformly.
                var effective = payload.parsed
                effective.transactions = effectiveTxns
                performImport(parsed: effective, account: chosenAccount)
                pendingImport = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDeveloperOptions) {
            DeveloperOptionsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLLMSettings) {
            LLMSettingsSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Clear All Data", isPresented: $showClearDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                container?.clearAllData()
                showSuccessToast("All data cleared")
            }
        } message: {
            Text("This will permanently delete all your transactions, accounts, budgets, and learned merchant rules. This cannot be undone.")
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(spacing: Spacing.base) {
            HStack(spacing: Spacing.base) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.brandPrimary, .brandAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)

                    Text(initials(from: userName))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(userName)
                        .font(.titleMedium)
                        .foregroundColor(.textPrimary)
                    Text(userEmail)
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Button {
                    // Edit profile action
                } label: {
                    Text("Edit")
                        .font(.caption)
                        .foregroundColor(.brandPrimary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.brandPrimary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(Spacing.base)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        SettingsSectionCard(title: "Notifications") {
            HStack {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(Color.warningAmber)
                            .frame(width: 32, height: 32)
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Budget Alerts")
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                        Text("Notify at 80% and 100% of any budget")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
                Toggle("", isOn: $budgetAlertsEnabled)
                    .tint(Color.brandPrimary)
                    .labelsHidden()
            }
            .padding(Spacing.base)
        }
    }

    // MARK: - Data Import Section

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsSectionCard(title: "Appearance") {
            HStack {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(Color.brandPrimary)
                            .frame(width: 32, height: 32)
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Theme")
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                        Text("System follows your iPhone setting")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
                Picker("Theme", selection: $themePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.menu)
                .tint(Color.brandPrimary)
            }
            .padding(Spacing.base)
        }
    }

    private var dataImportSection: some View {
        SettingsSectionCard(title: "Data Import") {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "doc.fill",
                    iconColor: .brandPrimary,
                    title: "Import Statement",
                    subtitle: "Upload a bank/credit card PDF"
                ) {
                    showDocumentPicker = true
                }
            }
        }
    }

    // MARK: - Privacy & Security Section

    private var privacySection: some View {
        SettingsSectionCard(title: "Privacy & Security") {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(Color.warningAmber)
                                .frame(width: 32, height: 32)
                            Image(systemName: "faceid")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Face ID Lock")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                            Text("Require Face ID on open")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { faceIDEnabled },
                        set: { newValue in
                            if newValue {
                                // Verify biometric works before enabling, so the user
                                // can't lock themselves out if Face ID isn't enrolled.
                                Task {
                                    let ok = await BiometricAuthService.shared.authenticate(
                                        reason: "Enable Face ID to lock the app"
                                    )
                                    await MainActor.run {
                                        faceIDEnabled = ok
                                        if ok {
                                            showSuccessToast("Face ID lock enabled")
                                        } else {
                                            showErrorToast("Couldn't verify Face ID. Lock not enabled.")
                                        }
                                    }
                                }
                            } else {
                                faceIDEnabled = false
                                showSuccessToast("Face ID lock disabled")
                            }
                        }
                    ))
                    .tint(.brandPrimary)
                    .labelsHidden()
                }
                .padding(Spacing.base)

                Divider().background(Color.bgElevated)

                SettingsRow(
                    icon: "square.and.arrow.up.fill",
                    iconColor: .brandPrimary,
                    title: "Export My Data",
                    subtitle: "Download as CSV"
                ) {
                    showSuccessToast("Export started — check Files app")
                }

                Divider().background(Color.bgElevated)

                SettingsRow(
                    icon: "sparkles",
                    iconColor: .brandAccent,
                    title: "AI Parsing (Beta)",
                    subtitle: LLMSettings.isReady ? "Enabled · fallback for unknown formats" : "Fallback when built-in parser can't read a format"
                ) {
                    showLLMSettings = true
                }

                Divider().background(Color.bgElevated)

                SettingsRow(
                    icon: "hammer.fill",
                    iconColor: .brandAccent,
                    title: "Developer Options",
                    subtitle: "Edit learned rules · diagnostics · re-link orphans"
                ) {
                    showDeveloperOptions = true
                }

                Divider().background(Color.bgElevated)

                SettingsRow(
                    icon: "trash.fill",
                    iconColor: .expenseRed,
                    title: "Clear All Data",
                    subtitle: "Permanently delete everything",
                    isDestructive: true
                ) {
                    showClearDataAlert = true
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        SettingsSectionCard(title: "About") {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(Color.bgElevated)
                                .frame(width: 32, height: 32)
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.textSecondary)
                        }
                        Text("Version")
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    Text("1.0.0")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }
                .padding(Spacing.base)

                Divider().background(Color.bgElevated)

                SettingsRow(
                    icon: "hand.raised.fill",
                    iconColor: .brandPrimary,
                    title: "Privacy Policy",
                    subtitle: nil
                ) {
                    // Open privacy policy URL
                }

                Divider().background(Color.bgElevated)

                SettingsRow(
                    icon: "star.fill",
                    iconColor: .warningAmber,
                    title: "Rate the App",
                    subtitle: "Love it? Tell the world!"
                ) {
                    // Open App Store review
                }
            }
        }
    }

    // MARK: - Helpers

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }.map { String($0) }
        return letters.joined().uppercased()
    }

    private func handlePDFImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isProcessingPDF = true

            // Parse synchronously — PDFKit is fast enough for typical statements.
            // Yield briefly so the spinner can render before the parse blocks.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                let parsed = PDFStatementParser.shared.parse(url: url)
                isProcessingPDF = false

                guard let parsed else {
                    showErrorToast("Couldn't read \(url.lastPathComponent). Is it a bank statement?")
                    return
                }
                guard let container else {
                    showErrorToast("App not ready — please try again.")
                    return
                }

                // Suggest an account using the same hierarchy as before — but DON'T
                // save yet. Let the user confirm / override in the sheet.
                let suggested = suggestAccount(for: parsed, filename: url.lastPathComponent, accounts: container.accountRepo.fetchAll())
                pendingImport = PDFImportPayload(
                    parsed: parsed,
                    suggestedAccount: suggested,
                    filename: url.lastPathComponent
                )
                return
            }
        case .failure(let error):
            showErrorToast("Import failed: \(error.localizedDescription)")
        }
    }

    /// Auto-link suggestion. Order: parsed last4 → filename hint → single CC
    /// from detected bank → single account from detected bank.
    private func suggestAccount(for parsed: PDFParseResult, filename: String, accounts: [AccountEntity]) -> AccountEntity? {
        let lower = filename.lowercased()
        let hints: [(String, String)] = [
            ("tataneu", "6624"), ("tata neu", "6624"), ("tata_neu", "6624"),
            ("regalia", "4493"),
            ("sapphiro", "2000"), ("saphirro", "2000"), ("saphiro", "2000"),
            ("cashback", "5075"), ("sbicashback", "5075"),
            ("federal", "8708"), ("fideral", "8708"),
        ]
        let filenameLast4 = hints.first(where: { lower.contains($0.0) })?.1
        let bankLower = parsed.detectedBank?.lowercased() ?? ""
        let bankMatches = bankLower.isEmpty ? [] : accounts.filter { $0.bankName.lowercased().contains(bankLower) }
        let creditBankMatches = bankMatches.filter { $0.type == .credit }

        return parsed.accountLast4.flatMap { l4 in accounts.first { $0.last4 == l4 } }
            ?? filenameLast4.flatMap { l4 in accounts.first { $0.last4 == l4 } }
            ?? (creditBankMatches.count == 1 ? creditBankMatches.first : nil)
            ?? (bankMatches.count == 1 ? bankMatches.first : nil)
    }

    /// Called from PDFImportConfirmSheet when the user taps Import. By that
    /// point an account has always been chosen (or explicitly skipped).
    private func performImport(parsed: PDFParseResult, account: AccountEntity?) {
        guard let container else {
            showErrorToast("App not ready — please try again.")
            return
        }

        // Save transactions with accountId set so they show the card chip
        if !parsed.transactions.isEmpty {
            let linked = parsed.transactions.map { txn -> TransactionEntity in
                var copy = txn
                copy.accountId = account?.id
                return copy
            }
            container.transactionRepo.saveBulk(linked)
            // Imported rows change what each card owes.
            container.refreshAccountBalances()
        }

        // Save credit-card due date if found
        var statementSaved = false
        if let dueDate = parsed.dueDate, let totalDue = parsed.totalDue, totalDue > 0 {
            if let account {
                let stmt = CardStatementEntity(
                    accountId: account.id,
                    accountName: account.name,
                    accountLast4: account.last4,
                    accountColorHex: account.colorHex,
                    statementDate: parsed.statementDate,
                    dueDate: dueDate,
                    totalDue: totalDue,
                    minimumDue: parsed.minimumDue
                )
                container.cardStatementRepo.save(stmt)
                NotificationManager.shared.scheduleReminders(for: stmt)
                statementSaved = true
            }
        }

        let bankSuffix = parsed.detectedBank.map { " from \($0)" } ?? ""
        if parsed.transactions.isEmpty && statementSaved {
            showSuccessToast("Statement saved — due date reminder set\(bankSuffix)")
        } else if parsed.transactions.isEmpty {
            showErrorToast("No transactions detected in this PDF.")
        } else if statementSaved {
            showSuccessToast("Imported \(parsed.transactions.count) transactions\(bankSuffix) · Due date saved")
        } else {
            showSuccessToast("Imported \(parsed.transactions.count) transactions\(bankSuffix)")
        }
    }

    private func relinkOrphans() {
        guard let container else { return }
        let accounts = container.accountRepo.fetchAll()
        let count = container.transactionRepo.relinkOrphanTransactions(accounts: accounts)
        if count > 0 {
            showSuccessToast("Linked \(count) transaction\(count == 1 ? "" : "s") to accounts")
        } else {
            showSuccessToast("No orphan transactions found")
        }
    }

    private func showSuccessToast(_ message: String) {
        toastMessage = message
        toastType = .success
        showToast = true
    }

    private func showErrorToast(_ message: String) {
        toastMessage = message
        toastType = .error
        showToast = true
    }
}

// MARK: - Settings Section Card

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title.uppercased())
                .font(.micro)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, Spacing.xs)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isDestructive ? Color.expenseRed.opacity(0.15) : iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isDestructive ? .expenseRed : iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodyMedium)
                        .foregroundColor(isDestructive ? .expenseRed : .textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary.opacity(0.5))
            }
            .padding(Spacing.base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
