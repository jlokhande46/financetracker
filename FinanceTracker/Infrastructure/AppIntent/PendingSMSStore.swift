import Foundation

/// Shared queue between LogBankSMSIntent (runs while phone is locked) and the main app.
///
/// The App Group UserDefaults suite is accessible from both the intent process and the
/// main app, allowing the intent to enqueue SMS texts that the app drains on next foreground.
///
/// Each queued item carries the timestamp it was enqueued — used by
/// `AppContainer.processPendingSMS` to preserve transaction *sequence* even
/// when the bank SMS itself only captured a date (no time-of-day), and to
/// stamp the persisted transaction's `createdAt` with the real receipt time
/// rather than the time the user happened to open the app.
enum PendingSMSStore {

    static let appGroupSuite = "group.com.sovinnour.FinanceTracker"
    /// New v2 key carries `[Item]` JSON. The legacy `pendingSMSQueue` (raw
    /// `[String]`) is drained one last time at read for backward compat.
    private static let queueKey = "pendingSMSQueueV2"
    private static let legacyQueueKey = "pendingSMSQueue"

    struct Item: Codable, Equatable {
        let text: String
        let enqueuedAt: Date
    }

    /// Never nil. Falls back to `.standard` when the App Group entitlement is
    /// unavailable (common on sideloaded / free-team builds) so the in-process
    /// SMS paths keep working instead of silently dropping every message.
    private static func store() -> UserDefaults? {
        AppGroupStore.defaults()
    }

    /// Adds a raw SMS text to the shared queue alongside the timestamp it
    /// was received. No-ops if the same text is already queued.
    static func enqueue(_ text: String, at date: Date = Date()) {
        guard let defaults = store() else { return }
        var items = readItems(defaults: defaults)
        guard !items.contains(where: { $0.text == text }) else {
            SMSAuditStore.record(.enqueueDeduped, text: text, at: date,
                                 detail: "Same text already in queue, not re-added.")
            return
        }
        items.append(Item(text: text, enqueuedAt: date))
        writeItems(items, defaults: defaults)
        SMSAuditStore.record(.enqueued, text: text, at: date)
    }

    /// Returns all queued items in arrival order and clears the queue
    /// (including any leftover legacy `[String]` entries).
    static func drainItems() -> [Item] {
        guard let defaults = store() else { return [] }
        let items = readItems(defaults: defaults)
        guard !items.isEmpty else { return [] }
        defaults.removeObject(forKey: queueKey)
        defaults.removeObject(forKey: legacyQueueKey)
        defaults.synchronize()
        return items
    }

    /// Back-compat shim: existing call sites that just want texts.
    static func drainQueue() -> [String] {
        drainItems().map(\.text)
    }

    /// Non-destructive count — used by Developer Options diagnostics.
    static var pendingCount: Int {
        guard let defaults = store() else { return 0 }
        return readItems(defaults: defaults).count
    }

    // MARK: - Private storage

    private static func readItems(defaults: UserDefaults) -> [Item] {
        var combined: [Item] = []
        if let data = defaults.data(forKey: queueKey),
           let items = try? JSONDecoder().decode([Item].self, from: data) {
            combined = items
        }
        // Migrate any legacy entries on the fly so a user upgrading mid-queue
        // doesn't lose their pending SMS. Treat unknown enqueued-time as now.
        if let legacy = defaults.stringArray(forKey: legacyQueueKey), !legacy.isEmpty {
            let migrated = legacy.map { Item(text: $0, enqueuedAt: Date()) }
            for m in migrated where !combined.contains(where: { $0.text == m.text }) {
                combined.append(m)
            }
        }
        return combined
    }

    private static func writeItems(_ items: [Item], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: queueKey)
        defaults.synchronize()
    }
}
