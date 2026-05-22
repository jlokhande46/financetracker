import AppIntents
import Foundation

/// An App Intent that receives a bank SMS text and queues it for FinanceTracker to process.
///
/// Because `openAppWhenRun` is false, iOS runs this intent silently in the background
/// without launching the app UI — so it works even when the iPhone is locked. The SMS is
/// written to a shared App Group UserDefaults queue; the main app drains the queue and
/// saves transactions the next time it enters the foreground.
///
/// Immediately after enqueueing, the intent posts a local notification with the
/// parsed amount + merchant so the user gets real-time feedback that the
/// automation caught the SMS — instead of only finding out the next time
/// they open the app.
///
/// ## Shortcuts setup (replaces the old "Open URL" approach)
///
/// 1. Open Shortcuts → tap "+" → search for "Log Bank SMS".
/// 2. Tap the action and set the SMS parameter to "Shortcut Input".
/// 3. Delete the old steps (URL Encode, URL, Open URL) — this single action replaces them.
/// 4. In your bank SMS automation, set the action to this shortcut.
///    Trigger by Sender (e.g. HDFCBK, SBICRD) — no keyword filter needed.
struct LogBankSMSIntent: AppIntent {

    static var title: LocalizedStringResource = "Log Bank SMS"
    static var description: IntentDescription? = IntentDescription(
        "Queues a bank transaction SMS for FinanceTracker to save. Works silently even when the iPhone is locked — the transaction is saved the next time you open the app."
    )

    // Critical: false means iOS runs this in the background without opening the app.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "SMS Text", description: "The full text of the bank transaction SMS.")
    var smsText: String

    func perform() async throws -> some IntentResult {
        let text = smsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .result() }

        let now = Date()
        SMSAuditStore.record(.receivedViaIntent, text: text, at: now)
        PendingSMSStore.enqueue(text, at: now)

        // Parse + normalise so the immediate alert can preview the amount and
        // merchant. SMSParser / MerchantNormalizer don't depend on a SwiftData
        // context, so they work inside the intent process. Classification
        // (CategoryClassifier) DOES need MerchantRuleStore's model context,
        // so the saved transaction's category is still computed by the main
        // app — the notification just shows what the SMS contained.
        let parsed = SMSParser.shared.parse(text)
        if parsed == nil {
            SMSAuditStore.record(.parseFailed, text: text, at: now,
                                 detail: "No known bank format matched (intent-time preview).")
        }
        await MainActor.run {
            NotificationManager.shared.fireSMSReceivedAlert(parsed: parsed, rawText: text)
        }
        return .result()
    }
}
