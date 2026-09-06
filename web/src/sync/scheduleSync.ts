import { db } from "../db/db";
import { billStatus } from "../domain/bills";
import { salaryCredit } from "../domain/billMatching";
import { buildSchedule } from "../domain/reminderSchedule";
import { pushPrefs, uploadSchedule } from "./push";

/**
 * Recompute the reminder schedule from local data and push it to the Worker.
 *
 * Runs whenever the app opens or comes back to the foreground. That's often
 * enough: the horizon is a fortnight, so even a user who doesn't open the app
 * for a week still has reminders queued — and each upload replaces the pending
 * set, so a bill marked paid stops nagging on the next launch rather than
 * needing its reminders individually cancelled.
 */
export async function syncReminderSchedule(): Promise<number> {
  if (!pushPrefs.enabled) return 0;

  const [bills, payments, accounts, transactions] = await Promise.all([
    db.bills.toArray(),
    db.billPayments.toArray(),
    db.accounts.toArray(),
    db.transactions.toArray(),
  ]);

  const statuses = bills
    .filter((b) => b.isActive)
    .map((b) => billStatus(b, payments));

  const reminders = buildSchedule({
    statuses,
    accounts,
    salaryLanded: salaryCredit(transactions) !== null,
    enabled: pushPrefs.options,
  });

  const ok = await uploadSchedule(reminders);
  return ok ? reminders.length : 0;
}
