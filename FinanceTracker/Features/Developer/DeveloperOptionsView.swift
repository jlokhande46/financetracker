import SwiftUI

/// Developer Options — review and edit every piece of "remembered" state the
/// app has accumulated. Power-user only. Lives in Settings → Privacy & Security.
struct DeveloperOptionsView: View {

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var rules: [MerchantRuleStore.RuleSnapshot] = []
    @State private var editingRule: MerchantRuleStore.RuleSnapshot? = nil
    @State private var ruleToDelete: MerchantRuleStore.RuleSnapshot? = nil
    @State private var showDeleteAllRulesAlert = false
    @State private var searchText = ""
    @State private var toastMessage: String = ""
    @State private var showToast: Bool = false

    private var filteredRules: [MerchantRuleStore.RuleSnapshot] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return rules }
        return rules.filter {
            $0.merchantKey.lowercased().contains(q) ||
            $0.merchantDisplay.lowercased().contains(q) ||
            $0.categorySlug.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.xl) {
                        merchantRulesSection
                        diagnosticsSection
                        dangerSection
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.vertical, Spacing.base)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("Developer Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .searchable(text: $searchText, prompt: "Search rules")
            .onAppear { load() }
            .sheet(item: $editingRule) { rule in
                EditMerchantRuleSheet(rule: rule) { newSlug, newName in
                    MerchantRuleStore.shared.updateRule(
                        id: rule.id,
                        categorySlug: newSlug,
                        displayName: newName
                    )
                    load()
                    toast("Rule updated")
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .alert("Delete all rules?", isPresented: $showDeleteAllRulesAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete \(rules.count) rule\(rules.count == 1 ? "" : "s")", role: .destructive) {
                    MerchantRuleStore.shared.deleteAll()
                    load()
                    toast("All merchant rules deleted")
                }
            } message: {
                Text("Future transactions will lose their learned categorisations. This won't affect existing transactions, just future imports.")
            }
            .confirmationDialog(
                "Delete this rule?",
                isPresented: Binding(
                    get: { ruleToDelete != nil },
                    set: { if !$0 { ruleToDelete = nil } }
                ),
                presenting: ruleToDelete
            ) { rule in
                Button("Delete", role: .destructive) {
                    MerchantRuleStore.shared.deleteRule(id: rule.id)
                    load()
                    toast("Rule deleted")
                }
                Button("Cancel", role: .cancel) {}
            } message: { rule in
                Text("Future transactions matching '\(rule.merchantDisplay)' will no longer auto-categorise.")
            }
        }
        .toast(isPresented: $showToast, message: toastMessage, type: .success)
    }

    // MARK: - Merchant rules section

    private var merchantRulesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MERCHANT RULES")
                        .font(.micro)
                        .foregroundStyle(Color.textSecondary)
                        .kerning(1.2)
                    Text("\(rules.count) learned rule\(rules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                if !rules.isEmpty {
                    Button("Delete all", role: .destructive) {
                        showDeleteAllRulesAlert = true
                    }
                    .font(.caption)
                    .foregroundStyle(Color.expenseRed)
                }
            }

            if rules.isEmpty {
                Text("No rules learned yet. Tap 'Remember' in Review to start.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(Spacing.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredRules) { rule in
                        ruleRow(rule)
                        if rule.id != filteredRules.last?.id {
                            Divider().background(Color.textTertiary.opacity(0.15))
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                if filteredRules.isEmpty && !rules.isEmpty {
                    Text("No rules match '\(searchText)'")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, Spacing.sm)
                }
            }
        }
    }

    private func ruleRow(_ rule: MerchantRuleStore.RuleSnapshot) -> some View {
        let cat = CategoryEntity.find(slug: rule.categorySlug)
        return Button {
            editingRule = rule
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(cat.color.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: cat.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(cat.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.merchantDisplay)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(cat.name)
                            .font(.micro)
                            .foregroundStyle(cat.color)
                        Text("·")
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                        Text("key: \(rule.merchantKey)")
                            .font(.micro)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(rule.matchCount)")
                        .font(.amount(13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("matches")
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                }
                Button {
                    ruleToDelete = rule
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.expenseRed.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("DIAGNOSTICS")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
                .kerning(1.2)

            VStack(spacing: 0) {
                statRow(label: "Transactions",   value: "\(transactionCount)", icon: "list.bullet")
                Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                statRow(label: "Accounts",       value: "\(accountCount)",      icon: "creditcard")
                Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                statRow(label: "Budgets",        value: "\(budgetCount)",       icon: "chart.bar")
                Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                statRow(label: "Goals",          value: "\(goalCount)",         icon: "target")
                Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                statRow(label: "Card statements", value: "\(cardStatementCount)", icon: "doc.text")
                Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                statRow(label: "Pending SMS queue", value: "\(pendingSMSCount)", icon: "tray")
                Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                statRow(label: "Dismissed insights", value: "\(dismissedInsightsCount)", icon: "eye.slash")
            }
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func statRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24)
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(value)
                .font(.amount(13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
        }
        .padding(Spacing.base)
    }

    // MARK: - Danger zone

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("RESET")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
                .kerning(1.2)

            VStack(spacing: 0) {
                if pendingSMSCount > 0 {
                    actionRow(
                        icon: "tray.and.arrow.down",
                        color: Color.warningAmber,
                        label: "Flush pending SMS queue",
                        sub: "\(pendingSMSCount) queued — drains without saving"
                    ) {
                        _ = PendingSMSStore.drainQueue()
                        load()
                        toast("Pending SMS queue cleared")
                    }
                    Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                }
                if dismissedInsightsCount > 0 {
                    actionRow(
                        icon: "eye",
                        color: Color.brandPrimary,
                        label: "Restore dismissed insights",
                        sub: "\(dismissedInsightsCount) hidden — bring them back"
                    ) {
                        UserDefaults.standard.removeObject(forKey: "dismissedInsightIDs")
                        load()
                        toast("Dismissed insights restored")
                    }
                    Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                }
                actionRow(
                    icon: "creditcard.fill",
                    color: Color.brandPrimary,
                    label: "Restore default cards",
                    sub: "Re-create HDFC, ICICI, SBI, Federal accounts if missing"
                ) {
                    guard let container else { return }
                    let before = container.accountRepo.fetchAll().count
                    container.accountRepo.syncUserCards()
                    let after = container.accountRepo.fetchAll().count
                    let added = after - before
                    toast(added > 0
                          ? "Restored \(added) account\(added == 1 ? "" : "s")"
                          : "All default accounts already present")
                }
                Divider().background(Color.textTertiary.opacity(0.15)).padding(.leading, 56)
                actionRow(
                    icon: "link.badge.plus",
                    color: Color.brandAccent,
                    label: "Re-link orphan transactions",
                    sub: "Match unlinked rows to accounts by SMS / PDF content"
                ) {
                    guard let container else { return }
                    let count = container.transactionRepo.relinkOrphanTransactions(
                        accounts: container.accountRepo.fetchAll()
                    )
                    toast(count > 0
                          ? "Linked \(count) transaction\(count == 1 ? "" : "s")"
                          : "No orphan transactions found")
                }
            }
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func actionRow(icon: String, color: Color, label: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Spacing.base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func load() {
        rules = MerchantRuleStore.shared.snapshots()
    }

    private func toast(_ msg: String) {
        toastMessage = msg
        showToast = true
    }

    private var transactionCount: Int  { container?.transactionRepo.fetchAll().count ?? 0 }
    private var accountCount: Int      { container?.accountRepo.fetchAll().count ?? 0 }
    private var budgetCount: Int       { container?.budgetRepo.fetchAll().count ?? 0 }
    private var goalCount: Int         { container?.goalRepo.fetchAll().count ?? 0 }
    private var cardStatementCount: Int { container?.cardStatementRepo.fetchAll().count ?? 0 }
    private var pendingSMSCount: Int {
        UserDefaults(suiteName: PendingSMSStore.appGroupSuite)?
            .stringArray(forKey: "pendingSMSQueue")?.count ?? 0
    }
    private var dismissedInsightsCount: Int {
        (UserDefaults.standard.array(forKey: "dismissedInsightIDs") as? [String])?.count ?? 0
    }
}

// MARK: - Edit Merchant Rule sheet

struct EditMerchantRuleSheet: View {
    let rule: MerchantRuleStore.RuleSnapshot
    var onSave: (_ categorySlug: String, _ displayName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var selectedSlug: String

    init(rule: MerchantRuleStore.RuleSnapshot, onSave: @escaping (String, String) -> Void) {
        self.rule = rule
        self.onSave = onSave
        self._displayName = State(initialValue: rule.merchantDisplay)
        self._selectedSlug = State(initialValue: rule.categorySlug)
    }

    private var allCategories: [CategoryEntity] {
        CategoryEntity.system
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {

                        // Lookup key (read-only — this is the matching key)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LOOKUP KEY")
                                .font(.micro)
                                .foregroundStyle(Color.textSecondary)
                            Text(rule.merchantKey)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .padding(Spacing.base)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            Text("Future merchants containing this string (case-insensitive) match this rule.")
                                .font(.micro)
                                .foregroundStyle(Color.textTertiary)
                        }

                        // Display name
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DISPLAY NAME")
                                .font(.micro)
                                .foregroundStyle(Color.textSecondary)
                            TextField("Display name", text: $displayName)
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                                .tint(Color.brandPrimary)
                                .padding(Spacing.base)
                                .background(Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }

                        // Category picker grid
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("CATEGORY")
                                .font(.micro)
                                .foregroundStyle(Color.textSecondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: Spacing.sm)],
                                      spacing: Spacing.sm) {
                                ForEach(allCategories) { cat in
                                    Button {
                                        selectedSlug = cat.slug
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: cat.icon)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(selectedSlug == cat.slug ? .white : cat.color)
                                            Text(cat.name)
                                                .font(.micro)
                                                .foregroundStyle(selectedSlug == cat.slug ? .white : Color.textSecondary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, Spacing.sm)
                                        .background(selectedSlug == cat.slug ? cat.color : Color.bgCard)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Stats
                        HStack(spacing: Spacing.md) {
                            stat(label: "Matches", value: "\(rule.matchCount)")
                            stat(label: "Created", value: rule.createdAt.formatted(date: .abbreviated, time: .omitted))
                            stat(label: "Updated", value: rule.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        }

                        Button {
                            let cleanName = displayName.trimmingCharacters(in: .whitespaces)
                            onSave(selectedSlug, cleanName)
                            dismiss()
                        } label: {
                            Text("Save Rule")
                                .font(.titleMedium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Color.brandPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.sm)
                    }
                    .padding(Spacing.base)
                }
            }
            .navigationTitle("Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.micro)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}
