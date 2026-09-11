import type { Paise, Transaction } from "./types";
import { INTENT_META } from "./types";
import { findCategory, isTransferCategory } from "./categories";
import { addMonths, effectiveIntent, inMonth, needsWants, startOfMonth } from "./analysis";
import { budgetStatuses, type Budget } from "./budgets";
import { goalStatuses, type Goal } from "./goals";
import { detectSubscriptions, type Subscription } from "./subscriptions";

/**
 * Heuristic insights for the dashboard. Rules over the user's own numbers —
 * no model, nothing fetched.
 *
 * The hard part isn't generating these, it's not generating too many. An
 * insight card that always says something becomes wallpaper, so each rule has
 * a threshold it must actually clear, and only the highest-priority few are
 * shown.
 */

export type InsightKind =
  | "wantsOverTarget" | "savingsLow" | "topWant" | "categorySpike"
  | "budgetProjectedOver" | "goalShortfall" | "goalOnTrack"
  | "subscriptions" | "unusualCharge" | "spendDown";

export interface Insight {
  kind: InsightKind;
  headline: string;
  detail: string;
  color: string;
  /** Lower sorts first. */
  priority: number;
}

const inr = (p: Paise) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 })
    .format(p / 100);

const AMBER = "var(--warning-amber)";
const RED = "var(--expense-red)";
const GREEN = "var(--income-green)";
const BRAND = "var(--brand-primary)";

export interface InsightInput {
  all: Transaction[];
  budgets: Budget[];
  goals: Goal[];
  month?: number;
  now?: number;
}

export function generateInsights(input: InsightInput): Insight[] {
  const now = input.now ?? Date.now();
  const month = input.month ?? startOfMonth(now);
  const live = input.all.filter((t) => !t.isDeleted && !t.isHidden);
  const monthTxns = live.filter((t) => inMonth(t.date, month));
  const spendable = monthTxns.filter((t) => !isTransferCategory(t.categorySlug));
  const expenses = spendable.filter((t) => t.type === "debit");
  const totalSpend = expenses.reduce((s, t) => s + t.amount, 0);

  const out: Insight[] = [];

  // ── the 50/30/20 frame ─────────────────────────────────────────────────────
  const split = needsWants(monthTxns);
  if (split.total > 0) {
    const wantsPct = (split.want / split.total) * 100;
    if (wantsPct > 35) {
      const excess = split.want - Math.round(split.total * 0.3);
      out.push({
        kind: "wantsOverTarget",
        headline: `Wants are ${Math.round(wantsPct)}% of spending`,
        detail: `Target is 30%. Trimming about ${inr(excess)} would hit it — money that could go to a goal instead.`,
        color: AMBER,
        priority: 2,
      });
    }
    const savingsPct = (split.saving / split.total) * 100;
    if (savingsPct < 10) {
      out.push({
        kind: "savingsLow",
        headline: "Savings are under 10% of spending",
        detail: `${Math.round(savingsPct)}% went to savings this month against a 20% target.`,
        color: GREEN,
        priority: 3,
      });
    }
  }

  // ── biggest discretionary category ─────────────────────────────────────────
  const byCategory = new Map<string, Paise>();
  for (const t of expenses) {
    byCategory.set(t.categorySlug, (byCategory.get(t.categorySlug) ?? 0) + t.amount);
  }
  const topWant = [...byCategory.entries()]
    .filter(([slug]) => effectiveIntent({ categorySlug: slug } as Transaction) === "want")
    .sort((a, b) => b[1] - a[1])[0];
  if (topWant && topWant[1] > 0) {
    const cat = findCategory(topWant[0]);
    out.push({
      kind: "topWant",
      headline: `${cat.name} leads your wants`,
      detail: `${inr(topWant[1])} this month. A fifth of that is ${inr(Math.round(topWant[1] * 0.2))} back each month.`,
      color: cat.colorHex,
      priority: 5,
    });
  }

  // ── a category well above its own trailing average ─────────────────────────
  // Compared against the same category's own history, not a fixed number —
  // "you spent a lot on travel" is only meaningful relative to normal for you.
  const spike = findCategorySpike(live, month, byCategory);
  if (spike) out.push(spike);

  // ── budgets heading over ───────────────────────────────────────────────────
  for (const status of budgetStatuses(input.budgets, live, month, now)) {
    if (status.state !== "over" && status.projectedSpend > status.budget.limit * 1.1) {
      const label = status.budget.categorySlug === "__total__"
        ? "your monthly budget"
        : findCategory(status.budget.categorySlug).name;
      out.push({
        kind: "budgetProjectedOver",
        headline: `On pace to overshoot ${label}`,
        detail: `At this rate the month ends near ${inr(status.projectedSpend)} against a ${inr(status.budget.limit)} cap.`,
        color: AMBER,
        priority: 1,
      });
      break; // One is a warning; five is noise.
    }
  }

  // ── goals against what's actually spare ────────────────────────────────────
  const income = spendable.filter((t) => t.type === "credit").reduce((s, t) => s + t.amount, 0);
  const disposable = Math.max(0, income - totalSpend);
  for (const status of goalStatuses(input.goals, now).slice(0, 2)) {
    const needed = status.requiredPerMonth;
    if (needed === null || status.remaining === 0) continue;
    if (needed > disposable) {
      out.push({
        kind: "goalShortfall",
        headline: `${status.goal.name} needs ${inr(needed)}/month`,
        detail: disposable > 0
          ? `This month left about ${inr(disposable)} spare, so it's short by ${inr(needed - disposable)}.`
          : "Nothing was left over this month to put towards it.",
        color: RED,
        priority: 2,
      });
    } else {
      out.push({
        kind: "goalOnTrack",
        headline: `${status.goal.name} is within reach`,
        detail: `It needs ${inr(needed)}/month and about ${inr(disposable)} was spare this month.`,
        color: BRAND,
        priority: 6,
      });
    }
    break;
  }

  // ── recurring charges ──────────────────────────────────────────────────────
  const subs = detectSubscriptions(live, now);
  if (subs.length >= 2) {
    const annual = subs.reduce((s, x) => s + x.annualCost, 0);
    out.push({
      kind: "subscriptions",
      headline: `${subs.length} recurring charges found`,
      detail: `Together about ${inr(annual)} a year. The ones that hurt are the small monthly charges you stopped noticing.`,
      color: BRAND,
      priority: 4,
    });
  }

  // ── one unusually large charge ─────────────────────────────────────────────
  const unusual = findUnusualCharge(expenses, live, month);
  if (unusual) out.push(unusual);

  // ── something good, when there is something good ───────────────────────────
  const prevSpend = live
    .filter((t) => inMonth(t.date, addMonths(month, -1)) && t.type === "debit" && !isTransferCategory(t.categorySlug))
    .reduce((s, t) => s + t.amount, 0);
  if (prevSpend > 0 && totalSpend > 0 && totalSpend < prevSpend * 0.9) {
    out.push({
      kind: "spendDown",
      headline: `Spending is down ${Math.round((1 - totalSpend / prevSpend) * 100)}%`,
      detail: `${inr(totalSpend)} so far against ${inr(prevSpend)} last month.`,
      color: GREEN,
      priority: 4,
    });
  }

  return out.sort((a, b) => a.priority - b.priority).slice(0, 4);
}

