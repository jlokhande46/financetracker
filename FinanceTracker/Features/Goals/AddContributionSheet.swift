import SwiftUI

struct AddContributionSheet: View {
    let goal: GoalEntity
    var onSave: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountString: String = ""
    @FocusState private var focused: Bool

    private var amount: Decimal { Decimal(string: amountString) ?? 0 }
    private var isValid: Bool { amount > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.xs) {
                        Text("Adding to")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: goal.type.icon)
                                .foregroundStyle(goal.type.color)
                            Text(goal.name)
                                .font(.titleMedium)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                    .padding(.top, Spacing.xl)

                    VStack(spacing: Spacing.sm) {
                        Text("AMOUNT")
                            .font(.micro)
                            .foregroundStyle(Color.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("₹")
                                .font(.amount(28, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                            TextField("0", text: $amountString)
                                .keyboardType(.decimalPad)
                                .font(.amount(44, weight: .bold))
                                .foregroundStyle(goal.type.color)
                                .multilineTextAlignment(.center)
                                .focused($focused)
                                .frame(maxWidth: 200)
                        }
                    }

                    Button {
                        guard isValid else { return }
                        onSave(amount)
                        dismiss()
                    } label: {
                        Text("Add ₹\(amountString.isEmpty ? "0" : amountString) to Goal")
                            .font(.titleMedium)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.base)
                            .background(isValid ? goal.type.color : Color.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                    .padding(.horizontal, Spacing.base)

                    Spacer()
                }
            }
            .navigationTitle("Add Contribution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onAppear { focused = true }
        }
    }
}
