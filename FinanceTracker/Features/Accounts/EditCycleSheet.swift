import SwiftUI

/// Lets the user configure when a credit card's statement is generated and when
/// the payment is due. Saving triggers a BillCycleManager sweep so reminders
/// and any newly-due statement appear immediately.
struct EditCycleSheet: View {
    let account: AccountEntity
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container

    @State private var statementDay: Int
    @State private var dueDay: Int
    @State private var hasCycle: Bool

    init(account: AccountEntity, onSaved: @escaping () -> Void) {
        self.account = account
        self.onSaved = onSaved
        _statementDay = State(initialValue: account.statementDay ?? 1)
        _dueDay      = State(initialValue: account.dueDay ?? 18)
        _hasCycle    = State(initialValue: account.statementDay != nil && account.dueDay != nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(account.name)
                                .font(.titleLarge)
                                .foregroundStyle(Color.textPrimary)
                            if let last4 = account.last4 {
                                Text("•••• \(last4)")
                                    .font(.bodyMedium)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }

                        Toggle("Track this card's billing cycle", isOn: $hasCycle)
                            .tint(Color.brandPrimary)
                            .padding(Spacing.base)
                            .background(Color.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                        if hasCycle {
                            dayPicker(title: "STATEMENT DAY",
                                      subtitle: "Day of month your bill is generated",
                                      value: $statementDay)
                            dayPicker(title: "DUE DAY",
                                      subtitle: "Day of month the payment is due",
                                      value: $dueDay)

                            // Live preview of next cycle
                            preview
                        }

                        Button(action: save) {
                            Text("Save")
                                .font(.titleMedium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.base)
                                .background(Color.brandPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.sm)
                    }
                    .padding(Spacing.base)
                }
            }
            .navigationTitle("Billing Cycle")
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

    private func dayPicker(title: String, subtitle: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.micro)
                    .foregroundStyle(Color.textSecondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            HStack {
                Text("Day \(value.wrappedValue)")
                    .font(.amount(20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                // 1...31, not 1...28. Real cards bill on the 30th (HDFC, ICICI here),
                // and the old cap silently snapped those back to 28. Months
                // shorter than the chosen day are handled downstream by the
                // cycle math, which clamps to the month's last valid day.
                Stepper("", value: value, in: 1...31)
                    .labelsHidden()
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var preview: some View {
        let cal = Calendar.current
        let now = Date()
        var stmtComps = cal.dateComponents([.year, .month], from: now)
        stmtComps.day = statementDay
        var stmtDate = cal.date(from: stmtComps) ?? now
        if stmtDate > now {
            stmtComps.month = (stmtComps.month ?? 1) - 1
            stmtDate = cal.date(from: stmtComps) ?? stmtDate
        }
        var dueComps = cal.dateComponents([.year, .month], from: stmtDate)
        dueComps.day = dueDay
        var dueDate = cal.date(from: dueComps) ?? now
        if dueDate <= stmtDate {
            dueComps.month = (dueComps.month ?? 1) + 1
            dueDate = cal.date(from: dueComps) ?? dueDate
        }

        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return VStack(alignment: .leading, spacing: 4) {
            Text("CURRENT CYCLE")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: Spacing.sm) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Color.brandPrimary)
                Text("Statement: \(f.string(from: stmtDate))")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.warningAmber)
                Text("Due: \(f.string(from: dueDate))")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private func save() {
        guard let container else { return }
        container.accountRepo.updateCycleDays(
            id: account.id,
            statementDay: hasCycle ? statementDay : nil,
            dueDay: hasCycle ? dueDay : nil
        )
        // Run sweep so new cycle creates a statement and reminders if needed.
        container.billCycleManager.runDailySweep()
        onSaved()
        dismiss()
    }
}
