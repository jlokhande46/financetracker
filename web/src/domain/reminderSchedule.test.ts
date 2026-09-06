import { describe, expect, it } from "vitest";
import { rupees, type Account } from "./types";
import { billStatus, type BillPayment, type RecurringBill } from "./bills";
import { billReminders, buildSchedule, statementReminders, tipReminders } from "./reminderSchedule";
import { tipOfTheDay, TIPS } from "./tips";

const at = (y: number, m: number, d: number, h = 8) => new Date(y, m - 1, d, h).getTime();

function bill(over: Partial<RecurringBill> = {}): RecurringBill {
  return {
    id: "b1", name: "Rent", categorySlug: "rent", expectedAmount: rupees(25000),
    dueDay: 12, frequency: "monthly", anchorMonth: at(2026, 8, 1),
    isActive: true, createdAt: at(2026, 1, 1),
    ...over,
  };
}

const account = (over: Partial<Account> = {}): Account => ({
  id: "acc1", name: "ICICI Sapphiro", bankName: "ICICI Bank", type: "credit",
  balance: 0, openingBalance: 0, colorHex: "#F59E0B", isActive: true,
  statementDay: 16, dueDay: 30, createdAt: 0,
  ...over,
});

describe("bill reminders", () => {
  const now = at(2026, 8, 8);

  it("sends nothing until salary lands", () => {
    // The whole point of the salary gate: nagging on the 1st about a bill you
    // can't pay until the 3rd is noise.
    const statuses = [billStatus(bill(), [], now)];
    expect(billReminders(statuses, false, now)).toHaveLength(0);
    expect(billReminders(statuses, true, now).length).toBeGreaterThan(0);
  });

  it("ramps from one a day to three as the due date arrives", () => {
    const statuses = [billStatus(bill({ dueDay: 12 }), [], now)];
    const perDay = new Map<string, number>();
    for (const r of billReminders(statuses, true, now)) {
      const key = new Date(r.send_at).toDateString();
      perDay.set(key, (perDay.get(key) ?? 0) + 1);
    }
    expect(perDay.get(new Date(at(2026, 8, 9)).toDateString())).toBe(1);  // 3 days out
    expect(perDay.get(new Date(at(2026, 8, 11)).toDateString())).toBe(2); // 1 day out
    expect(perDay.get(new Date(at(2026, 8, 12)).toDateString())).toBe(3); // due
    expect(perDay.get(new Date(at(2026, 8, 13)).toDateString())).toBe(3); // overdue
  });

  it("says nothing more than a week out", () => {
    const statuses = [billStatus(bill({ dueDay: 25 }), [], now)];
    const early = billReminders(statuses, true, now)
      .filter((r) => r.send_at < at(2026, 8, 17));
    expect(early).toHaveLength(0);
  });

  it("stops entirely once the bill is marked paid", () => {
    const paid: BillPayment = {
      id: "b1:2026-08", billId: "b1", periodKey: "2026-08",
      paidAt: at(2026, 8, 7), amount: rupees(25000),
    };
    const statuses = [billStatus(bill(), [paid], now)];
    expect(billReminders(statuses, true, now)).toHaveLength(0);
  });

  it("skips a deactivated bill", () => {
    const statuses = [billStatus(bill({ isActive: false }), [], now)];
    expect(billReminders(statuses, true, now)).toHaveLength(0);
  });

  it("never schedules a reminder in the past", () => {
    const statuses = [billStatus(bill({ dueDay: 3 }), [], now)];
    expect(billReminders(statuses, true, now).every((r) => r.send_at > now)).toBe(true);
  });

  it("gives every reminder a stable, unique id so re-uploading can't duplicate one", () => {
    const statuses = [billStatus(bill(), [], now)];
    const first = billReminders(statuses, true, now);
    const second = billReminders(statuses, true, now);
    expect(first.map((r) => r.id)).toEqual(second.map((r) => r.id));
    expect(new Set(first.map((r) => r.id)).size).toBe(first.length);
  });

  it("shares one tag per bill so three nudges are one lock-screen row", () => {
    const statuses = [billStatus(bill(), [], now)];
    const tags = new Set(billReminders(statuses, true, now).map((r) => r.tag));
    expect([...tags]).toEqual(["bill-b1"]);
  });

  it("carries the amount in the title and the timing in the body", () => {
    const statuses = [billStatus(bill(), [], now)];
    const dueDay = billReminders(statuses, true, now)
      .find((r) => new Date(r.send_at).getDate() === 12);
    expect(dueDay?.title).toContain("Rent");
    expect(dueDay?.title).toContain("25,000");
    expect(dueDay?.body).toBe("Due today.");
  });
});

