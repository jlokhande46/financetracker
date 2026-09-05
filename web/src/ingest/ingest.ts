import { parseSMS } from "../parsing/smsParser";
import { normalizeMerchant, merchantRuleKey } from "../categorization/merchantNormalizer";
import { classify } from "../categorization/classifier";
import { db, recordAudit } from "../db/db";
import type { Account, Transaction } from "../domain/types";

/** Window in which an identical rawContent is treated as a duplicate. */
const DEDUP_WINDOW_MS = 2 * 60 * 1000;

export interface IngestResult {
  status: "saved" | "duplicate" | "unparseable";
  transaction?: Transaction;
}

/**
 * The single path every captured SMS flows through:
 *   dedup -> parse -> normalise (honouring learned rules) -> classify -> store.
 *
 * `receivedAt` is when the Shortcut actually fired, not when the app opened.
 * Most Indian bank SMS carry a date but no time, so a same-day batch would
 * otherwise collapse onto midnight and lose its ordering — we graft the receipt
 * time-of-day onto the parsed date to preserve sequence.
 */
export async function ingestSMS(
  rawText: string,
  receivedAt: number = Date.now(),
): Promise<IngestResult> {
  const text = rawText.trim();
  if (!text) return { status: "unparseable" };

  const recent = await db.transactions
    .where("rawContent")
    .equals(text)
    .toArray();
  if (recent.some((t) => Math.abs(receivedAt - t.createdAt) < DEDUP_WINDOW_MS)) {
    await recordAudit("dedupSkipped", text, "Identical SMS already saved in the last 2 minutes.");
    return { status: "duplicate" };
  }

  const parsed = parseSMS(text);
  if (!parsed) {
    await recordAudit("parseFailed", text, "No known bank format matched.");
    return { status: "unparseable" };
  }
  await recordAudit("parsed", text, `matched by ${parsed.matchedBy}`);

  const rule = await lookupMerchantRule(parsed.merchantRaw);
  const merchantName = normalizeMerchant(parsed.merchantRaw, rule?.displayName);

  const classification = classify({
    merchantName,
    amount: parsed.amount,
    type: parsed.type,
    rawContent: text,
    userRuleSlug: rule?.categorySlug,
  });

  const transaction: Transaction = {
    id: crypto.randomUUID(),
    amount: parsed.amount,
    type: parsed.type,
    merchantRaw: parsed.merchantRaw,
    merchantName: merchantName || parsed.merchantRaw,
    categorySlug: classification.categorySlug,
    date: resolveDate(parsed.date, receivedAt),
    source: "sms",
    confidence: classification.confidence,
    // Auto-captured rows are confirmed; low confidence still surfaces them in
    // Review via needsReview, so nothing silently hides.
    isConfirmed: classification.confidence >= 0.85,
    isRecurring: false,
    tags: [],
    accountId: await linkAccount(parsed.last4, text),
    upiRef: parsed.upiRef,
    bankRef: parsed.bankRef,
    rawContent: text,
    createdAt: receivedAt,
  };

  await db.transactions.put(transaction);
  await recordAudit(
    "saved",
    text,
    `${parsed.type === "credit" ? "+" : "-"}${parsed.amount / 100} ${transaction.merchantName}`,
  );
  return { status: "saved", transaction };
}

/**
 * Most bank SMS give a date with no time. Keep the parsed calendar day but
 * take the time-of-day from when the message arrived, so two SMS on the same
 * day still sort in the order they happened.
 */
function resolveDate(parsedDate: number | undefined, receivedAt: number): number {
  if (parsedDate === undefined) return receivedAt;
  const d = new Date(parsedDate);
  const hasTime = d.getHours() !== 0 || d.getMinutes() !== 0 || d.getSeconds() !== 0;
  if (hasTime) return parsedDate;
  const r = new Date(receivedAt);
  d.setHours(r.getHours(), r.getMinutes(), r.getSeconds(), 0);
  return d.getTime();
}

async function lookupMerchantRule(merchantRaw: string) {
  const key = merchantRuleKey(merchantRaw);
  if (!key) return undefined;
  const all = await db.merchantRules.toArray();
  // Substring match in either direction; longest key wins, matching the Swift
  // MerchantRuleStore behaviour.
  const matches = all.filter(
    (r) => r.key && (key.includes(r.key) || r.key.includes(key)),
  );
  return matches.sort((a, b) => b.key.length - a.key.length)[0];
}

/** last4 -> bank keyword -> single account of that bank. */
async function linkAccount(last4: string | undefined, rawText: string): Promise<string | undefined> {
  const accounts = await db.accounts.toArray();
  if (accounts.length === 0) return undefined;

  if (last4) {
    const byLast4 = accounts.find((a) => a.last4 === last4);
    if (byLast4) return byLast4.id;
  }

  const lower = rawText.toLowerCase();
  const bankNeedles: Array<[needle: string, bankSubstring: string]> = [
    ["federal bank", "federal"], ["hdfc bank", "hdfc"],
    ["icici bank", "icici"], ["sbi", "sbi"], ["axis bank", "axis"],
  ];
  for (const [needle, bank] of bankNeedles) {
    if (!lower.includes(needle)) continue;
    const candidates = accounts.filter((a) => a.bankName.toLowerCase().includes(bank));
    if (candidates.length === 1) return candidates[0]!.id;
  }
  return undefined;
}

/** Recompute derived balances: openingBalance combined with linked transactions. */
export async function recalculateBalances(): Promise<void> {
  const [accounts, transactions] = await Promise.all([
    db.accounts.toArray(),
    db.transactions.toArray(),
  ]);

  const net = new Map<string, { credits: number; debits: number }>();
  for (const t of transactions) {
    if (!t.accountId || t.isDeleted) continue;
    const entry = net.get(t.accountId) ?? { credits: 0, debits: 0 };
    if (t.type === "credit") entry.credits += t.amount;
    else entry.debits += t.amount;
    net.set(t.accountId, entry);
  }

  const updated: Account[] = accounts.map((a) => {
    const n = net.get(a.id) ?? { credits: 0, debits: 0 };
    // Cards track OUTSTANDING, so purchases raise it and payments reduce it.
    // Deposit accounts move the other way.
    const balance = a.type === "credit"
      ? a.openingBalance + n.debits - n.credits
      : a.openingBalance + n.credits - n.debits;
    return { ...a, balance };
  });
  await db.accounts.bulkPut(updated);
}
