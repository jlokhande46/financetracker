import type { Account, Paise } from "./types";
import { dueDescription, type BillStatus } from "./bills";
import { reminderFrequency } from "./billMatching";
import { tipOfTheDay } from "./tips";

/**
 * Working out what to be reminded about, and when.
 *
 * This runs in the browser, where the ledger lives, and produces a small list of
 * {when, title, body} the Worker can fire blind. The server never needs to see a
 * transaction to send "Rent is due tomorrow" — which is the only reason putting
 * notifications on a server is tolerable at all.
 */

export interface ScheduledReminder {
  /** Stable per bill+day+slot, so re-uploading the schedule can't duplicate one. */
  id: string;
  send_at: number;
  title: string;
  body: string;
  /** Collapses repeats of the same bill on the lock screen. */
  tag: string;
  url: string;
}

/** Hours of the day a reminder can land, used in order as the cadence ramps. */
const SLOT_HOURS = [9, 14, 19];

/** How far ahead to schedule. The client re-uploads whenever it opens. */
const HORIZON_DAYS = 14;

const DAY = 86_400_000;

const dayStart = (ms: number) => {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
};

const dayKey = (ms: number) => {
  const d = new Date(ms);
  return `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;
};

const inr = (p: Paise) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 })
    .format(p / 100);

/**
 * Reminders for every unpaid bill across the next fortnight, at a cadence that
 * ramps toward the due date.
 *
 * `salaryLanded` gates the whole thing. Nagging on the 1st about a bill you
 * can't pay until the 3rd is just noise — which is exactly what the user asked
 * to avoid.
 */
export function billReminders(
  statuses: BillStatus[],
  salaryLanded: boolean,
  now: number = Date.now(),
): ScheduledReminder[] {
  if (!salaryLanded) return [];

  const out: ScheduledReminder[] = [];
  for (const status of statuses) {
    if (status.isPaid || !status.bill.isActive) continue;

    for (let offset = 0; offset <= HORIZON_DAYS; offset++) {
      const day = dayStart(now) + offset * DAY;
      const daysUntilDue = Math.round((dayStart(status.dueDate) - day) / DAY);
      const perDay = reminderFrequency(daysUntilDue);
      if (perDay === 0) continue;

      for (let slot = 0; slot < perDay; slot++) {
        const at = new Date(day);
        at.setHours(SLOT_HOURS[slot]!, 0, 0, 0);
        if (at.getTime() <= now) continue;

        const amount = status.bill.expectedAmount;
        out.push({
          id: `bill-${status.bill.id}-${dayKey(day)}-${slot}`,
          send_at: at.getTime(),
          title: `${status.bill.name}${amount > 0 ? ` · ${inr(amount)}` : ""}`,
          body: describeForPush(status, daysUntilDue),
          // Same tag across the whole bill, so three nudges don't stack into
          // three lock-screen rows.
          tag: `bill-${status.bill.id}`,
          url: "/",
        });
      }
    }
  }
  return out;
}

function describeForPush(status: BillStatus, daysUntilDue: number): string {
  if (daysUntilDue < 0) return `${-daysUntilDue} day${daysUntilDue === -1 ? "" : "s"} past due. Mark it paid once it's settled.`;
  if (daysUntilDue === 0) return "Due today.";
  if (daysUntilDue === 1) return "Due tomorrow.";
  return dueDescription(status);
}

/**
 * A nudge to import each card's statement on the day it's generated — the point
 * at which the PDF actually exists.
 */
export function statementReminders(
  accounts: Account[],
  now: number = Date.now(),
): ScheduledReminder[] {
  const out: ScheduledReminder[] = [];
  for (const account of accounts) {
    if (account.type !== "credit" || !account.statementDay || !account.isActive) continue;

    for (let offset = 0; offset <= HORIZON_DAYS; offset++) {
      const day = new Date(dayStart(now) + offset * DAY);
      const last = new Date(day.getFullYear(), day.getMonth() + 1, 0).getDate();
      // Clamp, so a statement day of 30 still fires in February.
      if (day.getDate() !== Math.min(account.statementDay, last)) continue;

      const at = new Date(day);
      at.setHours(SLOT_HOURS[0]!, 0, 0, 0);
      if (at.getTime() <= now) continue;

      out.push({
        id: `stmt-${account.id}-${dayKey(day.getTime())}`,
        send_at: at.getTime(),
        title: `${account.name} statement is out`,
        body: "Import the PDF to bring in anything the SMS alerts missed.",
        tag: `stmt-${account.id}`,
        url: "/",
      });
    }
  }
  return out;
}

/** The daily money tip, matching what the dashboard shows that day. */
export function tipReminders(now: number = Date.now()): ScheduledReminder[] {
  const out: ScheduledReminder[] = [];
  for (let offset = 0; offset <= HORIZON_DAYS; offset++) {
    const day = dayStart(now) + offset * DAY;
    const at = new Date(day);
    at.setHours(SLOT_HOURS[1]!, 0, 0, 0);
    if (at.getTime() <= now) continue;

    out.push({
      id: `tip-${dayKey(day)}`,
      send_at: at.getTime(),
      title: "Money tip",
      body: tipOfTheDay(day).text,
      tag: "tip",
      url: "/",
    });
  }
  return out;
}

export interface ScheduleOptions {
  bills: boolean;
  statements: boolean;
  tips: boolean;
}

/**
 * The full schedule to upload. Sorted and capped, because the Worker keeps the
 * whole list in D1 and there's no value in queueing a month of tips.
 */
export function buildSchedule(opts: {
  statuses: BillStatus[];
  accounts: Account[];
  salaryLanded: boolean;
  enabled: ScheduleOptions;
  now?: number;
}): ScheduledReminder[] {
  const now = opts.now ?? Date.now();
  const all = [
    ...(opts.enabled.bills ? billReminders(opts.statuses, opts.salaryLanded, now) : []),
    ...(opts.enabled.statements ? statementReminders(opts.accounts, now) : []),
    ...(opts.enabled.tips ? tipReminders(now) : []),
  ];
  return all.sort((a, b) => a.send_at - b.send_at).slice(0, 200);
}
