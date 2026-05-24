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
    var selectedTags: Set<String> = [] {
        didSet { applyFilters() }
    }
    var sortOrder: SortOrder = .dateDesc {
        didSet { applyFilters() }
    }

    var showAddSheet: Bool = false
    var showFilterSheet: Bool = false
    var isLoading: Bool = false
    /// Indicates an in-flight pagination fetch — used by the feed to show a
    /// "Loading more…" spinner under the last group without blocking the UI.
    var isLoadingMore: Bool = false
    /// Set after a bulk recategorization; the view shows a toast and then clears this.
    var bulkUpdateMessage: String? = nil

    // MARK: - Pagination state
    /// Date of the OLDEST transaction currently loaded. Passed to
    /// `transactionRepo.fetchPage(beforeDate:)` to fetch the next older page.
    private var oldestLoadedDate: Date? = nil
    /// `true` while more older rows exist in the DB beyond what's currently
    /// loaded. Flipped to `false` once we exhaust the table OR switch into
    /// full-fetch mode (filters / search active).
    private(set) var hasMorePages: Bool = false
    /// Default page size — chosen to keep initial load fast on big histories
    /// while still filling 1-2 screens of the feed for the average user.
    private let pageSize = 100

    var hasActiveFilters: Bool {
        selectedCategory != nil || selectedSource != nil || selectedType != nil || !selectedTags.isEmpty
    }

    /// Every tag ever used across transactions (sorted) — feeds the filter sheet.
    /// Cached per load cycle to avoid O(n) recalculation on every SwiftUI body
    /// evaluation (which @Observable triggers frequently during scroll).
    private(set) var allKnownTags: [String] = []

    private func rebuildKnownTags() {
        var set = Set<String>()
        for t in allTransactions { for tag in t.tags { set.insert(tag) } }
        allKnownTags = Array(set).sorted()
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

        // Initial fetch: when filters or search are active, the user expects
        // the result set to span the entire history — fall back to full fetch.
        // Otherwise start with a paginated first page; older rows load on
        // scroll-end via `loadMoreIfNeeded`.
        if hasActiveFilters || !searchText.isEmpty {
            allTransactions = transactionRepo.fetchAll()
            oldestLoadedDate = allTransactions.last?.date
            hasMorePages = false
        } else {
            let page = transactionRepo.fetchPage(beforeDate: nil, limit: pageSize)
            allTransactions = page.transactions
            oldestLoadedDate = page.oldestDate
            hasMorePages = page.hasMore
        }

        pendingReviewTransactions = transactionRepo.fetchPendingReview()
        rebuildKnownTags()
        applyFilters()
    }

    /// Loads the next older page when the feed scrolls near the bottom.
    /// No-op when pagination is exhausted, a fetch is already in flight, or
    /// the view is in filter/search mode (which holds the full result set).
    /// Tiny debounce (100ms) avoids the scenario where multiple rows near
    /// the bottom all fire onAppear within the same scroll frame and pile
    /// up redundant fetches / re-renders.
    func loadMoreIfNeeded() async {
        guard hasMorePages, !isLoadingMore else { return }
        guard !hasActiveFilters && searchText.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard hasMorePages, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let page = transactionRepo.fetchPage(beforeDate: oldestLoadedDate, limit: pageSize)
        allTransactions.append(contentsOf: page.transactions)
        oldestLoadedDate = page.oldestDate ?? oldestLoadedDate
        hasMorePages = page.hasMore
        rebuildKnownTags()
        applyFilters()
    }

    /// Returns true if the given transaction is among the trailing rows of
    /// the currently-loaded set — used by the View to decide when to prefetch
    /// the next page. Threshold keeps the user from ever seeing an empty scroll.
    func isNearEndOfLoadedSet(_ transaction: TransactionEntity) -> Bool {
        guard hasMorePages else { return false }
        let prefetchThreshold = 15
        guard let idx = allTransactions.firstIndex(where: { $0.id == transaction.id }) else { return false }
        return idx >= allTransactions.count - prefetchThreshold
    }

    // MARK: - Filter & Sort
    func applyFilters() {
        // Filters/search must span the entire history. If we're currently
        // holding a paginated subset, upgrade to a full fetch so the user
        // doesn't get partial results. Falls back to no-op once already full.
        if (hasActiveFilters || !searchText.isEmpty) && hasMorePages {
            allTransactions = transactionRepo.fetchAll()
            oldestLoadedDate = allTransactions.last?.date
            hasMorePages = false
        }

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

        // Tags — match if transaction has any of the selected tags
        if !selectedTags.isEmpty {
            result = result.filter { txn in
                !Set(txn.tags).intersection(selectedTags).isEmpty
            }
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
        newTags: [String]? = nil,
        rememberName: Bool,
        rememberCategory: Bool,
        applyToPast: Bool = false
    ) {
        var updated = transaction
        if let n = newName, !n.isEmpty {
            updated.merchantName = n
        }
        updated.categorySlug = newSlug
        if let newTags { updated.tags = newTags }
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
        selectedTags = []
    }

    func refresh() {
        Task { await load() }
    }
}
