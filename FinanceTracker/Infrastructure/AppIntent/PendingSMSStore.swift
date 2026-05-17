import Foundation

/// Shared queue between LogBankSMSIntent (runs while phone is locked) and the main app.
///
/// The App Group UserDefaults suite is accessible from both the intent process and the
/// main app, allowing the intent to enqueue SMS texts that the app drains on next foreground.
enum PendingSMSStore {

    static let appGroupSuite = "group.com.sovinnour.FinanceTracker"
    private static let queueKey = "pendingSMSQueue"

    /// Adds a raw SMS text to the shared queue. No-ops if the text is already queued.
    static func enqueue(_ text: String) {
        guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return }
        var queue = defaults.stringArray(forKey: queueKey) ?? []
        guard !queue.contains(text) else { return }
        queue.append(text)
        defaults.set(queue, forKey: queueKey)
    }

    /// Returns all queued SMS texts and clears the queue atomically.
    static func drainQueue() -> [String] {
        guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return [] }
        let queue = defaults.stringArray(forKey: queueKey) ?? []
        defaults.removeObject(forKey: queueKey)
        return queue
    }
}
