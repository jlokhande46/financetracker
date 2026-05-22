import SwiftUI

/// Transaction picker shown when the user taps "Mark Paid" on a bill (or
/// on the CC Mark-Paid action — reused). Lists the best-matching candidate
/// debits from the last 14 days, plus a "None of these / paid outside the
/// app" option that marks paid without linking.
///
/// `title` and `subtitle` come from the caller so this sheet works for
/// both recurring bills and CC statements without duplication.
struct MarkBillPaidSheet: View {
    let title: String
    let subtitle: String
    let candidates: [TransactionEntity]
    let onConfirm: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransactionId: UUID? = nil
    @State private var noLinkSelected: Bool = false
    @AppStorage("hideAmounts") private var hideAmounts: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM · h:mm a"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        explainer
                        if candidates.isEmpty {
                            emptyCandidates
                        } else {
                            candidatesList
                        }
                        noLinkRow
                    }
                    .padding(Spacing.base)
                    .padding(.bottom, 100)
                }
                confirmBar
            }
            .navigationTitle(title)
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

    // MARK: - Sections

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subtitle)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var candidatesList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("CANDIDATES")
                .font(.micro)
                .foregroundStyle(Color.textSecondary)
            VStack(spacing: 0) {
                ForEach(candidates) { txn in
                    Button {
                        withAnimation(.springy) {
                            selectedTransactionId = txn.id
                            noLinkSelected = false
                        }
                    } label: {
                        candidateRow(txn)
                    }
                    .buttonStyle(.plain)
                    if txn.id != candidates.last?.id {
                        Divider()
                            .background(Color.textTertiary.opacity(0.15))
                            .padding(.leading, 56)
                    }
                }
            }
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func candidateRow(_ txn: TransactionEntity) -> some View {
        let isSelected = selectedTransactionId == txn.id
        let cat = CategoryEntity.find(slug: txn.categorySlug)
        return HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.brandPrimary : cat.color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: isSelected ? "checkmark" : cat.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : cat.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.merchantName.isEmpty ? txn.merchantRaw : txn.merchantName)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(cat.name)
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                    Text("·")
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                    Text(Self.dateFormatter.string(from: txn.date))
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Text(txn.amount.currencyString(hidden: hideAmounts))
                .font(.amount(14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .padding(Spacing.base)
        .background(isSelected ? Color.brandPrimary.opacity(0.08) : Color.clear)
    }

    private var noLinkRow: some View {
        Button {
            withAnimation(.springy) {
                noLinkSelected.toggle()
                if noLinkSelected { selectedTransactionId = nil }
            }
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(noLinkSelected ? Color.brandPrimary : Color.bgElevated)
                        .frame(width: 36, height: 36)
                    Image(systemName: noLinkSelected ? "checkmark" : "questionmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(noLinkSelected ? .white : Color.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("None of these / paid outside the app")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text("Marks the bill as paid this cycle without linking a transaction.")
                        .font(.micro)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.base)
            .background(noLinkSelected ? Color.brandPrimary.opacity(0.08) : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private var emptyCandidates: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.warningAmber)
                Text("No matching debits in the last 14 days")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
            }
            Text("Use the option below to mark this bill paid without linking a transaction.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warningAmber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.warningAmber.opacity(0.3), lineWidth: 1)
        )
    }

    private var canConfirm: Bool { selectedTransactionId != nil || noLinkSelected }

    private var confirmBar: some View {
        VStack {
            Button {
                onConfirm(selectedTransactionId)
                dismiss()
            } label: {
                Text("Confirm Paid")
                    .font(.titleMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(canConfirm ? Color.incomeGreen : Color.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.full))
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)
            .padding(.horizontal, Spacing.base)
            .padding(.bottom, Spacing.lg)
        }
        .background(
            LinearGradient(
                colors: [Color.bgPrimary.opacity(0), Color.bgPrimary],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
