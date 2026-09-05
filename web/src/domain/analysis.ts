import type { CategoryIntent, Paise, Transaction } from "./types";
import { categoryIntent, isTransferCategory } from "./categories";

export interface CategorySpend {
  categorySlug: string;
  amount: Paise;
  count: number;
  percent: number;
}

export interface MerchantSpend {
  merchantName: string;
  amount: Paise;
  count: number;
  categorySlug: string;
}

export interface MonthlyAnalysis {
  month: number;
  totalIncome: Paise;
  totalExpenses: Paise;
  savings: Paise;
  savingsRate: number;
  categoryBreakdown: CategorySpend[];
  topMerchants: MerchantSpend[];
  dayWiseSpend: Array<{ date: number; amount: Paise }>;
  previousMonthExpenses: Paise;
  spendChangePercent: number;
}

export interface NeedsWantsBreakdown {
  need: Paise;
  want: Paise;
  saving: Paise;
  total: Paise;
}

/** User override wins over the category's default mapping. */
export function effectiveIntent(t: Transaction): CategoryIntent | null {
  return t.intentOverride ?? categoryIntent(t.categorySlug);
}

export const inMonth = (ms: number, monthStart: number): boolean => {
  const a = new Date(ms), b = new Date(monthStart);
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth();
};

export function startOfMonth(ms: number): number {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), 1).getTime();
}

export function addMonths(ms: number, delta: number): number {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth() + delta, 1).getTime();
}

const live = (t: Transaction) => !t.isDeleted && !t.isHidden;

/**
 * The 50/30/20 split for a set of transactions.
 *
 * Only debits count — income isn't part of the spend split. Transfers and card
 * payments are excluded upstream by `categoryIntent` returning null for them,
 * which is what stops a ₹35K card payment from showing up as a "want".
 */
export function needsWants(transactions: Transaction[]): NeedsWantsBreakdown {
  const out: NeedsWantsBreakdown = { need: 0, want: 0, saving: 0, total: 0 };
  for (const t of transactions) {
    if (!live(t) || t.type !== "debit") continue;
    const intent = effectiveIntent(t);
    if (!intent) continue;
    out[intent] += t.amount;
    out.total += t.amount;
  }
  return out;
}

export function analyseMonth(
  monthStart: number,
  all: Transaction[],
): MonthlyAnalysis {
  const txns = all.filter((t) => live(t) && inMonth(t.date, monthStart));
  const spendable = txns.filter((t) => !isTransferCategory(t.categorySlug));

  const totalIncome = spendable
    .filter((t) => t.type === "credit")
    .reduce((sum, t) => sum + t.amount, 0);
  const totalExpenses = spendable
    .filter((t) => t.type === "debit")
    .reduce((sum, t) => sum + t.amount, 0);

  const savings = totalIncome - totalExpenses;
  const savingsRate = totalIncome > 0 ? (savings / totalIncome) * 100 : 0;

  // Category breakdown (top 6 by spend)
  const catMap = new Map<string, { amount: Paise; count: number }>();
  for (const t of spendable) {
    if (t.type !== "debit") continue;
    const cur = catMap.get(t.categorySlug) ?? { amount: 0, count: 0 };
    catMap.set(t.categorySlug, { amount: cur.amount + t.amount, count: cur.count + 1 });
  }
  const categoryBreakdown: CategorySpend[] = [...catMap.entries()]
    .map(([categorySlug, v]) => ({
      categorySlug,
      amount: v.amount,
      count: v.count,
      percent: totalExpenses > 0 ? (v.amount / totalExpenses) * 100 : 0,
    }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 6);

  // Top merchants (top 5)
  const merchMap = new Map<string, { amount: Paise; count: number; slug: string }>();
  for (const t of txns) {
    if (t.type !== "debit") continue;
    const key = t.merchantName || t.merchantRaw || "Unknown";
    const cur = merchMap.get(key) ?? { amount: 0, count: 0, slug: t.categorySlug };
    merchMap.set(key, { amount: cur.amount + t.amount, count: cur.count + 1, slug: cur.slug });
  }
  const topMerchants: MerchantSpend[] = [...merchMap.entries()]
    .map(([merchantName, v]) => ({
      merchantName, amount: v.amount, count: v.count, categorySlug: v.slug,
    }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 5);

  // Day-wise spend across the whole month, zero-filled so the chart has no gaps.
  const d = new Date(monthStart);
  const daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  const perDay = new Map<number, Paise>();
  for (const t of spendable) {
    if (t.type !== "debit") continue;
    perDay.set(new Date(t.date).getDate(), (perDay.get(new Date(t.date).getDate()) ?? 0) + t.amount);
  }
  const dayWiseSpend = Array.from({ length: daysInMonth }, (_, i) => ({
    date: new Date(d.getFullYear(), d.getMonth(), i + 1).getTime(),
    amount: perDay.get(i + 1) ?? 0,
  }));

  const prevStart = addMonths(monthStart, -1);
  const previousMonthExpenses = all
    .filter((t) => live(t) && inMonth(t.date, prevStart) && !isTransferCategory(t.categorySlug) && t.type === "debit")
    .reduce((sum, t) => sum + t.amount, 0);

  const spendChangePercent = previousMonthExpenses > 0
    ? ((totalExpenses - previousMonthExpenses) / previousMonthExpenses) * 100
    : 0;

  return {
    month: monthStart,
    totalIncome,
    totalExpenses,
    savings,
    savingsRate,
    categoryBreakdown,
    topMerchants,
    dayWiseSpend,
    previousMonthExpenses,
    spendChangePercent,
  };
}
