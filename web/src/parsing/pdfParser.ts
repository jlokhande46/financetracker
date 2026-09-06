import type { Paise, TransactionType } from "../domain/types";
import { parseAmountToPaise } from "./smsParser";

/**
 * Bank statement PDF parsing, ported from PDFStatementParser.swift.
 *
 * Pipeline: text extraction -> group lines into records -> bail if the table
 * came out column-scrambled -> parse each record -> infer direction.
 *
 * The Swift version accumulated several fixes that only surfaced against real
 * statements. They are all preserved here and pinned by tests:
 *   - records terminate at their closing amount, so the LAST transaction in a
 *     statement doesn't swallow the entire footer
 *   - the withdrawal/deposit column heuristic is gated to Federal Bank
 *   - amounts are comma-grouped only, never space-grouped
 */

export interface ParsedPDFRow {
  amount: Paise;
  type: TransactionType;
  merchantRaw: string;
  date: number;
  /** How confident we are about debit-vs-credit specifically. */
  directionConfidence: number;
  rawContent: string;
}

export interface PDFParseResult {
  rows: ParsedPDFRow[];
  detectedBank: string | null;
  accountLast4: string | null;
  dueDate: number | null;
  statementDate: number | null;
  totalDue: Paise | null;
  minimumDue: Paise | null;
  /** True when the layout came out column-first and we refused to guess. */
  columnScrambled: boolean;
  rawText: string;
}

// ── bank detection ───────────────────────────────────────────────────────────

export function detectBank(text: string): string | null {
  const l = text.toLowerCase();
  if (l.includes("hdfc bank")) return "HDFC";
  if (l.includes("icici bank")) return "ICICI";
  if (l.includes("state bank")) return "SBI";
  if (l.includes("axis bank")) return "Axis";
  if (l.includes("kotak")) return "Kotak";
  if (l.includes("yes bank")) return "Yes Bank";
  if (l.includes("idfc")) return "IDFC";
  if (l.includes("indusind")) return "IndusInd";
  if (l.includes("rbl")) return "RBL";
  if (l.includes("federal bank") || l.includes("federalbank")) return "Federal";
  return null;
}

// ── record grouping ──────────────────────────────────────────────────────────

