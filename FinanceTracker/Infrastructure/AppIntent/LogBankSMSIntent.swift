import AppIntents

/// An App Intent that receives a bank SMS text and queues it for FinanceTracker to process.
///
/// Because `openAppWhenRun` is false, iOS runs this intent silently in the background
/// without launching the app UI — so it works even when the iPhone is locked. The SMS is
/// written to a shared App Group UserDefaults queue; the main app drains the queue and
/// saves transactions the next time it enters the foreground.
///
/// ## Shortcuts setup (replaces the old "Open URL" approach)
///
/// 1. Open Shortcuts → tap "+" → search for "Log Bank SMS".
/// 2. Tap the action and set the SMS parameter to "Shortcut Input".
/// 3. Delete the old steps (URL Encode, URL, Open URL) — this single action replaces all of them.
/// 4. In your bank SMS automation, set the action to this shortcut.
///    Trigger by Sender (e.g. HDFCBK, SBICRD) — no keyword filter needed.
struct LogBankSMSIntent: AppIntent {

    static var title: LocalizedStringResource = "Log Bank SMS"
    static var description = IntentDescription(
        "Queues a bank transaction SMS for FinanceTracker to save. " +
        "Works silently even when the iPhone is locked — the transaction " +
        "is saved the next time you open the app."
    )

    // Critical: false means iOS runs this in the background without opening the app.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "SMS Text", description: "The full text of the bank transaction SMS.")
    var smsText: String

    func perform() async throws -> some IntentResult {
        let text = smsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .result() }
        PendingSMSStore.enqueue(text)
        return .result()
    }
}
