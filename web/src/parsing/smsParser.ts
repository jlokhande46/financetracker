import type { Paise, TransactionType } from "../domain/types";

export interface ParsedSMS {
  amount: Paise;
  type: TransactionType;
  merchantRaw: string;
  last4?: string;
  /** epoch ms, when the SMS carried a parseable date */
  date?: number;
  upiRef?: string;
  bankRef?: string;
  rawText: string;
  /** Which parser matched — useful in the audit log. */
  matchedBy: string;
}

/**
 * Bank-specific SMS parsers, ported from Infrastructure/Parsing/SMSParser.swift.
 * Each pattern is tuned to a real SMS observed from that bank/card, and they run
 * in order of precision before the generic fallbacks — a generic "Rs.X debited"
 * rule would otherwise swallow messages a specific parser reads far better.
 *
 * Swift's `(?is)` inline flags become the `i` + `s` flags here.
 */

// ── amount helpers ───────────────────────────────────────────────────────────

/** "1,234.50" -> 123450 paise. Integer math only; no float rounding drift. */
export function parseAmountToPaise(raw: string): Paise | null {
  const cleaned = raw.replace(/,/g, "").trim();
  if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return null;
  const [whole = "0", frac = ""] = cleaned.split(".");
  const paiseFrac = (frac + "00").slice(0, 2);
  return Number(whole) * 100 + Number(paiseFrac);
}

// ── date helpers ─────────────────────────────────────────────────────────────

const MONTHS: Record<string, number> = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
  jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
};

function yearFrom2Digit(y: number): number {
  return y < 100 ? 2000 + y : y;
}

/** dd/MM/yy, dd/MM/yyyy, dd-MM-yy, dd-MM-yyyy */
function parseNumericDate(s: string): number | undefined {
  const m = s.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/);
  if (!m) return undefined;
  const d = Number(m[1]), mo = Number(m[2]), y = yearFrom2Digit(Number(m[3]));
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return undefined;
  return new Date(y, mo - 1, d).getTime();
}

/** dd-MMM-yy / dd-MMM-yyyy (ICICI) */
function parseMonthNameDate(s: string): number | undefined {
  const m = s.match(/^(\d{1,2})[-/\s]([A-Za-z]{3,9})[-/\s](\d{2,4})$/);
  if (!m) return undefined;
  const mo = MONTHS[m[2]!.slice(0, 3).toLowerCase()];
  if (mo === undefined) return undefined;
  return new Date(yearFrom2Digit(Number(m[3])), mo, Number(m[1])).getTime();
}

/** "Month DD, YYYY" (Federal Bank) */
function parseLongDate(s: string): number | undefined {
  const m = s.match(/^([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{4})$/);
  if (!m) return undefined;
  const mo = MONTHS[m[1]!.slice(0, 3).toLowerCase()];
  if (mo === undefined) return undefined;
  return new Date(Number(m[3]), mo, Number(m[2])).getTime();
}

/** "yyyy-MM-dd" optionally followed by ":HH:mm:ss" (HDFC Regalia) */
function parseISOish(s: string): number | undefined {
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})(?::(\d{2}):(\d{2}):(\d{2}))?$/);
  if (!m) return undefined;
  return new Date(
    Number(m[1]), Number(m[2]) - 1, Number(m[3]),
    Number(m[4] ?? 0), Number(m[5] ?? 0), Number(m[6] ?? 0),
  ).getTime();
}