const RECORD_START =
  /^(?:\d{1,2}[/-][A-Za-z0-9]{2,9}[/-]\d{2,4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{2,4})\b/;

/** A line ending in a decimal / comma-grouped amount, optionally Cr/Dr/C/D. */
const CLOSING_AMOUNT =
  /(?:\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+\.\d{2})\s*(?:[CD]|Cr|Dr|CR|DR)?\s*$/;

/**
 * Join a transaction's wrapped lines back into one record.
 *
 * A record starts at any line beginning with a date. It ENDS once we've
 * appended the line carrying its closing amount — without that terminator the
 * final transaction in a statement absorbs every footer line that follows,
 * which is how an ICICI row once picked up "payment received" from the
 * MAD-calculation boilerplate and got booked as a credit.
 *
 * Federal Bank is exempt: its savings rows can split
 * [withdrawal, deposit, balance] across separate lines, so closing at the
 * first amount would drop the rest.
 */
export function groupLinesIntoRecords(lines: string[], bank: string | null): string[] {
  const applyTerminator = bank !== "Federal";
  const records: string[] = [];
  let current = "";
  let closed = false;

  for (const line of lines) {
    if (RECORD_START.test(line)) {
      if (current) records.push(current);
      current = line;
      closed = applyTerminator && CLOSING_AMOUNT.test(line);
    } else if (current && !closed) {
      current += " " + line;
      if (applyTerminator && CLOSING_AMOUNT.test(line)) closed = true;
    }
  }
  if (current) records.push(current);
  return records;
}

/**
 * PDFKit-style extractors sometimes read a table column-first, producing
 * records with many dates and no amounts (the HDFC Savings symptom). We can't
 * recover row alignment from that, so it's better to report nothing than to
 * emit confidently wrong transactions.
 */
export function recordsAppearColumnScrambled(records: string[]): boolean {
  const dateRe = /\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{2,4}/g;
  const amountRe = /\d{1,3}(?:[,\s]\d{3})*\.\d{2}/g;
  let scrambled = 0, candidates = 0;
  for (const r of records.slice(0, 20)) {
    if (r.length <= 40) continue;
    candidates++;
    const dates = r.match(dateRe)?.length ?? 0;
    const amounts = r.match(amountRe)?.length ?? 0;
    if (dates >= 4 && amounts === 0) scrambled++;
  }
  // Need a few jumbled records to be confident — a single-transaction PDF
  // shouldn't trip this.
  return scrambled >= 3 && scrambled * 2 >= candidates;
}

// ── junk filtering ───────────────────────────────────────────────────────────

const JUNK = [
  "finance charge", "fin charge", "fin chg", "interest charge", "interest debit",
  "late payment", "late fee", "joining fee", "annual fee", "membership fee",
  "renewal fee", "service tax", "service charge", "convenience fee",
  "processing fee", "overlimit", "over limit", "cash advance fee",
  "fuel surcharge", "previous balance", "opening balance", "closing balance",
  "carry forward", "balance carried forward", "total amount due",
  "minimum amount due", "amount due", "available credit", "available limit",
  "credit limit", "payment due date", "statement date",
  " gst ", " igst ", " cgst ", " sgst ",
  // Statements embed the GST rate inline as "IGST-VPS...-RATE 18.0"; without
  // this the 18.0 reads as an ₹18 transaction.
  "igst-",
];

export function isJunkNarration(narration: string): boolean {
  const padded = ` ${narration.toLowerCase()} `;
  return JUNK.some((j) => padded.includes(j));
}

export function isValidNarration(narration: string): boolean {
  if (narration.length < 3) return false;
  return /[A-Za-z]{2,}/.test(narration);
}

// ── amounts ──────────────────────────────────────────────────────────────────

export interface AmountMatch {
  paise: Paise;
  index: number;
  length: number;
  cr: boolean;
  dr: boolean;
}

/**
 * Amounts are comma-grouped only, never space-grouped — otherwise a rewards
 * column rendered as "14 747.50" collapses into a single ₹14,747.50.
 * Lookarounds keep us from matching digits embedded in tokens like "S95818915".
 */
export function extractAmounts(text: string, allowWholeNumbers = false): AmountMatch[] {
  const body = allowWholeNumbers
    ? String.raw`(?:\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?)|(?:\d{1,7}\.\d{1,2})|(?:\d{1,7})`
    : String.raw`(?:\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?)|(?:\d{1,5}\.\d{1,2})`;
  const re = new RegExp(
    String.raw`(?<![A-Za-z0-9.])(${body})(?![A-Za-z0-9./-])\s*(Cr|Dr|CR|DR)?`,
    "g",
  );
  const out: AmountMatch[] = [];
  for (const m of text.matchAll(re)) {
    const paise = parseAmountToPaise(m[1]!);
    if (paise === null) continue;
    const suffix = (m[2] ?? "").toUpperCase();
    out.push({
      paise,
      index: m.index!,
      length: m[0].length,
      cr: suffix === "CR",
      dr: suffix === "DR",
    });
  }
  return out;
}

// ── dates ────────────────────────────────────────────────────────────────────

const MONTHS: Record<string, number> = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
  jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
};
const yr = (y: number) => (y < 100 ? 2000 + y : y);

