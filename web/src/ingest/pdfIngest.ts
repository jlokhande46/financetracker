import { classify } from "../categorization/classifier";
import { merchantRuleKey, normalizeMerchant } from "../categorization/merchantNormalizer";
import { db, recordAudit } from "../db/db";
import type { ParsedPDFRow, PDFParseResult } from "../parsing/pdfParser";
import type { Transaction } from "../domain/types";
import { recalculateBalances } from "./ingest";

/**
 * Turning parsed statement rows into transactions.
 *
 * Statement import differs from SMS in two ways that matter:
 *
 *   - It is re-run. A user imports August, then imports it again next month
 *     alongside September. Dedup here is on the row's exact text with no time
 *     window (unlike SMS, where the same alert genuinely can repeat), so a
 *     re-import is a no-op rather than a doubled month.
 *   - Rows carry a direction confidence of their own. A row the parser guessed
 *     at goes to Review instead of being trusted, because a wrong direction is
 *     the difference between a ₹747 charge and a ₹747 refund.
 */

export interface PDFImportResult {
  saved: number;
  duplicates: number;
  needsReview: number;
  skipped: number;
  transactions: Transaction[];
}

export async function importParsedStatement(
  parsed: PDFParseResult,
  opts: { accountId?: string } = {},
): Promise<PDFImportResult> {
  const out: PDFImportResult = {
    saved: 0, duplicates: 0, needsReview: 0, skipped: 0, transactions: [],
  };

  if (parsed.columnScrambled) {
    await recordAudit(
      "parseFailed",
      parsed.rawText.slice(0, 120),
      "Table came out column-first; refused to guess row alignment.",
    );
    out.skipped = 1;
    return out;
  }

  const accountId = opts.accountId ?? await accountForStatement(parsed);
  const rules = await db.merchantRules.toArray();
  const fresh: Transaction[] = [];

  for (const row of parsed.rows) {
    if (await isDuplicate(row)) { out.duplicates++; continue; }

    const key = merchantRuleKey(row.merchantRaw);
    const rule = key
      ? rules.filter((r) => r.key && (key.includes(r.key) || r.key.includes(key)))
              .sort((a, b) => b.key.length - a.key.length)[0]
      : undefined;

    const merchantName = normalizeMerchant(row.merchantRaw, rule?.displayName);
    const classification = classify({
      merchantName,
      amount: row.amount,
      type: row.type,
      rawContent: row.rawContent,
      userRuleSlug: rule?.categorySlug,
    });

    // A shaky direction caps the row's overall confidence: the category can be
    // certain while the debit-vs-credit call is a guess, and it's the guess
    // that needs a human.
    const confidence = Math.min(classification.confidence, row.directionConfidence);

    const transaction: Transaction = {
      id: crypto.randomUUID(),
      amount: row.amount,
      type: row.type,
      merchantRaw: row.merchantRaw,
      merchantName: merchantName || row.merchantRaw,
      categorySlug: classification.categorySlug,
      date: row.date,
      source: "pdf",
      confidence,
      isConfirmed: confidence >= 0.85,
      isRecurring: false,
      tags: [],
      accountId,
      rawContent: row.rawContent,
      createdAt: Date.now(),
    };

    fresh.push(transaction);
    out.saved++;
    if (confidence < 0.85) out.needsReview++;
  }

  if (fresh.length) {
    await db.transactions.bulkPut(fresh);
    await recalculateBalances();
  }
  out.transactions = fresh;

  await recordAudit(
    fresh.length > 0 ? "saved" : "parsed",
    `PDF statement · ${parsed.detectedBank ?? "unknown bank"}`,
    `${out.saved} saved · ${out.duplicates} already present · ${out.needsReview} to review`,
  );

  return out;
}

/**
 * Exact-text match on any existing row, with no time window.
 *
 * A statement row is verbatim-stable across re-imports, so identical text is a
 * re-import rather than a genuine repeat purchase.
 */
async function isDuplicate(row: ParsedPDFRow): Promise<boolean> {
  const existing = await db.transactions.where("rawContent").equals(row.rawContent).toArray();
  return existing.some((t) => !t.isDeleted || t.source === "pdf");
}

/** Match the statement to an account by card last-4, then by bank name. */
async function accountForStatement(parsed: PDFParseResult): Promise<string | undefined> {
  const accounts = await db.accounts.toArray();
  if (parsed.accountLast4) {
    const byLast4 = accounts.find((a) => a.last4 === parsed.accountLast4);
    if (byLast4) return byLast4.id;
  }
  if (parsed.detectedBank) {
    const needle = parsed.detectedBank.toLowerCase();
    const candidates = accounts.filter((a) => a.bankName.toLowerCase().includes(needle));
    if (candidates.length === 1) return candidates[0]!.id;
  }
  return undefined;
}
