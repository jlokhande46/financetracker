import Foundation
import Observation

enum SortOrder: String, CaseIterable {
    case dateDesc   = "Newest First"
    case dateAsc    = "Oldest First"
    case amountDesc = "Highest Amount"
}

@Observable
@MainActor
final class TransactionListViewModel {

    // MARK: - State
    var allTransactions: [TransactionEntity] = []
    var filteredTransactions: [TransactionEntity] = []
    var groupedTransactions: [(key: String, transactions: [TransactionEntity])] = []
    var pendingReviewTransactions: [TransactionEntity] = []

    var searchText: String = "" {
        didSet { applyFilters() }
    }
    var selectedCategory: String? = nil {
        didSet { applyFilters() }
    }
    var selectedSource: TransactionSource? = nil {
        didSet { applyFilters() }
    }
    var selectedType: TransactionType? = nil {
        didSet { applyFilters() }
    }
    var sortOrder: SortOrder = .dateDesc {
        didSet { applyFilters() }
    }

    var showAddSheet: Bool = false
    var showFilterSheet: Bool = false
    var isLoading: Bool = false
    /// Set after a bulk recategorization; the view shows a toast and then clears this.
    var bulkUpdateMessage: String? = nil

    var hasActiveFilters: Bool {
        selectedCategory != nil || selectedSource != nil || selectedType != nil
    }

    // MARK: - Dependencies
    private let transactionRepo: TransactionRepositoryImpl
    private let accountRepo: AccountRepositoryImpl?

    // UUID → AccountEntity map, rebuilt on each load
    private(set) var accountMap: [UUID: AccountEntity] = [:]

    init(transactionRepo: TransactionRepositoryImpl, accountRepo: AccountRepositoryImpl? = nil) {
        self.transactionRepo = transactionRepo
        self.accountRepo     = accountRepo
    }

    func accountDisplay(for transaction: TransactionEntity) -> String? {
        guard let id = transaction.accountId, let account = accountMap[id] else { return nil }
        if let last4 = account.last4 { return "\(account.name) ••••\(last4)" }
        return account.name
    }

