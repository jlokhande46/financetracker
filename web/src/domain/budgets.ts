import type { Paise, Transaction } from "./types";
import { inMonth, startOfMonth } from "./analysis";
import { isTransferCategory } from "./categories";

/**
 * Monthly spending caps, per category or across the board.
 *
 * The pacing figure is what makes a budget useful mid-month: ₹8,000 of a
 * ₹10,000 food budget is fine on the 28th and alarming on the 9th, and a bar
 * alone can't tell you which.
 */

/** Sentinel slug for an overall monthly cap rather than a per-category one. */
export const TOTAL_BUDGET_SLUG = "__total__";

export interface Budget {
  id: string;
  /** Category slug, or TOTAL_BUDGET_SLUG. */
  categorySlug: string;
  limit: Paise;
  createdAt: number;
}

export type BudgetState = "under" | "onTrack" | "warning" | "over";

export interface BudgetStatus {
  budget: Budget;
  spent: Paise;
  remaining: Paise;
  /** Spent / limit. Can exceed 1. */
  fraction: number;
  /** Where spending should be by now if it were spread evenly. */
  expectedFraction: number;
  state: BudgetState;
  /** Spend per remaining day to finish exactly on budget; 0 once over. */
  dailyAllowance: Paise;
  projectedSpend: Paise;
}

export const BUDGET_STATE_META: Record<BudgetState, { label: string; color: string }> = {
  under: { label: "Under budget", color: "var(--income-green)" },
  onTrack: { label: "On track", color: "var(--income-green)" },
  warning: { label: "Running hot", color: "var(--warning-amber)" },
  over: { label: "Over budget", color: "var(--expense-red)" },
};

export function budgetStatus(
  budget: Budget,
  transactions: Transaction[],
  monthStart: number = startOfMonth(Date.now()),
  now: number = Date.now(),
): BudgetStatus {
  const spent = transactions
    .filter((t) =>
      !t.isDeleted && !t.isHidden && t.type === "debit" &&
      inMonth(t.date, monthStart) &&
      // Card payments and transfers move money, they don't spend it — counting
      // them would blow every budget the moment a statement is settled.
      !isTransferCategory(t.categorySlug) &&
      (budget.categorySlug === TOTAL_BUDGET_SLUG || t.categorySlug === budget.categorySlug))
    .reduce((sum, t) => sum + t.amount, 0);

  const m = new Date(monthStart);
  const days = new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate();
  // A past month is fully elapsed; a future one hasn't started.
  const elapsed = inMonth(now, monthStart)
    ? new Date(now).getDate()
    : now > monthStart ? days : 0;
  const daysLeft = Math.max(0, days - elapsed);

  const fraction = budget.limit > 0 ? spent / budget.limit : 0;
  const expectedFraction = days > 0 ? elapsed / days : 0;
  const remaining = budget.limit - spent;

  const state: BudgetState =
    remaining < 0 ? "over"
    : fraction > expectedFraction + 0.15 ? "warning"
    : fraction > expectedFraction ? "onTrack"
    : "under";

  return {
    budget, spent, remaining, fraction, expectedFraction, state,
    dailyAllowance: remaining > 0 && daysLeft > 0 ? Math.floor(remaining / daysLeft) : 0,
    // Straight-line projection. Crude, but it answers "will I make it?".
    projectedSpend: elapsed > 0 ? Math.round((spent / elapsed) * days) : 0,
  };
}

export function budgetStatuses(
  budgets: Budget[],
  transactions: Transaction[],
  monthStart: number = startOfMonth(Date.now()),
  now: number = Date.now(),
): BudgetStatus[] {
  return budgets
    .map((b) => budgetStatus(b, transactions, monthStart, now))
    // Worst first, so the one needing attention is at the top.
    .sort((a, b) => b.fraction - a.fraction);
}
