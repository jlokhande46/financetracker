import type { Paise, Transaction } from "./types";
import { isTransferCategory } from "./categories";

/**
 * Finding recurring charges the user never told us about.
 *
 * Netflix, a gym, an annual domain renewal — the ones that quietly keep taking
 * money. Detection is by cadence, not by a merchant blocklist: a hardcoded list
 * would be wrong for every market it wasn't written for, and would miss the
 * local gym that actually matters.
 */

export type Cadence = "weekly" | "monthly" | "quarterly" | "yearly";

export interface Subscription {
  merchantName: string;
  categorySlug: string;
  cadence: Cadence;
  /** The amount it usually charges — the median, so one odd month doesn't skew it. */
  typicalAmount: Paise;
  /** What it costs over a year at this cadence. */
  annualCost: Paise;
  occurrences: number;
  lastCharged: number;
  /** Best guess at the next charge, from the last one plus the cadence. */
  nextExpected: number;
  /** 0-1: how regular the intervals and amounts are. */
  confidence: number;
}

const DAY = 86_400_000;

/** Expected gap in days, and how far off a real gap can be and still count. */
const CADENCES: Array<{ cadence: Cadence; days: number; tolerance: number; perYear: number }> = [
  { cadence: "weekly", days: 7, tolerance: 2, perYear: 52 },
  { cadence: "monthly", days: 30.4, tolerance: 6, perYear: 12 },
  { cadence: "quarterly", days: 91, tolerance: 12, perYear: 4 },
  { cadence: "yearly", days: 365, tolerance: 30, perYear: 1 },
];

const median = (xs: number[]): number => {
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid]! : Math.round((s[mid - 1]! + s[mid]!) / 2);
};

/**
 * Group debits by merchant and look for a regular cadence.
 *
 * Needs at least three charges. Two could be coincidence — a restaurant you
 * happened to visit a month apart — and calling that a subscription would make
 * the whole feature untrustworthy.
 */
export function detectSubscriptions(
  transactions: Transaction[],
  now: number = Date.now(),
): Subscription[] {
  const byMerchant = new Map<string, Transaction[]>();
  for (const t of transactions) {
    if (t.isDeleted || t.isHidden || t.type !== "debit") continue;
    // Card payments and transfers recur by nature; they aren't subscriptions.
    if (isTransferCategory(t.categorySlug)) continue;
    const key = (t.merchantName || t.merchantRaw || "").trim().toLowerCase();
    if (!key) continue;
    if (!byMerchant.has(key)) byMerchant.set(key, []);
    byMerchant.get(key)!.push(t);
  }

  const out: Subscription[] = [];

  for (const group of byMerchant.values()) {
    if (group.length < 3) continue;
    const sorted = [...group].sort((a, b) => a.date - b.date);

    const gaps: number[] = [];
    for (let i = 1; i < sorted.length; i++) {
      gaps.push((sorted[i]!.date - sorted[i - 1]!.date) / DAY);
    }
    const typicalGap = median(gaps);

    const match = CADENCES.find((c) => Math.abs(typicalGap - c.days) <= c.tolerance);
    if (!match) continue;

    // How consistently the gaps hit that cadence.
    const onCadence = gaps.filter((g) => Math.abs(g - match.days) <= match.tolerance).length;
    const regularity = onCadence / gaps.length;
    if (regularity < 0.6) continue;

    const amounts = sorted.map((t) => t.amount);
    const typicalAmount = median(amounts);
    // A subscription charges roughly the same each time. Groceries at the same
    // shop every week won't — that's what separates them.
    const steady = typicalAmount > 0
      ? amounts.filter((a) => Math.abs(a - typicalAmount) / typicalAmount <= 0.15).length / amounts.length
      : 0;
    if (steady < 0.6) continue;

    const last = sorted[sorted.length - 1]!;
    // Long gone — a cancelled subscription shouldn't keep showing up.
    const sinceLast = (now - last.date) / DAY;
    if (sinceLast > match.days * 2 + match.tolerance) continue;

    out.push({
      merchantName: last.merchantName || last.merchantRaw,
      categorySlug: last.categorySlug,
      cadence: match.cadence,
      typicalAmount,
      annualCost: typicalAmount * match.perYear,
      occurrences: sorted.length,
      lastCharged: last.date,
      nextExpected: last.date + match.days * DAY,
      confidence: Math.min(1, (regularity * 0.5 + steady * 0.3 + Math.min(1, sorted.length / 6) * 0.2)),
    });
  }

  return out.sort((a, b) => b.annualCost - a.annualCost);
}

export const CADENCE_LABEL: Record<Cadence, string> = {
  weekly: "Weekly",
  monthly: "Monthly",
  quarterly: "Every 3 months",
  yearly: "Yearly",
};

/** What every detected subscription costs per year, combined. */
export const totalAnnualCost = (subs: Subscription[]): Paise =>
  subs.reduce((sum, s) => sum + s.annualCost, 0);