    // MARK: - Load
    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Rebuild account lookup
        let accounts = accountRepo?.fetchAll() ?? []
        accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        allTransactions = transactionRepo.fetchAll()
        pendingReviewTransactions = transactionRepo.fetchPendingReview()
        applyFilters()
    }

    // MARK: - Filter & Sort
    func applyFilters() {
        var result = allTransactions

        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.merchantName.lowercased().contains(query)
                || $0.merchantRaw.lowercased().contains(query)
                || ($0.notes?.lowercased().contains(query) ?? false)
                || $0.categorySlug.lowercased().contains(query)
            }
        }

        // Category
        if let slug = selectedCategory {
            result = result.filter { $0.categorySlug == slug }
        }

        // Source
        if let source = selectedSource {
            result = result.filter { $0.source == source }
        }

        // Type
        if let type = selectedType {
            result = result.filter { $0.type == type }
        }

        // Sort
        switch sortOrder {
        case .dateDesc:
            result.sort { $0.date > $1.date }
        case .dateAsc:
            result.sort { $0.date < $1.date }
        case .amountDesc:
            result.sort { $0.amount > $1.amount }
        }

        filteredTransactions = result
        groupedTransactions = groupTransactions(result)
    }

    // MARK: - Grouping
    func groupTransactions(_ txns: [TransactionEntity]) -> [(key: String, transactions: [TransactionEntity])] {
        let calendar = Calendar.current
        var groups: [(key: String, transactions: [TransactionEntity])] = []
        var keyedMap: [String: [TransactionEntity]] = [:]
        var keyOrder: [String] = []

        for txn in txns {
            let key = relativeDay(for: txn.date, calendar: calendar)
            if keyedMap[key] == nil {
                keyedMap[key] = []
                keyOrder.append(key)
            }
            keyedMap[key]?.append(txn)
        }

        for key in keyOrder {
            groups.append((key: key, transactions: keyedMap[key] ?? []))
        }

        return groups
    }

    private let groupHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        return f
    }()

    private func relativeDay(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return groupHeaderFormatter.string(from: date)
    }

    // MARK: - Actions
    func confirmCategory(transaction: TransactionEntity, newSlug: String, rememberMerchant: Bool = false) {
        confirmReview(
            transaction: transaction,
            newName: nil,
            newSlug: newSlug,
            rememberName: false,
            rememberCategory: rememberMerchant
        )
    }

    /// Full review action: updates name + category and optionally saves merchant rules
    /// for the name and/or category so future imports auto-apply them.
    /// When `applyToPast` is true (and `rememberCategory` is on), all existing transactions
    /// from the same merchant are re-categorized in bulk.
    func confirmReview(
        transaction: TransactionEntity,
        newName: String?,
        newSlug: String,
        rememberName: Bool,
        rememberCategory: Bool,
        applyToPast: Bool = false
    ) {
        var updated = transaction
        if let n = newName, !n.isEmpty {
            updated.merchantName = n
        }
        updated.categorySlug = newSlug
        updated.isConfirmed = true
        updated.confidence = 1.0
        transactionRepo.update(updated)

        if let idx = allTransactions.firstIndex(where: { $0.id == transaction.id }) {
            allTransactions[idx] = updated
        }
        pendingReviewTransactions.removeAll { $0.id == transaction.id }

        if rememberName || rememberCategory {
            MerchantRuleStore.shared.saveRule(
                merchant: transaction.merchantRaw.isEmpty ? transaction.merchantName : transaction.merchantRaw,
                categorySlug: rememberCategory ? newSlug : nil,
                displayName: rememberName ? newName : nil
            )
        }

        if applyToPast && rememberCategory {
            let key = transaction.merchantRaw.isEmpty ? transaction.merchantName : transaction.merchantRaw
            let count = transactionRepo.bulkRecategorize(
                merchantRaw: key,
                merchantNameKey: transaction.merchantName,
                newSlug: newSlug
            )
            if count > 0 {
                let catName = CategoryEntity.find(slug: newSlug).name
                bulkUpdateMessage = "Updated \(count) past transaction\(count == 1 ? "" : "s") to \(catName)"
                Task { await load() }
                return
            }
        }
        applyFilters()
    }

    /// Re-categorizes all past transactions for the given merchant in one shot.
    /// Used by `EditCategorySheet` when "Apply to past" is toggled on.
    func bulkRecategorize(transaction: TransactionEntity, newSlug: String) {
        let key = transaction.merchantRaw.isEmpty ? transaction.merchantName : transaction.merchantRaw
        let count = transactionRepo.bulkRecategorize(
            merchantRaw: key,
            merchantNameKey: transaction.merchantName,
            newSlug: newSlug
        )
        if count > 0 {
            let catName = CategoryEntity.find(slug: newSlug).name
            bulkUpdateMessage = "Updated \(count) past transaction\(count == 1 ? "" : "s") to \(catName)"
            Task { await load() }
        }
    }

    /// Set or clear the user's per-transaction intent override. Pass `nil` to
    /// fall back to the category's default intent.
    func setIntentOverride(transaction: TransactionEntity, intent: CategoryIntent?) {
        var updated = transaction
        updated.intentOverride = intent
        transactionRepo.update(updated)
        if let idx = allTransactions.firstIndex(where: { $0.id == transaction.id }) {
            allTransactions[idx] = updated
        }
        applyFilters()
    }

    func updateTransaction(_ updated: TransactionEntity) {
        transactionRepo.update(updated)
        if let idx = allTransactions.firstIndex(where: { $0.id == updated.id }) {
            allTransactions[idx] = updated
        }
        applyFilters()
    }

    func deleteTransaction(id: UUID) {
        transactionRepo.delete(id: id)
        allTransactions.removeAll { $0.id == id }
        pendingReviewTransactions.removeAll { $0.id == id }
        applyFilters()
    }

    func clearFilters() {
        selectedCategory = nil
        selectedSource = nil
        selectedType = nil
    }

    func refresh() {
        Task { await load() }
    }
}
