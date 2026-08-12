import Foundation

/// Lightweight per-event log for the LLM beta — every LLM call and its
/// outcome (success + result count / failure + error message) so the user
/// can debug parsing issues without wiring up a full trace UI. Surfaced
/// in Developer Options if we want; for beta, it just tails the last 50
/// events into UserDefaults.
enum LLMAuditLog {

    private static let key = "llmAuditLog"
    private static let maxEntries = 50

    enum Kind: Codable, Equatable {
        case smsSuccess(hasResult: Bool)
        case smsFailure(error: String)
        case pdfSuccess(count: Int)
        case pdfFailure(error: String)

        var label: String {
            switch self {
            case .smsSuccess(let has): return has ? "SMS parsed" : "SMS: no transaction"
            case .smsFailure(let e):   return "SMS failed: \(e.prefix(80))"
            case .pdfSuccess(let c):   return "PDF parsed (\(c) txns)"
            case .pdfFailure(let e):   return "PDF failed: \(e.prefix(80))"
            }
        }
    }

    struct Entry: Codable, Identifiable {
        var id: UUID
        var timestamp: Date
        var kind: Kind
        var textPreview: String

        init(kind: Kind, textPreview: String, timestamp: Date = Date()) {
            self.id = UUID()
            self.timestamp = timestamp
            self.kind = kind
            self.textPreview = textPreview
        }
    }

    static func record(_ kind: Kind, text: String) {
        var log = read()
        log.append(Entry(kind: kind, textPreview: String(text.prefix(120))))
        if log.count > maxEntries { log = Array(log.suffix(maxEntries)) }
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Newest-first snapshot for UI display.
    static func snapshot() -> [Entry] { read().reversed() }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static var count: Int { read().count }

    private static func read() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }
}