describe("statement reminders", () => {
  it("fires on each card's statement day", () => {
    const reminders = statementReminders([account({ statementDay: 16 })], at(2026, 8, 8));
    expect(reminders).toHaveLength(1);
    expect(new Date(reminders[0]!.send_at).getDate()).toBe(16);
    expect(reminders[0]!.body).toContain("Import");
  });

  it("clamps a statement day past the end of a short month", () => {
    const reminders = statementReminders([account({ statementDay: 30 })], at(2028, 2, 20));
    expect(new Date(reminders[0]!.send_at).getDate()).toBe(29); // leap year
  });

  it("ignores deposit accounts and inactive cards", () => {
    expect(statementReminders([account({ type: "savings" })], at(2026, 8, 8))).toHaveLength(0);
    expect(statementReminders([account({ isActive: false })], at(2026, 8, 8))).toHaveLength(0);
  });
});

describe("daily tip", () => {
  it("is stable through a day and changes the next", () => {
    // The push has to match what the dashboard shows, so it can't be random.
    expect(tipOfTheDay(at(2026, 8, 8, 1))).toEqual(tipOfTheDay(at(2026, 8, 8, 23)));
    expect(tipOfTheDay(at(2026, 8, 8))).not.toEqual(tipOfTheDay(at(2026, 8, 9)));
  });

  it("cycles through the whole set", () => {
    const seen = new Set<string>();
    for (let i = 0; i < TIPS.length; i++) seen.add(tipOfTheDay(at(2026, 8, 1) + i * 86_400_000).text);
    expect(seen.size).toBe(TIPS.length);
  });

  it("queues one a day, matching what the app would show", () => {
    const reminders = tipReminders(at(2026, 8, 8));
    expect(reminders.length).toBeGreaterThan(10);
    const first = reminders[0]!;
    expect(first.body).toBe(tipOfTheDay(first.send_at).text);
  });
});

describe("the combined schedule", () => {
  const now = at(2026, 8, 8);
  const statuses = [billStatus(bill(), [], now)];
  const accounts = [account()];

  it("includes only what's switched on", () => {
    const billsOnly = buildSchedule({
      statuses, accounts, salaryLanded: true,
      enabled: { bills: true, statements: false, tips: false }, now,
    });
    expect(billsOnly.every((r) => r.tag.startsWith("bill-"))).toBe(true);

    const none = buildSchedule({
      statuses, accounts, salaryLanded: true,
      enabled: { bills: false, statements: false, tips: false }, now,
    });
    expect(none).toHaveLength(0);
  });

  it("comes back in send order", () => {
    const all = buildSchedule({
      statuses, accounts, salaryLanded: true,
      enabled: { bills: true, statements: true, tips: true }, now,
    });
    const times = all.map((r) => r.send_at);
    expect([...times].sort((a, b) => a - b)).toEqual(times);
  });

  it("stays within the upload cap", () => {
    const many = Array.from({ length: 40 }, (_, i) =>
      billStatus(bill({ id: `b${i}` }), [], now));
    expect(buildSchedule({
      statuses: many, accounts, salaryLanded: true,
      enabled: { bills: true, statements: true, tips: true }, now,
    }).length).toBeLessThanOrEqual(200);
  });
});