/** Finds the leading date and returns where it (plus any trailing time / value-date) ends. */
export function extractDate(line: string): { date: number; end: number } | null {
  const patterns: Array<{ re: RegExp; build: (m: RegExpMatchArray) => number | null }> = [
    { re: /\d{2}[/-]\d{2}[/-]\d{4}/, build: (m) => numeric(m[0]) },
    { re: /\d{2}[/-]\d{2}[/-]\d{2}/, build: (m) => numeric(m[0]) },
    { re: /\d{2}\s+[A-Za-z]{3}\s+\d{4}/, build: (m) => named(m[0]) },
    { re: /\d{2}\s+[A-Za-z]{3}\s+\d{2}/, build: (m) => named(m[0]) },
    { re: /\d{2}[/-][A-Za-z]{3}[/-]\d{4}/, build: (m) => named(m[0]) },
    { re: /\d{2}[/-][A-Za-z]{3}[/-]\d{2}/, build: (m) => named(m[0]) },
  ];

  for (const { re, build } of patterns) {
    const m = line.match(re);
    if (!m || m.index === undefined) continue;
    const date = build(m);
    if (date === null) continue;

    let end = m.index + m[0].length;
    // Consume a trailing time ("12/05/2026|10:15", HDFC CC).
    const time = line.slice(end).match(/^[\s|]*\d{1,2}:\d{2}(?::\d{2})?/);
    if (time) end += time[0].length;
    // Consume a trailing value-date (Federal shows txn-date then value-date).
    const valueDate = line.slice(end).match(/^\s*\d{1,2}[/-][A-Za-z0-9]{2,9}[/-]\d{2,4}\b/);
    if (valueDate) end += valueDate[0].length;
    return { date, end };
  }
  return null;

  function numeric(s: string): number | null {
    const m = s.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/);
    if (!m) return null;
    const mo = Number(m[2]);
    if (mo < 1 || mo > 12) return null;
    return new Date(yr(Number(m[3])), mo - 1, Number(m[1])).getTime();
  }
  function named(s: string): number | null {
    const m = s.match(/^(\d{1,2})[\s/-]([A-Za-z]{3})[\s/-](\d{2,4})$/);
    if (!m) return null;
    const mo = MONTHS[m[2]!.toLowerCase()];
    if (mo === undefined) return null;
    return new Date(yr(Number(m[3])), mo, Number(m[1])).getTime();
  }
}

// ── direction inference ──────────────────────────────────────────────────────

const CC_PAYMENT_KEYWORDS = [
  "cc payment", "card payment", "bppy cc", "bppy/", "bppy ",
  "payment received", "payment thank you", "payment - thank you",
  "auto debit-cc payment", "neft cr", "imps cr",
  "credit card payment", "bill payment received",
];

const STRICT_CREDIT_KEYWORDS = [
  "salary credit", "salary credited", "refund", "cashback", "reversal",
  "interest credit", "imps in/", "neft in/", "rtgs in/", "by transfer-",
  "credited by",
];

export interface Inference {
  amount: Paise;
  type: TransactionType;
  directionConfidence: number;
  step: string;
}

const firstNonZero = (a: AmountMatch[]) => a.find((x) => x.paise > 0);

/**
 * Decide amount + direction for a statement row. Ordered by how trustworthy
 * each signal is; the keyword checks look only at the narration (text before
 * the first amount) so footer boilerplate can't flip a row's direction.
 */
