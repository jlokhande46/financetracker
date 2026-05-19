import Foundation

/// Handles `financetracker://import?sms=<encoded text>` deep links.
///
/// Instead of surfacing the SMS to the UI (which would open the paste sheet),
/// the text is enqueued in `PendingSMSStore` — the same queue used by
/// `LogBankSMSIntent`. `AppContainer.processPendingSMS()` drains the queue
/// and saves the transaction silently whenever the app is active.
@Observable
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()
    private init() {}

    // Dedup state — iOS or the Shortcuts pipeline can fire the same URL more than once
    // when the app is already foregrounded. Ignore identical payloads within a 10-second
    // window so we don't double-save the same SMS.
    private var lastHandledHash: Int = 0
    private var lastHandledAt: Date = .distantPast

    /// Parse `financetracker://import?sms=<encoded text>` and silently enqueue it.
    /// Returns `true` if a new SMS was enqueued (so the caller can drain immediately).
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "financetracker",
              url.host?.lowercased() == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sms = components.queryItems?.first(where: { $0.name == "sms" })?.value,
              !sms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        let hash = sms.hashValue
        let now = Date()
        if hash == lastHandledHash && now.timeIntervalSince(lastHandledAt) < 10 {
            return false
        }
        lastHandledHash = hash
        lastHandledAt = now
        PendingSMSStore.enqueue(sms)
        return true
    }
}
