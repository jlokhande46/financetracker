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
    var groupedTransactions: [TransactionGroup] = []
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
    /// 50 rather than 100: per-page cost is dominated by model→entity
    /// conversion, so halving the page halves the worst-case hitch. The
    /// prefetch threshold below starts the next page early enough that the
    /// smaller page size is never visible as an empty scroll.
    private let pageSize = 50

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

        // Drop memoised day headers so "Today"/"Yesterday" can't go stale if
        // the app sat open across midnight.
        dayKeyCache.removeAll(keepingCapacity: true)

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
    ///
    /// The `isLoadingMore` flag already collapses the burst of `onAppear`
    /// calls that fire as several trailing rows enter view together, so no
    /// artificial debounce is needed — an earlier 100ms `Task.sleep` here was
    /// pure added latency on the exact interaction it was meant to smooth.
    func loadMoreIfNeeded() async {
        guard hasMorePages, !isLoadingMore else { return }
        guard !hasActiveFilters && searchText.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let page = transactionRepo.fetchPage(beforeDate: oldestLoadedDate, limit: pageSize)
        guard !page.transactions.isEmpty else {
            hasMorePages = page.hasMore
            return
        }

        allTransactions.append(contentsOf: page.transactions)
        oldestLoadedDate = page.oldestDate ?? oldestLoadedDate
        hasMorePages = page.hasMore

        // Union just the new page's tags rather than rescanning every loaded row.
        var tagSet = Set(allKnownTags)
        for t in page.transactions { for tag in t.tags { tagSet.insert(tag) } }
        allKnownTags = Array(tagSet).sorted()

        // `fetchPage` walks strictly backwards in time, so under the default
        // newest-first sort the incoming rows all belong AFTER everything
        // already on screen. That lets us splice them on in O(page) instead of
        // re-filtering, re-sorting and re-grouping the entire accumulated set
        // — which made each successive page cost more than the last (page 5
        // was re-processing 500 rows) and is what produced the multi-second
        // hitch when scrolling back through history.
        //
        // The other sort orders interleave with existing rows, so they still
        // take the full rebuild.
        if sortOrder == .dateDesc {
            appendPageToGroups(page.transactions)
        } else {
            applyFilters()
        }
    }

    /// Splice a newly-fetched page onto the end of the existing feed.
    /// Rows continuing the last visible day extend that group; the rest form
    /// new groups after it.
    private func appendPageToGroups(_ newRows: [TransactionEntity]) {
        filteredTransactions.append(contentsOf: newRows)

        let calendar = Calendar.current
        var groups = groupedTransactions

        for txn in newRows {
            let key = relativeDay(for: txn.date, calendar: calendar)
            if let last = groups.last, last.key == key {
                var rows = last.transactions
                rows.append(txn)
                groups[groups.count - 1] = TransactionGroup(
                    key: key,
                    transactions: rows,
                    debitTotal: last.debitTotal + (txn.isDebit ? txn.amount : 0),
                    creditTotal: last.creditTotal + (txn.isCredit ? txn.amount : 0)
                )
            } else {
                groups.append(TransactionGroup(
                    key: key,
                    transactions: [txn],
                    debitTotal: txn.isDebit ? txn.amount : 0,
                    creditTotal: txn.isCredit ? txn.amount : 0
                ))
            }
        }

        groupedTransactions = groups
    }

    /// Returns true if the given transaction is among the trailing rows of
    /// the currently-loaded set — used by the View to decide when to prefetch
    /// the next page. Threshold keeps the user from ever seeing an empty scroll.
    func isNearEndOfLoadedSet(_ transaction: TransactionEntity) -> Bool {
        guard hasMorePages else { return false }
        let prefetchThreshold = 25
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
    /// One day-section of the feed. `debitTotal` / `creditTotal` are computed
    /// once here at grouping time rather than inside the pinned section header,
    /// which SwiftUI re-evaluates constantly while scrolling — two
    /// `filter().reduce()` passes per header per frame was pure waste.
    struct TransactionGroup: Identifiable {
        let key: String
        let transactions: [TransactionEntity]
        let debitTotal: Decimal
        let creditTotal: Decimal
        var id: String { key }
    }

    func groupTransactions(_ txns: [TransactionEntity]) -> [TransactionGroup] {
        let calendar = Calendar.current
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

        return keyOrder.map { key in
            let rows = keyedMap[key] ?? []
            // Single pass for both totals instead of two filter+reduce passes.
            var debit: Decimal = 0
            var credit: Decimal = 0
            for t in rows {
                if t.isDebit { debit += t.amount } else { credit += t.amount }
            }
            return TransactionGroup(
                key: key,
                transactions: rows,
                debitTotal: debit,
                creditTotal: credit
            )
        }
    }

    private let groupHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        return f
    }()

    /// Day-header strings memoised by start-of-day. `DateFormatter.string(from:)`
    /// costs tens of microseconds and grouping called it once PER TRANSACTION —
    /// so a 500-row feed paid 500 formatter calls every time it regrouped. A
    /// feed spans maybe 30-60 distinct days, so caching collapses that to one
    /// call per day.
    private var dayKeyCache: [Date: String] = [:]

    private func relativeDay(for date: Date, calendar: Calendar) -> String {
        let dayStart = calendar.startOfDay(for: date)
        if let cached = dayKeyCache[dayStart] { return cached }
        let key = computeRelativeDay(for: date, calendar: calendar)
        dayKeyCache[dayStart] = key
        return key
    }

    private func computeRelativeDay(for date: Date, calendar: Calendar) -> String {
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
        patchInPlace(updated)
    }

    /// Replace a single transaction everywhere it's cached without re-running
    /// the whole filter → sort → group pipeline.
    ///
    /// `applyFilters()` rebuilds `filteredTransactions` AND every
    /// `TransactionGroup`, which hands SwiftUI brand-new array identities and
    /// forces it to diff the entire feed. For a one-row edit (intent override,
    /// note, tag, recurring flag) that's the difference between re-rendering
    /// one row and re-rendering all of them — very visible as lag when you
    /// swipe a row to mark Need/Want.
    ///
    /// Intent/notes/tags never affect membership or ordering, so surgical
    /// replacement is safe. Anything that COULD change filtering or sort order
    /// (category edits under an active category filter, date changes, deletes)
    /// still goes through `applyFilters()`.
    private func patchInPlace(_ updated: TransactionEntity) {
        if let idx = allTransactions.firstIndex(where: { $0.id == updated.id }) {
            allTransactions[idx] = updated
        }
        if let idx = filteredTransactions.firstIndex(where: { $0.id == updated.id }) {
            filteredTransactions[idx] = updated
        }
        for gIdx in groupedTransactions.indices {
            guard let rIdx = groupedTransactions[gIdx].transactions
                .firstIndex(where: { $0.id == updated.id }) else { continue }
            var rows = groupedTransactions[gIdx].transactions
            rows[rIdx] = updated
            // Totals can shift if the amount or direction changed.
            var debit: Decimal = 0
            var credit: Decimal = 0
            for t in rows {
                if t.isDebit { debit += t.amount } else { credit += t.amount }
            }
            groupedTransactions[gIdx] = TransactionGroup(
                key: groupedTransactions[gIdx].key,
                transactions: rows,
                debitTotal: debit,
                creditTotal: credit
            )
            break
        }
    }

    /// Persist a brand-new transaction (manual add) and show it immediately.
    ///
    /// This previously did NOT exist: `AddTransactionView` handed its entity to
    /// a closure that only inserted into the in-memory array, so every
    /// manually-added transaction was lost on the next reload. The repo write
    /// is the whole point — the local array update is just so the row appears
    /// without waiting for a refetch.
    func addTransaction(_ txn: TransactionEntity) {
        transactionRepo.save(txn)
        allTransactions.insert(txn, at: 0)
        for tag in txn.tags where !allKnownTags.contains(tag) {
            allKnownTags = (allKnownTags + [tag]).sorted()
        }
        applyFilters()
    }

    func updateTransaction(_ updated: TransactionEntity) {
        transactionRepo.update(updated)

        // Only fall back to the full filter → sort → group rebuild when the
        // edit could actually change which rows show or in what order. Edits
        // from the detail sheet are usually notes / tags / account / recurring
        // / intent, none of which move a row — those take the cheap path.
        let previous = allTransactions.first { $0.id == updated.id }
        let affectsMembershipOrOrder: Bool = {
            guard let previous else { return true }
            return previous.categorySlug != updated.categorySlug   // category filter
                || previous.type         != updated.type           // type filter
                || previous.source       != updated.source         // source filter
                || previous.tags         != updated.tags           // tag filter
                || previous.amount       != updated.amount         // amountDesc sort
                || previous.date         != updated.date           // date sort + day grouping
                || previous.merchantName != updated.merchantName   // search text
                || previous.merchantRaw  != updated.merchantRaw
                || previous.notes        != updated.notes
        }()

        if affectsMembershipOrOrder {
            if let idx = allTransactions.firstIndex(where: { $0.id == updated.id }) {
                allTransactions[idx] = updated
            }
            applyFilters()
        } else {
            patchInPlace(updated)
        }
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