export function inferAmountAndType(
  amounts: AmountMatch[],
  line: string,
  bank: string | null,
): Inference {
  if (amounts.length === 0) {
    return { amount: 0, type: "debit", directionConfidence: 0, step: "empty" };
  }

  // 1. Explicit Cr/Dr on the amount. Skipped at 4+ amounts because on a
  //    4-column savings row the suffix belongs to the running balance.
  if (amounts.length <= 3) {
    const cr = amounts.find((a) => a.cr);
    if (cr) return { amount: cr.paise, type: "credit", directionConfidence: 1, step: "1-CR" };
    const dr = amounts.find((a) => a.dr);
    if (dr) return { amount: dr.paise, type: "debit", directionConfidence: 1, step: "1-DR" };
  }

  // 2. SBI: trailing C / D marks the direction.
  const trimmed = line.trim();
  const nonBalance = amounts.slice(0, -1);
  if (/\sC$/.test(trimmed)) {
    const chosen = firstNonZero(nonBalance) ?? amounts[0]!;
    return { amount: chosen.paise, type: "credit", directionConfidence: 1, step: "2-C" };
  }
  if (/\sD$/.test(trimmed)) {
    const chosen = firstNonZero(nonBalance) ?? amounts[0]!;
    return { amount: chosen.paise, type: "debit", directionConfidence: 1, step: "2-D" };
  }

  // 3. HDFC CC: a '+' immediately before/after the amount means credit.
  const first = amounts[0]!;
  const before = line.slice(0, first.index);
  if (/\+\s*(?:₹|Rs\.?|INR)?\s*$/.test(before)) {
    return { amount: first.paise, type: "credit", directionConfidence: 1, step: "3-plusBefore" };
  }
  const after = line.slice(first.index + first.length);
  if (/^\s*(?:₹|Rs\.?|INR)?\s*\+/.test(after)) {
    return { amount: first.paise, type: "credit", directionConfidence: 1, step: "3-plusAfter" };
  }

  // 4. Federal savings columns [withdrawal | deposit | balance].
  //    Bank-gated: a credit-card statement has no such columns, and ICICI's
  //    reward-points column would otherwise read as a deposit — that's the bug
  //    that booked a ₹747.50 BookMyShow debit as a ₹14 credit.
  if (bank === "Federal" && nonBalance.length >= 2) {
    const nonZero = nonBalance.map((a, i) => ({ a, i })).filter((x) => x.a.paise > 0);
    if (nonZero.length === 1) {
      const { a, i } = nonZero[0]!;
      return {
        amount: a.paise,
        type: i === 0 ? "debit" : "credit",
        directionConfidence: 0.9,
        step: "4-col",
      };
    }
  }

  // 5. Keywords — narration only, so footer text can't reach them.
  const narration = line.slice(0, first.index).toLowerCase();
  const ccHit = CC_PAYMENT_KEYWORDS.find((k) => narration.includes(k));
  if (ccHit) {
    const chosen = firstNonZero(nonBalance) ?? amounts[amounts.length - 1]!;
    return { amount: chosen.paise, type: "credit", directionConfidence: 1, step: `5-cc[${ccHit}]` };
  }
  const strictHit = STRICT_CREDIT_KEYWORDS.find((k) => narration.includes(k));
  if (strictHit) {
    const chosen = firstNonZero(nonBalance) ?? amounts[amounts.length - 1]!;
    return { amount: chosen.paise, type: "credit", directionConfidence: 0.8, step: `5-strict[${strictHit}]` };
  }

  // 6. Default to debit, low confidence so the row lands in Review.
  //    Prefer the rightmost amount: on ICICI Sapphiro the earlier columns are
  //    reward points, not money.
  const last = amounts[amounts.length - 1]!;
  const chosen = last.paise > 0 ? last : (firstNonZero(nonBalance) ?? last);
  return { amount: chosen.paise, type: "debit", directionConfidence: 0.4, step: "6-default" };
}

// ── HDFC credit-card rows ────────────────────────────────────────────────────

/**
 * HDFC CC rows have their own shape: `DATE| TIME DESC [+ N] [+] C AMOUNT`.
 * The literal "C" is HDFC's currency marker, and "+ N" is a rewards count
 * (not money) — both confuse the generic amount/direction logic, so this
 * runs first.
 */
