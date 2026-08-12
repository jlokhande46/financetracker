import Foundation

/// Beta feature — LLM-powered fallback for any SMS format the built-in
/// SMSParser can't crack, and any PDF the built-in PDFStatementParser
/// bails on.
///
/// Native parsers always run first (they're fast, deterministic, offline,
/// and free). If they return nil AND the user has explicitly enabled the
/// LLM beta with a valid API key, the raw text is sent to the configured
/// LLM and the returned JSON is parsed back into `ParsedSMSResult`.
///
/// Privacy: every call sends the raw SMS/PDF text to a third-party
/// provider (currently Anthropic only). Users are warned about this in
/// the settings sheet and the beta is opt-in.
final class LLMParser {

    static let shared = LLMParser()
    private init() {}

    /// Parses a single SMS. Returns nil when:
    ///   - Beta is disabled or no API key
    ///   - Network / API failure
    ///   - LLM decides the text isn't a bank transaction
    func parseSMS(_ text: String) async -> ParsedSMSResult? {
        guard LLMSettings.isReady, let key = LLMKeychain.apiKey() else { return nil }

        let system = Self.smsSystemPrompt
        let userMessage = text

        do {
            let json = try await callAnthropic(
                system: system,
                user: userMessage,
                apiKey: key,
                model: LLMSettings.model,
                maxTokens: 400
            )
            return Self.parseSMSResponseJSON(json, rawText: text)
        } catch {
            LLMAuditLog.record(.smsFailure(error: error.localizedDescription), text: text)
            return nil
        }
    }

    /// Parses a full PDF statement's extracted text. Returns every
    /// transaction the LLM identifies. Skips fees, running balances,
    /// non-transaction rows. Called AFTER `PDFStatementParser.parse`
    /// so this is only invoked when the native pipeline finds nothing.
    func parsePDFText(_ text: String) async -> [ParsedSMSResult] {
        guard LLMSettings.isReady, let key = LLMKeychain.apiKey() else { return [] }

        // Trim to a reasonable prompt size — most CC statements fit in
        // 20-30k chars. Chunking beyond one call would be phase-2.
        let clipped = String(text.prefix(30_000))
        let system = Self.pdfSystemPrompt

        do {
            let json = try await callAnthropic(
                system: system,
                user: clipped,
                apiKey: key,
                model: LLMSettings.model,
                maxTokens: 4_000
            )
            let items = Self.parsePDFResponseJSON(json)
            LLMAuditLog.record(.pdfSuccess(count: items.count), text: "PDF text (\(clipped.count) chars)")
            return items
        } catch {
            LLMAuditLog.record(.pdfFailure(error: error.localizedDescription), text: "PDF text (\(clipped.count) chars)")
            return []
        }
    }

    // MARK: - Prompts

    private static let smsSystemPrompt = """
    You are a bank transaction extractor. Given an SMS message, return ONLY \
    a JSON object matching this schema, or the string "null" if the SMS is \
    not a bank/credit-card transaction (promotional, OTP, balance-only \
    notification, etc.).

    Schema:
    {
      "amount": number,             // Positive decimal amount
      "type": "debit" | "credit",   // debit = money out, credit = money in
      "merchantRaw": string,        // Merchant or counterparty name from the SMS, verbatim
      "last4": string | null,       // Last 4 digits of card/account if mentioned
      "date": string | null,        // ISO 8601 date (YYYY-MM-DD) if mentioned
      "upiRef": string | null,      // UPI reference id if mentioned
      "bankRef": string | null      // Bank transaction id if mentioned
    }

    Rules:
    - Output ONLY the JSON object or the literal string null. No explanation.
    - Do NOT wrap in ```json fences.
    - For CC bill payments (bpps, cc payment, card payment), use "credit".
    - Skip OTPs, balance alerts without a transaction, and marketing SMS.
    """

