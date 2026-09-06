import type { Paise, Transaction } from "./types";
import { cycleStart, dateOnDay, nextCycleStart, type BillStatus, type RecurringBill } from "./bills";

/**
 * Finding the transaction that settled a bill, and deciding when to start
 * nagging about the ones that haven't been settled.
 *
 * Kept apart from bills.ts so the cycle maths stays free of transaction
 * concerns and testable on its own.
 */

export interface BillCandidate {
  transaction: Transaction;
  /** 0-1. Purely for ordering the picker — the user makes the final call. */
  score: number;
  reason: string;
}

/** How far either side of the due date a payment can land and still count. */
const WINDOW_DAYS_BEFORE = 12;
const WINDOW_DAYS_AFTER = 12;
const DAY = 86_400_000;

/**
 * Debits that plausibly paid this bill, best guess first.
 *
 * Deliberately generous: it's a shortlist for a human to pick from, not an
 * auto-matcher. Guessing wrong and silently marking a bill paid is worse than
 * showing one extra row.
 */
export function billCandidates(
  status: BillStatus,
  transactions: Transaction[],
  limit = 8,
): BillCandidate[] {
  const { bill, dueDate } = status;
  const from = dueDate - WINDOW_DAYS_BEFORE * DAY;
  const to = dueDate + WINDOW_DAYS_AFTER * DAY;
  const name = bill.name.toLowerCase();

  const out: BillCandidate[] = [];
  for (const t of transactions) {
    if (t.isDeleted || t.isHidden || t.type !== "debit") continue;
    if (t.date < from || t.date > to) continue;

    let score = 0.2;
    const reasons: string[] = [];

    if (bill.accountId && t.accountId === bill.accountId) {
      score += 0.3;
      reasons.push("same card");
    }
    if (t.categorySlug === bill.categorySlug) {
      score += 0.2;
      reasons.push("same category");
    }
    const merchant = `${t.merchantName} ${t.merchantRaw}`.toLowerCase();
    if (name.length >= 3 && merchant.includes(name)) {
      score += 0.25;
      reasons.push("name matches");
    }
    if (bill.expectedAmount > 0) {
      const drift = Math.abs(t.amount - bill.expectedAmount) / bill.expectedAmount;
      if (drift < 0.02) { score += 0.3; reasons.push("exact amount"); }
      else if (drift < 0.2) { score += 0.15; reasons.push("similar amount"); }
    }
    // Closer to the due date is a better guess, worth up to 0.1.
    score += 0.1 * Math.max(0, 1 - Math.abs(t.date - dueDate) / (WINDOW_DAYS_AFTER * DAY));

    out.push({
      transaction: t,
      score: Math.min(1, score),
      reason: reasons.join(" · ") || "in the due-date window",
    });
  }

  return out.sort((a, b) => b.score - a.score || b.transaction.date - a.transaction.date)
            .slice(0, limit);
}

// ── salary-triggered reminders ───────────────────────────────────────────────

/**
 * Was salary credited in the month containing `now`?
 *
 * This is the trigger the user asked for: reminders start once money has
 * landed, not on the 1st when there's nothing to pay bills with.
 */
export function salaryCredit(
  transactions: Transaction[],
  now: number = Date.now(),
): Transaction | null {
  const ref = new Date(now);
  const monthStart = new Date(ref.getFullYear(), ref.getMonth(), 1).getTime();
  const candidates = transactions.filter(
    (t) => !t.isDeleted && !t.isHidden && t.type === "credit" &&
           t.date >= monthStart && t.date <= now &&
           (t.categorySlug === "salary" || /salary|sal cr|payroll/i.test(`${t.merchantName} ${t.merchantRaw}`)),
  );
  if (candidates.length === 0) return null;
  // The largest credit is the salary; smaller ones are reimbursements.
  return candidates.reduce((a, b) => (b.amount > a.amount ? b : a));
}

export interface ReminderPlan {
  /** Null when salary hasn't landed yet — nothing to nag about. */
  salaryDate: number | null;
  outstanding: BillStatus[];
  totalOutstanding: Paise;
  /** Copy for the notification, or null when there's nothing to say. */
  message: string | null;
}

/**
 * What to remind the user about today.
 *
 * Silent until salary arrives, then lists every bill still unpaid this cycle
 * and stops the moment they're all settled — the "till all is marked paid"
 * behaviour, without a reminder that outlives its usefulness.
 */
export function reminderPlan(
  statuses: BillStatus[],
  transactions: Transaction[],
  now: number = Date.now(),
): ReminderPlan {
  const salary = salaryCredit(transactions, now);
  const outstanding = statuses.filter((s) => !s.isPaid && s.bill.isActive);
  const totalOutstanding = outstanding.reduce(
    (sum, s) => sum + (s.payment?.amount ?? s.bill.expectedAmount), 0,
  );

  if (!salary || outstanding.length === 0) {
    return { salaryDate: salary?.date ?? null, outstanding, totalOutstanding, message: null };
  }

  const overdue = outstanding.filter((s) => s.state === "overdue");
  const message = overdue.length > 0
    ? `${overdue.length} bill${overdue.length === 1 ? " is" : "s are"} overdue — ${overdue.map((s) => s.bill.name).join(", ")}`
    : `${outstanding.length} bill${outstanding.length === 1 ? "" : "s"} left to pay this month`;

  return { salaryDate: salary.date, outstanding, totalOutstanding, message };
}

/**
 * Reminder cadence, ramping as the due date approaches — the same escalation
 * the iOS build used, expressed as "how many times a day".
 */
export function reminderFrequency(daysUntilDue: number): number {
  if (daysUntilDue < 0) return 3;
  if (daysUntilDue === 0) return 3;
  if (daysUntilDue <= 2) return 2;
  if (daysUntilDue <= 7) return 1;
  return 0;
}

/**
 * A credit-card statement becomes a bill on its statement day. Given a card's
 * statement/due days, the bill for the cycle we're currently in.
 */
export function creditCardBillDates(
  statementDay: number,
  dueDay: number,
  now: number = Date.now(),
): { statementDate: number; dueDate: number } {
  const d = new Date(now);
  const thisMonth = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  const statementDate = dateOnDay(thisMonth, statementDay);
  // A due day at or before the statement day belongs to the following month —
  // that's the "bills on the 16th, due on the 30th" vs "bills 7th, due 21st"
  // distinction, and a naive same-month assumption gets one of them wrong.
  const dueMonth = dueDay > statementDay
    ? thisMonth
    : new Date(d.getFullYear(), d.getMonth() + 1, 1).getTime();
  return { statementDate, dueDate: dateOnDay(dueMonth, dueDay) };
}

/** Re-exported so callers doing cycle arithmetic need only this module. */
export { cycleStart, nextCycleStart };
export type { RecurringBill };