export function parseHDFCCreditCardRow(line: string): ParsedPDFRow | null {
  const m = line.match(
    /^(\d{1,2}\/\d{1,2}\/\d{4})\|\s*(\d{1,2}:\d{2})\s+(.+?)\s+(?:\+\s+\d+\s+)?(\+\s+)?C\s*([\d,]+(?:\.\d{1,2})?)\b/,
  );
  if (!m) return null;

  const [, dateStr, timeStr, rawNarration, plusBeforeC, amountStr] = m;
  const dm = dateStr!.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!dm) return null;
  const tm = timeStr!.match(/^(\d{1,2}):(\d{2})$/);
  const date = new Date(
    Number(dm[3]), Number(dm[2]) - 1, Number(dm[1]),
    Number(tm?.[1] ?? 0), Number(tm?.[2] ?? 0),
  ).getTime();

  const amount = parseAmountToPaise(amountStr!);
  if (amount === null || amount <= 0) return null;

  const narration = rawNarration!.trim().replace(/^[|*:\-\s]+|[|*:\-\s]+$/g, "");
  if (!isValidNarration(narration) || isJunkNarration(narration)) return null;

  // A bare '+' before the C means credit; '+ N' is a rewards count, so debit.
  return {
    amount,
    type: plusBeforeC ? "credit" : "debit",
    merchantRaw: narration,
    date,
    directionConfidence: 1,
    rawContent: line,
  };
}

// ── per-record parsing ───────────────────────────────────────────────────────

export function parseTransactionRecord(line: string, bank: string | null): ParsedPDFRow | null {
  const hdfc = parseHDFCCreditCardRow(line);
  if (hdfc) return hdfc;

  const dateInfo = extractDate(line);
  if (!dateInfo) return null;
  if (dateInfo.end >= line.length) return null;

  // Look for amounts only AFTER the date. That's what makes it safe to accept
  // bare whole numbers (Federal's "0 25000 90672.62") without reading the
  // year out of the leading date as an amount.
  const postDate = line.slice(dateInfo.end);
  const local = extractAmounts(postDate, true);
  if (local.length === 0) return null;
  const amounts = local.map((a) => ({ ...a, index: a.index + dateInfo.end }));

  const firstIdx = amounts[0]!.index;
  if (firstIdx <= dateInfo.end) return null;

  const narration = line
    .slice(dateInfo.end, firstIdx)
    .trim()
    .replace(/^[|*:\-\s]+|[|*:\-\s]+$/g, "");
  if (!narration || !isValidNarration(narration) || isJunkNarration(narration)) return null;

  const inferred = inferAmountAndType(amounts, line, bank);
  if (inferred.amount <= 0) return null;

  return {
    amount: inferred.amount,
    type: inferred.type,
    merchantRaw: narration,
    date: dateInfo.date,
    directionConfidence: inferred.directionConfidence,
    rawContent: line,
  };
}

// ── statement-level fields ───────────────────────────────────────────────────

function labelledAmount(text: string, label: string): Paise | null {
  const re = new RegExp(`${label}\\s*[:\\-]?\\s*(?:Rs\\.?|INR)?\\s*([\\d,]+(?:\\.\\d{2})?)`, "is");
  const m = text.match(re);
  return m ? parseAmountToPaise(m[1]!) : null;
}