/** A category at least 60% above its own trailing three-month average. */
function findCategorySpike(
  live: Transaction[],
  month: number,
  thisMonth: Map<string, Paise>,
): Insight | null {
  let best: { slug: string; amount: Paise; average: Paise; ratio: number } | null = null;

  for (const [slug, amount] of thisMonth) {
    if (amount <= 0) continue;
    const history: Paise[] = [];
    for (let back = 1; back <= 3; back++) {
      const m = addMonths(month, -back);
      const total = live
        .filter((t) => t.type === "debit" && t.categorySlug === slug && inMonth(t.date, m))
        .reduce((s, t) => s + t.amount, 0);
      history.push(total);
    }
    // Need real history — a category's first month isn't a spike.
    if (history.filter((h) => h > 0).length < 2) continue;
    const average = Math.round(history.reduce((a, b) => a + b, 0) / history.length);
    if (average <= 0) continue;

    const ratio = amount / average;
    if (ratio >= 1.6 && (!best || ratio > best.ratio)) {
      best = { slug, amount, average, ratio };
    }
  }

  if (!best) return null;
  const cat = findCategory(best.slug);
  return {
    kind: "categorySpike",
    headline: `${cat.name} is up ${Math.round((best.ratio - 1) * 100)}%`,
    detail: `${inr(best.amount)} this month against a ${inr(best.average)} average over the last three.`,
    color: cat.colorHex,
    priority: 1,
  };
}

/** A single charge far above what this account normally sees. */
function findUnusualCharge(
  expenses: Transaction[],
  live: Transaction[],
  month: number,
): Insight | null {
  const history = live.filter(
    (t) => t.type === "debit" && !isTransferCategory(t.categorySlug) && !inMonth(t.date, month),
  );
  if (history.length < 20) return null;

  const sorted = history.map((t) => t.amount).sort((a, b) => a - b);
  // 95th percentile rather than the mean — one big historical purchase
  // shouldn't raise the bar so far that nothing ever trips it.
  const p95 = sorted[Math.floor(sorted.length * 0.95)]!;
  const biggest = [...expenses].sort((a, b) => b.amount - a.amount)[0];
  if (!biggest || biggest.amount <= p95 * 1.5) return null;

  return {
    kind: "unusualCharge",
    headline: `${inr(biggest.amount)} at ${biggest.merchantName || biggest.merchantRaw}`,
    detail: "Well above your usual transaction size — worth a second look if you don't recognise it.",
    color: AMBER,
    priority: 3,
  };
}

export { detectSubscriptions, INTENT_META };
export type { Subscription };
