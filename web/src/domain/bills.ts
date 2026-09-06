import type { Paise } from "./types";

/**
 * Recurring bills — rent, electricity, credit-card settlements, postpaid, and
 * the gas cylinder that only comes every second month.
 *
 * The point of the model is that a bill is not "paid" because a date passed.
 * It's paid when a real transaction settles it, which is why `BillPayment`
 * links to a transaction id. That's what lets the reminders stop at the right
 * moment instead of nagging past a payment the user already made.
 */

export type BillFrequency = "monthly" | "bimonthly" | "quarterly" | "yearly";

export const FREQUENCY_LABEL: Record<BillFrequency, string> = {
  monthly: "Every month",
  bimonthly: "Every 2 months",
  quarterly: "Every 3 months",
  yearly: "Every year",
};

export const MONTHS_PER_CYCLE: Record<BillFrequency, number> = {
  monthly: 1, bimonthly: 2, quarterly: 3, yearly: 12,
};

export interface RecurringBill {
  id: string;
  name: string;
  categorySlug: string;
  /** What it usually costs. The amount actually paid comes from the linked txn. */
  expectedAmount: Paise;
  /** Day of month, 1-31. Clamped into short months rather than rolling over. */
  dueDay: number;
  frequency: BillFrequency;
  /**
   * Epoch ms inside any month this bill falls due. Only matters for cycles
   * longer than a month — it's what decides whether the gas bill lands in odd
   * or even months.
   */
  anchorMonth: number;
  /** Set for a credit-card bill, so the Cards section and this share one state. */
  accountId?: string;
  isActive: boolean;
  createdAt: number;
}

export interface BillPayment {
  /** `${billId}:${periodKey}` — one payment per bill per cycle, by construction. */
  id: string;
  billId: string;
  periodKey: string;
  paidAt: number;
  amount: Paise;
  /** The transaction the user picked as the settling payment, when they picked one. */
  transactionId?: string;
}

export type BillState = "paid" | "upcoming" | "dueSoon" | "dueToday" | "overdue";

export interface BillStatus {
  bill: RecurringBill;
  /** The cycle still needing action. Rolls forward once the current one is settled. */
  periodKey: string;
  periodStart: number;
  dueDate: number;
  isPaid: boolean;
  /** The payment that settled the cycle we rolled past, if there was one. */
  payment?: BillPayment;
  /** Period key of that settled cycle — what an "undo" has to target. */
  paidPeriodKey?: string;
  /** Negative once the due date has passed. */
  daysUntilDue: number;
  state: BillState;
}

// ── cycle maths ──────────────────────────────────────────────────────────────

const startOfDay = (ms: number) => {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
};

const daysInMonth = (year: number, month: number) => new Date(year, month + 1, 0).getDate();

/**
 * A date on `day` of the given month, clamped to the month's length.
 *
 * `new Date(2026, 1, 31)` silently becomes 3 March. A bill due on the 31st has
 * to land on 28 February, not spill into the next month — that's the same
 * rollover the Swift `BillCycleManager` had to be taught to clamp.
 */
export function dateOnDay(monthStart: number, day: number): number {
  const d = new Date(monthStart);
  const clamped = Math.min(Math.max(1, day), daysInMonth(d.getFullYear(), d.getMonth()));
  return new Date(d.getFullYear(), d.getMonth(), clamped).getTime();
}

