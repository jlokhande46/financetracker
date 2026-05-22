import SwiftUI

/// Embedded in BudgetsView between the budgets list and the goals list.
/// Owns its own sheets (add/edit + mark-paid) so the parent doesn't need
/// to thread state.
struct RecurringBillsSection: View {
    let viewModel: RecurringBillsViewModel

    @State private var billPendingDelete: RecurringBillEntity? = nil
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            if viewModel.bills.isEmpty {
                emptyState
            } else if viewModel.sortedBills.isEmpty {
                allInactiveState
            } else {
                billsList
            }
        }
        .padding(.bottom, Spacing.md)
        .sheet(isPresented: Binding(
            get: { viewModel.showAddEditSheet },
            set: { viewModel.showAddEditSheet = $0 }
        )) {
            AddEditBillSheet(existing: viewModel.editingBill) { saved in
                viewModel.save(saved)
                viewModel.editingBill = nil
            }
        }
        .sheet(item: Binding(
            get: { viewModel.billToMarkPaid },
            set: { viewModel.billToMarkPaid = $0 }
        )) { bill in
            MarkBillPaidSheet(
                title: "Mark \(bill.name) Paid",
                subtitle: subtitleForBill(bill),
                candidates: viewModel.paymentCandidates(for: bill),
                onConfirm: { txnId in
                    viewModel.markPaid(bill: bill, transactionId: txnId)
                }
            )
        }
        .confirmationDialog(
            "Delete bill",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let b = billPendingDelete {
                    viewModel.delete(b.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let b = billPendingDelete {
                Text("Remove \(b.name)? Past payment history stays in the transactions feed.")
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recurring Bills")
                    .font(.titleLarge)
                    .foregroundStyle(Color.textPrimary)
                if viewModel.unpaidCount > 0 && viewModel.hasSalary {
                    Text("\(viewModel.unpaidCount) due — reminders running")
                        .font(.caption)
                        .foregroundStyle(Color.warningAmber)
                } else if viewModel.unpaidCount > 0 {
                    Text("\(viewModel.unpaidCount) due — reminders wait for salary credit")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("All paid this cycle")
                        .font(.caption)
                        .foregroundStyle(Color.incomeGreen)
                }
            }
            Spacer()
            Button {
                viewModel.editingBill = nil
                viewModel.showAddEditSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.brandPrimary.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, Spacing.base)
    }

    private var billsList: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(viewModel.sortedBills) { bill in
                BillCard(
                    bill: bill,
                    salaryReceived: viewModel.hasSalary,
                    onMarkPaid: {
                        viewModel.billToMarkPaid = bill
                    },
                    onEdit: {
                        viewModel.editingBill = bill
                        viewModel.showAddEditSheet = true
                    }
                )
                .padding(.horizontal, Spacing.base)
                .contextMenu {
                    if !bill.isDueThisCycle {
                        Button {
                            viewModel.resetLastPaid(billId: bill.id)
                        } label: {
                            Label("Mark as unpaid", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button {
                        viewModel.editingBill = bill
                        viewModel.showAddEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        billPendingDelete = bill
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Button {
            viewModel.editingBill = nil
            viewModel.showAddEditSheet = true
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandPrimary)
                Text("Track recurring bills")
                    .font(.titleMedium)
                    .foregroundStyle(Color.textPrimary)
                Text("Rent, electricity, postpaid — get reminded after every salary credit.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.brandPrimary.opacity(0.3),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.base)
    }

    private var allInactiveState: some View {
        Text("All bills paused. Activate one to resume tracking.")
            .font(.caption)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.base)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .padding(.horizontal, Spacing.base)
    }

    private func subtitleForBill(_ bill: RecurringBillEntity) -> String {
        let amt = bill.amount.map { " of \($0.currencyString)" } ?? ""
        return "Pick the transaction\(amt) that paid this bill, or mark it paid without linking."
    }
}