function labelledDate(text: string, label: string): number | null {
  const re = new RegExp(
    `${label}\\s*[:\\-]?\\s*(\\d{1,2}[\\s/-][A-Za-z]{3,9}[\\s/-]\\d{2,4}|\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}|[A-Za-z]{3,9}\\s+\\d{1,2},\\s*\\d{4})`,
    "is",
  );
  const m = text.match(re);
  if (!m) return null;
  const raw = m[1]!.trim();

  let d = extractDate(raw)?.date ?? null;
  if (d === null) {
    // "June 2, 2026" (ICICI style)
    const lm = raw.match(/^([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{4})$/);
    if (lm) {
      const mo = MONTHS[lm[1]!.slice(0, 3).toLowerCase()];
      if (mo !== undefined) d = new Date(Number(lm[3]), mo, Number(lm[2])).getTime();
    }
  }
  if (d === null) return null;

  // Discard implausible parses rather than showing "due 943 days ago", and try
  // shifting a mis-parsed year onto the current one.
  const diffDays = (d - Date.now()) / 86_400_000;
  if (diffDays >= -60 && diffDays <= 60) return d;
  const shifted = new Date(d);
  shifted.setFullYear(new Date().getFullYear());
  const shiftedDiff = (shifted.getTime() - Date.now()) / 86_400_000;
  if (shiftedDiff >= -60 && shiftedDiff <= 60) return shifted.getTime();
  if (shiftedDiff < -60) {
    shifted.setFullYear(shifted.getFullYear() + 1);
    return shifted.getTime();
  }
  return null;
}

export function extractAccountLast4(text: string): string | null {
  const patterns = [
    /\d{4}[xX]{6,}(\d{4})\b/,                               // ICICI 3747XXXXXXXX2001
    /X{4}\s*X{4}\s*X{4}\s*(\d{4})\b/,                       // XXXX XXXX XXXX 6624
    /(?:card|account)\s+ending\s+(?:in\s+)?(\d{4})\b/i,
    /card\s+(?:no\.?\s+)?ending\s+(?:in\s+)?(\d{4})\b/i,
    /card\s+(?:no\.?|number)?\s*\d{0,4}[xX]+(\d{4})\b/i,
    /a\/?c\s*[*xX]+(\d{4})\b/i,
    /account\s+(?:no\.?\s+|number\s+)?(?:ending\s+(?:in\s+)?)?(?:[xX*]+)?(\d{4})\b/i,
    /ending\s+(?:in\s+)?(?:[xX]+\s*)?(\d{4})\b/i,
    /card\s+(\d{4})\b(?!\s*\d)/i,
  ];
  for (const re of patterns) {
    const m = text.match(re);
    if (m) return m[1]!;
  }
  return null;
}

/** Parse already-extracted statement text. Kept separate from PDF I/O so it's testable. */
export function parseStatementText(fullText: string): PDFParseResult {
  const bank = detectBank(fullText);
  const lines = fullText
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);

  const records = groupLinesIntoRecords(lines, bank);
  const columnScrambled = recordsAppearColumnScrambled(records);

  const rows: ParsedPDFRow[] = [];
  if (!columnScrambled) {
    for (const record of records) {
      const row = parseTransactionRecord(record, bank);
      if (row) rows.push(row);
    }
  }

  return {
    rows,
    detectedBank: bank,
    accountLast4: extractAccountLast4(fullText),
    dueDate: labelledDate(fullText, "(?:payment\\s+)?due\\s+date"),
    statementDate: labelledDate(fullText, "statement\\s+date"),
    totalDue: labelledAmount(fullText, "(?:total\\s+amount\\s+due|total\\s+due|amount\\s+due)"),
    minimumDue: labelledAmount(fullText, "(?:minimum\\s+amount\\s+due|minimum\\s+due|min(?:imum)?\\s+due)"),
    columnScrambled,
    rawText: fullText,
  };
}

/** Browser-only: pull text out of a PDF File, then parse it. */
export async function parsePDFFile(file: File): Promise<PDFParseResult> {
  const pdfjs = await import("pdfjs-dist");
  // Vite resolves this to a hashed asset URL at build time.
  const workerUrl = (await import("pdfjs-dist/build/pdf.worker.mjs?url")).default;
  pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

  const buffer = await file.arrayBuffer();
  const doc = await pdfjs.getDocument({ data: buffer }).promise;

  let text = "";
  for (let i = 1; i <= doc.numPages; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    // Reconstruct lines from positioned text items: same y == same visual row.
    const byLine = new Map<number, string[]>();
    for (const item of content.items) {
      if (!("str" in item)) continue;
      const y = Math.round((item.transform[5] as number) * 2) / 2;
      if (!byLine.has(y)) byLine.set(y, []);
      byLine.get(y)!.push(item.str);
    }
    const ordered = [...byLine.entries()].sort((a, b) => b[0] - a[0]);
    text += ordered.map(([, parts]) => parts.join(" ").trim()).join("\n") + "\n";
  }
  return parseStatementText(text);
}