/** "2026-08" — stable across timezones because it's built from local parts. */
export function periodKeyOf(monthStart: number): string {
  const d = new Date(monthStart);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

const monthIndex = (ms: number) => {
  const d = new Date(ms);
  return d.getFullYear() * 12 + d.getMonth();
};

const monthStartFromIndex = (i: number) =>
  new Date(Math.floor(i / 12), i % 12, 1).getTime();

/**
 * The start of the billing cycle that contains `ms`.
 *
 * For a monthly bill this is just the month. For longer cycles it snaps back to
 * the nearest anchored cycle, so a bimonthly gas bill anchored to June is due
 * in June, August, October — never July.
 */
export function cycleStart(bill: RecurringBill, ms: number): number {
  const step = MONTHS_PER_CYCLE[bill.frequency];
  if (step === 1) return monthStartFromIndex(monthIndex(ms));
  const anchor = monthIndex(bill.anchorMonth);
  const delta = monthIndex(ms) - anchor;
  // Floor division, correct for negative deltas too (months before the anchor).
  const cycles = Math.floor(delta / step);
  return monthStartFromIndex(anchor + cycles * step);
}

export function nextCycleStart(bill: RecurringBill, ms: number): number {
  const step = MONTHS_PER_CYCLE[bill.frequency];
  return monthStartFromIndex(monthIndex(cycleStart(bill, ms)) + step);
}

// ── status ───────────────────────────────────────────────────────────────────

/** Inside this many days of the due date, a bill is "due soon". */
export const DUE_SOON_DAYS = 5;

/**
 * Where a bill stands right now.
 *
 * Once the cycle we're in is settled, the reported due date rolls forward to
 * the next one — "next due 5 Oct" is more useful than a stale card sitting on
 * a date that's already been dealt with.
 *
 * But the state stays `paid` for the rest of that cycle. Rolling forward
 * *silently* was a bug worth naming: the card went straight back to showing
 * "Mark paid" for next month, which is indistinguishable from the tap not
 * having registered.
 */
export function billStatus(
  bill: RecurringBill,
  payments: BillPayment[],
  now: number = Date.now(),
): BillStatus {
  const byKey = new Map(payments.filter((p) => p.billId === bill.id).map((p) => [p.periodKey, p]));

  let periodStart = cycleStart(bill, now);
  let key = periodKeyOf(periodStart);
  const settled = byKey.get(key);
  let paidPeriodKey: string | undefined;
  let payment = settled;

  if (settled) {
    paidPeriodKey = key;
    periodStart = nextCycleStart(bill, now);
    key = periodKeyOf(periodStart);
    // An early payment for the next cycle too keeps the newer one as the record
    // shown, so "Paid" always refers to the most recent settlement.
    const nextPayment = byKey.get(key);
    if (nextPayment) {
      paidPeriodKey = key;
      payment = nextPayment;
      periodStart = nextCycleStart(bill, periodStart);
      key = periodKeyOf(periodStart);
    }
  }

  const dueDate = dateOnDay(periodStart, bill.dueDay);
  const daysUntilDue = Math.round((startOfDay(dueDate) - startOfDay(now)) / 86_400_000);
  const isPaid = paidPeriodKey !== undefined;

  const state: BillState =
    isPaid ? "paid"
    : daysUntilDue < 0 ? "overdue"
    : daysUntilDue === 0 ? "dueToday"
    : daysUntilDue <= DUE_SOON_DAYS ? "dueSoon"
    : "upcoming";

  return {
    bill, periodKey: key, periodStart, dueDate,
    isPaid, payment, paidPeriodKey, daysUntilDue, state,
  };
}

const STATE_RANK: Record<BillState, number> = {
  overdue: 0, dueToday: 1, dueSoon: 2, upcoming: 3, paid: 4,
};

/** Most urgent first; ties broken by due date so the ordering is stable. */
export function sortBillStatuses(statuses: BillStatus[]): BillStatus[] {
  return [...statuses].sort(
    (a, b) => STATE_RANK[a.state] - STATE_RANK[b.state] || a.dueDate - b.dueDate,
  );
}

export const isOutstanding = (s: BillStatus) => !s.isPaid && s.daysUntilDue <= DUE_SOON_DAYS;

export const STATE_META: Record<BillState, { label: string; color: string }> = {
  paid: { label: "Paid", color: "var(--income-green)" },
  upcoming: { label: "Upcoming", color: "var(--text-secondary)" },
  dueSoon: { label: "Due soon", color: "var(--warning-amber)" },
  dueToday: { label: "Due today", color: "var(--warning-amber)" },
  overdue: { label: "Overdue", color: "var(--expense-red)" },
};

/** Human "in 3 days" / "4 days late", matching how the card reads it out. */
export function dueDescription(s: BillStatus): string {
  if (s.isPaid) return "Paid";
  return dueOnlyDescription(s.daysUntilDue);
}

/** The timing half on its own, for a paid card that still shows its next date. */
export function dueOnlyDescription(daysUntilDue: number): string {
  const d = daysUntilDue;
  if (d === 0) return "Due today";
  if (d === 1) return "Due tomorrow";
  if (d > 1) return `Due in ${d} days`;
  if (d === -1) return "1 day late";
  return `${-d} days late`;
}