/** "dd-MM-yyyy HH:mm:ss" (Federal Bank sent) */
function parseDateTime(s: string): number | undefined {
  const m = s.match(/^(\d{1,2})-(\d{1,2})-(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/);
  if (!m) return undefined;
  return new Date(
    Number(m[3]), Number(m[2]) - 1, Number(m[1]),
    Number(m[4]), Number(m[5]), Number(m[6]),
  ).getTime();
}

/**
 * When the SMS gives only DD-MM with no year, pick the nearest year so a Dec-31
 * transaction arriving on Jan-1 isn't filed twelve months into the future.
 */
function fillCurrentYear(ddMM: string, now = new Date()): number | undefined {
  const m = ddMM.match(/^(\d{1,2})-(\d{1,2})$/);
  if (!m) return undefined;
  const thisYear = new Date(now.getFullYear(), Number(m[2]) - 1, Number(m[1]));
  const daysAhead = (thisYear.getTime() - now.getTime()) / 86_400_000;
  if (daysAhead > 30) {
    return new Date(now.getFullYear() - 1, Number(m[2]) - 1, Number(m[1])).getTime();
  }
  return thisYear.getTime();
}

const clean = (s: string) => s.replace(/\s{2,}/g, " ").trim();

// ── bank-specific parsers ────────────────────────────────────────────────────

type Parser = (msg: string) => ParsedSMS | null;

/** HDFC Savings — "Sent Rs.X From HDFC Bank A/C *XXXX To MERCHANT On DD/MM/YY Ref XXX" */
const hdfcSavingsSent: Parser = (msg) => {
  const m = msg.match(
    /Sent\s+Rs\.?\s*([\d,]+(?:\.\d+)?)\s*From\s+HDFC\s+Bank\s+A\/?C\s+\*?(\d{4})\s*To\s+([^\n]+?)\s*On\s+(\d{2}\/\d{2}\/\d{2,4})\s*Ref\s+(\d+)/is,
  );
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  return {
    amount, type: "debit", merchantRaw: clean(m[3]!), last4: m[2],
    date: parseNumericDate(m[4]!), upiRef: m[5], rawText: msg,
    matchedBy: "hdfc-savings-sent",
  };
};

/** HDFC Savings credit — "Rs.X credited to HDFC Bank A/c XXNNNN on DD-MM-YY from VPA xxx" */
const hdfcSavingsCredited: Parser = (msg) => {
  const m = msg.match(
    /(?:Credit\s+Alert!?\s*)?Rs\.?\s*([\d,]+(?:\.\d+)?)\s+credited\s+to\s+HDFC\s+Bank\s+A\/?c\s+X+(\d{4})\s+on\s+(\d{2}-\d{2}-\d{2,4})\s+from\s+(?:VPA\s+)?(\S+)(?:\s*\(UPI\s+(\d+)\))?/is,
  );
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  return {
    amount, type: "credit", merchantRaw: clean(m[4]!), last4: m[2],
    date: parseNumericDate(m[3]!), upiRef: m[5] || undefined, rawText: msg,
    matchedBy: "hdfc-savings-credited",
  };
};

/** Federal Bank received — "received INR X in Account XXXXX ... sent by NAME on Month DD, YYYY" */
const federalReceived: Parser = (msg) => {
  const m = msg.match(
    /received\s+INR\s+([\d,]+(?:\.\d+)?)\s+in\s+(?:your\s+)?Account\s+X+(\d{4})[\s\S]*?sent\s+by\s+([^\n.]+?)\s+on\s+([A-Za-z]+\s+\d{1,2},\s*\d{4})/is,
  );
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  return {
    amount, type: "credit", merchantRaw: clean(m[3]!), last4: m[2],
    date: parseLongDate(m[4]!.trim()), rawText: msg,
    matchedBy: "federal-received",
  };
};

/** Federal Bank sent — "Rs X sent via UPI on DD-MM-YYYY at HH:MM:SS to MERCHANT.Ref:NNN -Federal Bank" */
const federalSent: Parser = (msg) => {
  const m = msg.match(
    /Rs\.?\s*([\d,]+(?:\.\d+)?)\s+sent\s+via\s+UPI\s+on\s+(\d{2}-\d{2}-\d{4})\s+at\s+(\d{2}:\d{2}:\d{2})\s+to\s+([^.\n]+?)\s*\.\s*Ref:?\s*(\d+)[\s\S]*?Federal\s*Bank/is,
  );
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  // Compose datetime so we keep the time instead of defaulting to midnight.
  const date = parseDateTime(`${m[2]} ${m[3]}`) ?? parseNumericDate(m[2]!);
  return {
    amount, type: "debit", merchantRaw: clean(m[4]!),
    date, upiRef: m[5], rawText: msg, matchedBy: "federal-sent",
  };
};

/** HDFC CC (Tata Neu Rupay UPI) — "Txn Rs.X On HDFC Bank Card XXXX At MERCHANT by UPI XXX On DD-MM" */
const hdfcCardTxn: Parser = (msg) => {
  const m = msg.match(
    /Txn\s+Rs\.?\s*([\d,]+(?:\.\d+)?)\s*On\s+HDFC\s+Bank\s+Card\s+(\d{4})\s*At\s+([^\n]+?)\s*by\s+UPI\s+(\d+)\s*On\s+(\d{2}-\d{2}(?:-\d{2,4})?)/is,
  );
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  const raw = m[5]!;
  // Only fill the year for the short DD-MM form; a full DD-MM-YYYY that failed
  // to parse should NOT be silently coerced to the current year.
  const date = parseNumericDate(raw) ?? (raw.length <= 5 ? fillCurrentYear(raw) : undefined);
  return {
    amount, type: "debit", merchantRaw: clean(m[3]!), last4: m[2],
    date, upiRef: m[4], rawText: msg, matchedBy: "hdfc-card-txn",
  };
};

/** HDFC CC (Regalia Gold) — "Spent Rs.X On HDFC Bank Card XXXX At MERCHANT On YYYY-MM-DD:HH:MM:SS" */
const hdfcCardSpent: Parser = (msg) => {
  const m = msg.match(
    /Spent\s+Rs\.?\s*([\d,]+(?:\.\d+)?)\s*On\s+HDFC\s+Bank\s+Card\s+(\d{4})\s*At\s+([^\n]+?)\s*On\s+(\d{4}-\d{2}-\d{2}(?::\d{2}:\d{2}:\d{2})?)/is,
  );
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  return {
    amount, type: "debit", merchantRaw: clean(m[3]!), last4: m[2],
    date: parseISOish(m[4]!), rawText: msg, matchedBy: "hdfc-card-spent",
  };
};

/** ICICI Sapphiro — "INR X spent using ICICI Bank Card XX2000 on DD-Mon-YY on MERCHANT" */
const iciciCard: Parser = (msg) => {
  const m = msg.match(
    /INR\s+([\d,]+(?:\.\d+)?)\s+spent\s+using\s+ICICI\s+Bank\s+Card\s+X+(\d{4})\s+on\s+(\d{2}-[A-Za-z]{3}-\d{2,4})\s+on\s+([^.]+?)\s*\.\s*(?:Avl\s+Limit)?/is,
  );
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  return {
    amount, type: "debit", merchantRaw: clean(m[4]!), last4: m[2],
    date: parseMonthNameDate(m[3]!), rawText: msg, matchedBy: "icici-card",
  };
};

/** SBI CC — "Rs.X spent on your SBI Credit Card ending XXXX at MERCHANT on DD/MM/YY" */
const sbiCard: Parser = (msg) => {
  const m = msg.match(
    /Rs\.?\s*([\d,]+(?:\.\d+)?)\s+spent\s+on\s+your\s+SBI\s+Credit\s+Card\s+ending\s+(\d{4})\s+at\s+([^\n]+?)\s+on\s+(\d{2}\/\d{2}\/\d{2,4})/is,
  );
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  return {
    amount, type: "debit", merchantRaw: clean(m[3]!), last4: m[2],
    date: parseNumericDate(m[4]!), rawText: msg, matchedBy: "sbi-card",
  };
};

// ── generic fallbacks ────────────────────────────────────────────────────────

/** Best-effort merchant when only an amount could be matched. */
function fallbackMerchant(msg: string): string {
  const patterns = [
    /(?:to|at|for|from)\s+(?:VPA\s+)?([A-Za-z0-9@._\-\s]+?)(?:\s+on|\s+Ref|\s+UPI|\.|\n|$)/i,
    /Info:\s*([A-Z0-9\s\-_]+?)(?:\s*Ref|$)/i,
  ];
  for (const p of patterns) {
    const m = msg.match(p);
    const candidate = m?.[1]?.trim();
    if (candidate && candidate.length > 2) return candidate;
  }
  return "";
}

function genericFor(bankNeedles: string[], label: string): Parser {
  return (msg) => {
    const lower = msg.toLowerCase();
    if (!bankNeedles.some((n) => lower.includes(n))) return null;
    const debit = msg.match(/(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?(?:has been\s+)?(?:debited|spent|charged)/i);
    if (debit) {
      const amount = parseAmountToPaise(debit[1]!);
      if (amount !== null) {
        return { amount, type: "debit", merchantRaw: fallbackMerchant(msg), rawText: msg, matchedBy: label };
      }
    }
    const credit = msg.match(/(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?(?:has been\s+)?credited/i);
    if (credit) {
      const amount = parseAmountToPaise(credit[1]!);
      if (amount !== null) {
        return { amount, type: "credit", merchantRaw: fallbackMerchant(msg), rawText: msg, matchedBy: label };
      }
    }
    return null;
  };
}

const upiGeneric: Parser = (msg) => {
  const lower = msg.toLowerCase();
  if (!["upi", "gpay", "phonepe", "paytm"].some((n) => lower.includes(n))) return null;
  const patterns: Array<[RegExp, TransactionType]> = [
    [/(?:payment|sent)\s+of\s+(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+to\s+([^\n.]+?)(?:\s+via\s+UPI|\s+UPI|\.)/i, "debit"],
    [/(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:paid|sent)\s+(?:to\s+)?([^\n.]+?)(?:\s+via|\s+using|\s+through|\s+UPI|\.)/i, "debit"],
    [/(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+received\s+from\s+([^\n.]+?)(?:\s+via|\s+using|\s+UPI|\.)/i, "credit"],
  ];
  for (const [re, type] of patterns) {
    const m = msg.match(re);
    if (!m) continue;
    const amount = parseAmountToPaise(m[1]!);
    if (amount === null) continue;
    return { amount, type, merchantRaw: clean(m[2]!), rawText: msg, matchedBy: "upi-generic" };
  }
  return null;
};

const genericDebit: Parser = (msg) => {
  const lower = msg.toLowerCase();
  if (!["debit", "spent", "paid"].some((n) => lower.includes(n))) return null;
  const m = msg.match(/(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?(?:debited|spent|charged)/i);
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  return { amount, type: "debit", merchantRaw: fallbackMerchant(msg), rawText: msg, matchedBy: "generic-debit" };
};

const genericCredit: Parser = (msg) => {
  const lower = msg.toLowerCase();
  if (!["credit", "received"].some((n) => lower.includes(n))) return null;
  const m = msg.match(/(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)\s+(?:is\s+)?credited/i);
  if (!m) return null;
  const amount = parseAmountToPaise(m[1]!);
  if (amount === null) return null;
  return { amount, type: "credit", merchantRaw: fallbackMerchant(msg), rawText: msg, matchedBy: "generic-credit" };
};

/** Ordered most-precise first. */
const PARSERS: Parser[] = [
  hdfcSavingsSent,
  hdfcSavingsCredited,
  federalReceived,
  federalSent,
  hdfcCardTxn,
  hdfcCardSpent,
  iciciCard,
  sbiCard,
  genericFor(["hdfc"], "hdfc-generic"),
  genericFor(["icici"], "icici-generic"),
  genericFor(["sbi", "state bank"], "sbi-generic"),
  genericFor(["axis"], "axis-generic"),
  genericFor(["kotak"], "kotak-generic"),
  genericFor(["yes bank", "yesbank"], "yes-generic"),
  upiGeneric,
  genericDebit,
  genericCredit,
];

/** Returns null when nothing matched — caller decides whether to try an LLM. */
export function parseSMS(message: string): ParsedSMS | null {
  const msg = message.trim();
  if (!msg) return null;
  for (const parser of PARSERS) {
    const result = parser(msg);
    if (result) return result;
  }
  return null;
}
