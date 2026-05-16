import Foundation

/// Carries deep-link payloads across the view hierarchy.
/// Set `pendingSMSText` from `onOpenURL`; clear it once consumed.
@Observable
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()
    private init() {}

    var pendingSMSText: String? = nil

    // Dedup state — iOS or the Shortcuts pipeline can fire the same URL more than once
    // when the app is already foregrounded. Ignore identical payloads within a 10-second
    // window so we don't double-save the same SMS.
    private var lastHandledHash: Int = 0
    private var lastHandledAt: Date = .distantPast

    /// Parse `financetracker://import?sms=<encoded text>` and store the SMS.
    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "financetracker",
              url.host?.lowercased() == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sms = components.queryItems?.first(where: { $0.name == "sms" })?.value,
              !sms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let hash = sms.hashValue
        let now = Date()
        if hash == lastHandledHash && now.timeIntervalSince(lastHandledAt) < 10 {
            // Duplicate fire from the same SMS within 10s — ignore.
            return
        }
        lastHandledHash = hash
        lastHandledAt = now
        pendingSMSText = sms
    }
}
