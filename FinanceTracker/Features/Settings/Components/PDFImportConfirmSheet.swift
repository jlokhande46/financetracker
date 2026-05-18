import SwiftUI

/// Shown after a PDF statement is parsed, BEFORE any transactions are saved.
/// The user can review what was extracted and confirm or change which account
/// the transactions get linked to. This guarantees the account is always set
/// — auto-link is a suggestion, not an authority.
struct PDFImportConfirmSheet: View {
    let parsed: PDFParseResult
    let suggestedAccount: AccountEntity?
    let filename: String
    var onConfirm: (AccountEntity?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @State private var selectedAccountId: UUID?
    @State private var didTrySync: Bool = false

    init(parsed: PDFParseResult,
         suggestedAccount: AccountEntity?,
         filename: String,
         onConfirm: @escaping (AccountEntity?) -> Void) {
        self.parsed = parsed
        self.suggestedAccount = suggestedAccount
        self.filename = filename
        self.onConfirm = onConfirm
        self._selectedAccountId = State(initialValue: suggestedAccount?.id)
    }

    /// Pull fresh from the container every time the body builds. This guarantees
    /// the picker is never empty just because accounts hadn't seeded at the
    /// moment the sheet was constructed.
    private var availableAccounts: [AccountEntity] {
        container?.accountRepo.fetchAll() ?? []
    }

    private var selectedAccount: AccountEntity? {
        availableAccounts.first { $0.id == selectedAccountId }
    }

    private var transactionsCount: Int { parsed.transactions.count }

    private var hasStatementInfo: Bool {
        parsed.dueDate != nil && parsed.totalDue != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {

                        headerCard
                        accountPicker
                        if hasStatementInfo { statementCard }

                        // Confirm button
                        Button { confirm() } label: {
                            Text(confirmButtonLabel)
                                .font(.titleMedium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(canConfirm ? Color.brandPrimary : Color.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canConfirm)
                        .padding(.top, Spacing.sm)
                    }
                    .padding(Spacing.base)
                }
            }
            .onAppear {
                // Self-heal: if accounts are missing the first time the sheet
                // opens, run syncUserCards once. Stops the user from staring at
                // an empty picker when something has gone wrong upstream.
                if !didTrySync, availableAccounts.isEmpty {
                    didTrySync = true
                    container?.accountRepo.syncUserCards()
                    // Re-select the suggested account now that accounts exist.
                    if selectedAccountId == nil {
                        selectedAccountId = suggestedAccount?.id
                            ?? availableAccounts.first?.id
                    }
                }
            }
            .navigationTitle("Import Statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - Summary header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.brandPrimary)
                Text(filename)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            if let bank = parsed.detectedBank {
                HStack(spacing: 4) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Text("Detected: \(bank)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            HStack(spacing: Spacing.md) {
                metricChip(label: "Transactions", value: "\(transactionsCount)", icon: "list.bullet")
                metricChip(label: "Debits", value: compact(parsed.totalDebit), color: Color.expenseRed, icon: "arrow.up")
                metricChip(label: "Credits", value: compact(parsed.totalCredit), color: Color.incomeGreen, icon: "arrow.down")
            }
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func metricChip(label: String, value: String, color: Color = .textPrimary, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Text(label)
                    .font(.micro)
                    .foregroundStyle(Color.textTertiary)
            }
            Text(value)
                .font(.amount(14, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Account picker (always present)

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("LINK TO ACCOUNT")
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if let acc = selectedAccount, acc.id == suggestedAccount?.id {
                    Text("auto-detected")
                        .font(.micro)
                        .foregroundStyle(Color.incomeGreen)
                } else if selectedAccount == nil {
                    Text("required")
                        .font(.micro)
                        .foregroundStyle(Color.expenseRed)
                }
            }

            // Currently selected account (or "none yet")
            if let acc = selectedAccount {
                selectedAccountRow(acc)
            } else {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.warningAmber)
                    VStack(alignment: .leading) {
                        Text("Couldn't auto-detect")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Text("Pick the account below — transactions need it.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(Spacing.base)
                .background(Color.warningAmber.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }

            // All accounts as choices
            Text("Choose")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, Spacing.xs)

            if availableAccounts.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("No accounts on this device. Tap below to restore your default cards (HDFC, ICICI, SBI, Federal).")
                        .font(.caption)
                        .foregroundStyle(Color.warningAmber)
                    Button {
                        container?.accountRepo.syncUserCards()
                        // Force re-evaluation by refreshing selection state
                        selectedAccountId = suggestedAccount?.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Restore default cards")
                        }
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.brandPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.warningAmber.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(availableAccounts) { account in
                            Button {
                                selectedAccountId = account.id
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: account.type.icon)
                                        .font(.system(size: 11))
                                    Text(account.name)
                                        .font(.caption)
                                    if let l4 = account.last4 {
                                        Text("••\(l4)")
                                            .font(.micro)
                                            .opacity(0.7)
                                    }
                                }
                                .foregroundStyle(selectedAccountId == account.id ? .white : Color.textSecondary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(selectedAccountId == account.id
                                            ? Color(hex: account.colorHex)
                                            : Color.bgCard)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func selectedAccountRow(_ acc: AccountEntity) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color(hex: acc.colorHex).opacity(0.25))
                    .frame(width: 36, height: 36)
                Image(systemName: acc.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: acc.colorHex))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(acc.name)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                if let l4 = acc.last4 {
                    Text("•••• \(l4) · \(acc.bankName)")
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Text(acc.bankName)
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer()
        }
        .padding(Spacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Statement card

    private var statementCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("STATEMENT")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let due = parsed.dueDate, let total = parsed.totalDue {
                    HStack {
                        Text("Due")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formattedDate(due))
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                    }
                    HStack {
                        Text("Total")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(compact(total))
                            .font(.amount(15, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                if let min = parsed.minimumDue {
                    HStack {
                        Text("Min Due")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text(compact(min))
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    // MARK: - Helpers

    private var canConfirm: Bool {
        // Require an account if we have transactions to attach. If only a
        // statement was parsed (no transactions), the account is still needed
        // to link the statement reminder.
        selectedAccount != nil || (transactionsCount == 0 && !hasStatementInfo)
    }

    private var confirmButtonLabel: String {
        if transactionsCount > 0 && hasStatementInfo {
            return "Import \(transactionsCount) txns + statement"
        }
        if transactionsCount > 0 { return "Import \(transactionsCount) transactions" }
        if hasStatementInfo { return "Save statement reminder" }
        return "Nothing to import"
    }

    private func confirm() {
        guard canConfirm else { return }
        onConfirm(selectedAccount)
        dismiss()
    }

    private func formattedDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    private func compact(_ amount: Decimal?) -> String {
        guard let amount else { return "—" }
        let d = Double(truncating: amount as NSDecimalNumber)
        if d >= 1_00_00_000 { return String(format: "₹%.1fCr", d / 1_00_00_000) }
        if d >= 1_00_000    { return String(format: "₹%.1fL",  d / 1_00_000) }
        if d >= 1_000       { return String(format: "₹%.1fK",  d / 1_000) }
        return String(format: "₹%.0f", d)
    }
}