    private static let pdfSystemPrompt = """
    You are a bank statement extractor. Given the raw text of a bank or \
    credit-card PDF statement, return a JSON array of every transaction. \
    Return [] if none found.

    Each item matches this schema:
    {
      "amount": number,             // Positive decimal
      "type": "debit" | "credit",
      "merchantRaw": string,        // Description / merchant / narration
      "last4": string | null,       // Card or account last 4 if inferable for that row
      "date": string | null,        // ISO 8601 date (YYYY-MM-DD)
      "upiRef": string | null,
      "bankRef": string | null
    }

    Rules:
    - Output ONLY the JSON array. No prose, no ```json fences.
    - Skip: finance charges, GST, late fees, joining/annual fees, service tax, \
      running balances, opening/closing balances, credit-limit summaries, \
      MITC / marketing / legal / rewards summary rows.
    - Credit-card payments made toward this card (BPPS / CC PAYMENT / \
      PAYMENT RECEIVED / THANK YOU) → type "credit".
    - Refunds and cashback → type "credit".
    - Everything else the cardholder charged → type "debit".
    - Preserve the merchant string verbatim so the app's normaliser can \
      match user rules.
    """

    // MARK: - HTTP

    private struct AnthropicMessagesRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct AnthropicMessagesResponse: Decodable {
        let content: [Block]
        struct Block: Decodable {
            let type: String
            let text: String?
        }
    }

    private struct AnthropicError: Decodable {
        let error: ErrorBody
        struct ErrorBody: Decodable {
            let type: String
            let message: String
        }
    }

    enum LLMError: LocalizedError {
        case badResponse(status: Int, body: String)
        case emptyContent
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let status, let body): return "HTTP \(status): \(body.prefix(200))"
            case .emptyContent:                       return "LLM returned no content"
            case .decodeFailed(let msg):              return "Decode failed: \(msg)"
            }
        }
    }

    private func callAnthropic(
        system: String,
        user: String,
        apiKey: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body = AnthropicMessagesRequest(
            model: model,
            max_tokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: user)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.badResponse(status: -1, body: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "<binary>"
            throw LLMError.badResponse(status: http.statusCode, body: errorBody)
        }

        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              !text.isEmpty else {
            throw LLMError.emptyContent
        }
        return text
    }

    // MARK: - JSON → ParsedSMSResult

    /// Shape returned by the LLM for a single transaction. Mirrors the
    /// system-prompt schema.
    private struct LLMTransactionDTO: Decodable {
        let amount: Decimal
        let type: String
        let merchantRaw: String
        let last4: String?
        let date: String?
        let upiRef: String?
        let bankRef: String?
    }

    private static func parseSMSResponseJSON(_ raw: String, rawText: String) -> ParsedSMSResult? {
        let trimmed = stripCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "null" { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let dto = try? JSONDecoder().decode(LLMTransactionDTO.self, from: data) else { return nil }
        return dto.toResult(rawText: rawText)
    }

    private static func parsePDFResponseJSON(_ raw: String) -> [ParsedSMSResult] {
        let trimmed = stripCodeFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return [] }
        guard let items = try? JSONDecoder().decode([LLMTransactionDTO].self, from: data) else { return [] }
        return items.compactMap { $0.toResult(rawText: "") }
    }

    /// LLMs sometimes wrap JSON in ```json ...``` even when asked not to.
    /// Strip fences before decoding.
    private static func stripCodeFences(_ s: String) -> String {
        var out = s
        if out.hasPrefix("```") {
            if let nl = out.firstIndex(of: "\n") {
                out = String(out[out.index(after: nl)...])
            }
        }
        if out.hasSuffix("```") {
            out = String(out.dropLast(3))
        }
        return out
    }
}

// MARK: - DTO → ParsedSMSResult conversion

private extension LLMParser.LLMTransactionDTO {
    func toResult(rawText: String) -> ParsedSMSResult? {
        guard amount > 0 else { return nil }
        let txnType: TransactionType = type.lowercased() == "credit" ? .credit : .debit
        return ParsedSMSResult(
            amount: amount,
            type: txnType,
            merchantRaw: merchantRaw.trimmingCharacters(in: .whitespacesAndNewlines),
            last4: last4,
            date: date.flatMap { parseISODate($0) },
            upiRef: upiRef,
            bankRef: bankRef,
            rawText: rawText
        )
    }

    private func parseISODate(_ str: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: str)
    }
}
