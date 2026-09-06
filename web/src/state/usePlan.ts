import { useCallback, useEffect, useMemo, useState } from "react";
import { db } from "../db/db";
import {
  billStatus, periodKeyOf, sortBillStatuses,
  type BillPayment, type BillStatus, type RecurringBill,
} from "../domain/bills";
import { budgetStatuses, type Budget, type BudgetStatus } from "../domain/budgets";
import { goalStatuses, type Goal, type GoalStatus } from "../domain/goals";
import { reminderPlan, type ReminderPlan } from "../domain/billMatching";
import { startOfMonth } from "../domain/analysis";
import type { Paise, Transaction } from "../domain/types";

/**
 * Bills, budgets and goals share one hook because the Plan screen shows all
 * three and they all invalidate together — a payment marks a bill paid AND
 * moves the budget it belongs to.
 */
export function usePlan(transactions: Transaction[]) {
  const [bills, setBills] = useState<RecurringBill[]>([]);
  const [payments, setPayments] = useState<BillPayment[]>([]);
  const [budgets, setBudgets] = useState<Budget[]>([]);
  const [goals, setGoals] = useState<Goal[]>([]);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    const [b, p, bg, g] = await Promise.all([
      db.bills.toArray(), db.billPayments.toArray(),
      db.budgets.toArray(), db.goals.toArray(),
    ]);
    setBills(b); setPayments(p); setBudgets(bg); setGoals(g);
    setLoading(false);
  }, []);

  useEffect(() => { void reload(); }, [reload]);

  const billStatuses = useMemo(
    () => sortBillStatuses(bills.filter((b) => b.isActive).map((b) => billStatus(b, payments))),
    [bills, payments],
  );

  const budgetList = useMemo(
    () => budgetStatuses(budgets, transactions, startOfMonth(Date.now())),
    [budgets, transactions],
  );

  const goalList = useMemo(() => goalStatuses(goals), [goals]);

  const reminders = useMemo(
    () => reminderPlan(billStatuses, transactions),
    [billStatuses, transactions],
  );

  return {
    loading, reload,
    bills, billStatuses, payments,
    budgets, budgetList,
    goals, goalList,
    reminders,
  };
}

export type { BillStatus, BudgetStatus, GoalStatus, ReminderPlan };

// ── bill mutations ───────────────────────────────────────────────────────────

export async function saveBill(bill: RecurringBill): Promise<void> {
  await db.bills.put(bill);
}

/**
 * Deletes a bill and the payment history that belonged to it — orphaned
 * payments would otherwise silently mark a recreated bill as already settled.
 */
export async function deleteBill(id: string): Promise<void> {
  const owned = await db.billPayments.where("billId").equals(id).primaryKeys();
  await db.billPayments.bulkDelete(owned);
  await db.bills.delete(id);
}

/**
 * Record a bill as paid for a cycle, optionally pointing at the transaction
 * that settled it.
 *
 * The id is `${billId}:${periodKey}` so marking the same cycle twice overwrites
 * rather than stacking up duplicate payments.
 */
export async function markBillPaid(opts: {
  billId: string;
  periodKey: string;
  amount: Paise;
  transactionId?: string;
  paidAt?: number;
}): Promise<void> {
  await db.billPayments.put({
    id: `${opts.billId}:${opts.periodKey}`,
    billId: opts.billId,
    periodKey: opts.periodKey,
    paidAt: opts.paidAt ?? Date.now(),
    amount: opts.amount,
    transactionId: opts.transactionId,
  });
}

export async function markBillUnpaid(billId: string, periodKey: string): Promise<void> {
  await db.billPayments.delete(`${billId}:${periodKey}`);
}

/** The key for the cycle a bill status is currently showing. */
export const statusPeriodKey = (s: BillStatus) => s.periodKey;
export { periodKeyOf };

// ── budget mutations ─────────────────────────────────────────────────────────

export async function saveBudget(budget: Budget): Promise<void> {
  await db.budgets.put(budget);
}

export async function deleteBudget(id: string): Promise<void> {
  await db.budgets.delete(id);
}

// ── goal mutations ───────────────────────────────────────────────────────────

export async function saveGoal(goal: Goal): Promise<void> {
  await db.goals.put(goal);
}

export async function deleteGoal(id: string): Promise<void> {
  await db.goals.delete(id);
}

/** Add to (or, with a negative delta, withdraw from) a goal's saved amount. */
export async function contributeToGoal(id: string, delta: Paise): Promise<void> {
  const goal = await db.goals.get(id);
  if (!goal) return;
  await db.goals.put({ ...goal, savedAmount: Math.max(0, goal.savedAmount + delta) });
}
