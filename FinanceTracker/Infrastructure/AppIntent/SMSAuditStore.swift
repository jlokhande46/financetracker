import Foundation

/// A rolling per-event log of everything the SMS pipeline does, written to
/// the same App Group as `PendingSMSStore` so both the LogBankSMSIntent
/// process and the main app contribute to the same trace.
///
/// Surfaced in Developer Options → SMS Activity so the user can answer:
/// "I sent an SMS — what happened to it?" Was it ever received by the
/// automation? Did it parse? Did it get saved? Was it suppressed as a
/// duplicate? The log is FIFO-capped at 100 entries.
enum SMSAuditStore {

    static let appGroupSuite = "group.com.sovinnour.FinanceTracker"
    private static let logKey = "smsAuditLog"
    private static let maxEntries = 100

    enum Kind: String, Codable, CaseIterable {
        /// LogBankSMSIntent.perform was invoked (Shortcuts automation fired).
        case receivedViaIntent
        /// DeepLinkHandler.handle parsed a `financetracker://import?sms=…` URL.
        case receivedViaURL
        /// Successfully appended to PendingSMSStore.
        case enqueued
        /// PendingSMSStore.enqueue de-duped against an identical pending entry.
        case enqueueDeduped
        /// SMSParser returned nil — no known bank format matched.
        case parseFailed
        /// AppContainer.processPendingSMS saved the SMS as a transaction.
        case savedAsTransaction
        /// processPendingSMS detected the same rawContent within the last 2m
        /// and skipped saving to avoid a duplicate row.
        case savedDeduped

        var label: String {
            switch self {
            case .receivedViaIntent:   return "Intent received"
            case .receivedViaURL:      return "URL received"
            case .enqueued:            return "Queued"
            case .enqueueDeduped:      return "Queue duplicate"
            case .parseFailed:         return "Parse failed"
            case .savedAsTransaction:  return "Saved"
            case .savedDeduped:        return "Skipped (duplicate)"
            }
        }

        var icon: String {
            switch self {
            case .receivedViaIntent:   return "tray.and.arrow.down.fill"
            case .receivedViaURL:      return "arrow.up.right.square.fill"
            case .enqueued:            return "arrow.down.to.line"
            case .enqueueDeduped:      return "doc.on.doc"
            case .parseFailed:         return "exclamationmark.triangle.fill"
            case .savedAsTransaction:  return "checkmark.seal.fill"
            case .savedDeduped:        return "arrow.uturn.left"
            }
        }
    }

    struct Event: Codable, Identifiable, Hashable {
        let id: UUID
        let timestamp: Date
        let kind: Kind
        /// First ~120 chars of the SMS so we don't fill UserDefaults with
        /// full-text duplicates of every queued message.
        let textPreview: String
        /// Optional supplementary info — parser result, error reason, etc.
        let detail: String?

        init(id: UUID = UUID(),
             timestamp: Date = Date(),
             kind: Kind,
             textPreview: String,
             detail: String? = nil) {
            self.id = id
            self.timestamp = timestamp
            self.kind = kind
            self.textPreview = textPreview
            self.detail = detail
        }
    }

    /// Append an event. Safe to call from the App Intent process AND the
    /// main app (App Group UserDefaults is the shared store).
    static func record(_ kind: Kind, text: String, at timestamp: Date = Date(), detail: String? = nil) {
        guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return }
        var log = readLog(defaults: defaults)
        log.append(Event(
            timestamp: timestamp,
            kind: kind,
            textPreview: String(text.prefix(120)),
            detail: detail
        ))
        if log.count > maxEntries {
            log = Array(log.suffix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(log) {
            defaults.set(data, forKey: logKey)
            defaults.synchronize()
        }
    }

    /// Newest-first snapshot for UI display.
    static func snapshot() -> [Event] {
        guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return [] }
        return readLog(defaults: defaults).reversed()
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return }
        defaults.removeObject(forKey: logKey)
        defaults.synchronize()
    }

    static var count: Int {
        guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return 0 }
        return readLog(defaults: defaults).count
    }

    private static func readLog(defaults: UserDefaults) -> [Event] {
        guard let data = defaults.data(forKey: logKey),
              let log = try? JSONDecoder().decode([Event].self, from: data)
        else { return [] }
        return log
    }
}
