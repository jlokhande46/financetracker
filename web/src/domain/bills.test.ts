import { describe, expect, it } from "vitest";
import { rupees, type Transaction } from "./types";
import {
  billStatus, cycleStart, dateOnDay, dueDescription, nextCycleStart, periodKeyOf,
  sortBillStatuses, type BillPayment, type RecurringBill,
} from "./bills";
import { billCandidates, creditCardBillDates, reminderFrequency, reminderPlan, salaryCredit } from "./billMatching";

const at = (y: number, m: number, d: number, h = 12) => new Date(y, m - 1, d, h).getTime();

function bill(over: Partial<RecurringBill> = {}): RecurringBill {
  return {
    id: "b1", name: "Rent", categorySlug: "rent", expectedAmount: rupees(25000),
    dueDay: 5, frequency: "monthly", anchorMonth: at(2026, 6, 1),
    isActive: true, createdAt: at(2026, 1, 1),
    ...over,
  };
}

function txn(over: Partial<Transaction> = {}): Transaction {
  return {
    id: crypto.randomUUID(), amount: rupees(100), type: "debit",
    merchantRaw: "X", merchantName: "X", categorySlug: "others",
    date: at(2026, 8, 5), source: "sms", confidence: 1, isConfirmed: true,
    isRecurring: false, tags: [], createdAt: Date.now(),
    ...over,
  };
}

describe("day clamping", () => {
  it("clamps a 31st due date into a short month instead of rolling over", () => {
    // new Date(2026, 1, 31) is 3 March. A bill due on the 31st has to land on
    // the 28th, not in the next month.
    const d = new Date(dateOnDay(at(2026, 2, 1), 31));
    expect([d.getMonth(), d.getDate()]).toEqual([1, 28]);
  });

  it("handles February in a leap year", () => {
    const d = new Date(dateOnDay(at(2028, 2, 1), 31));
    expect(d.getDate()).toBe(29);
  });

  it("leaves an in-range day alone", () => {
    expect(new Date(dateOnDay(at(2026, 8, 1), 14)).getDate()).toBe(14);
  });
});

describe("cycle maths", () => {
  it("a monthly bill's cycle is just its month", () => {
    expect(periodKeyOf(cycleStart(bill(), at(2026, 8, 20)))).toBe("2026-08");
  });

  it("a bimonthly bill stays on its anchor's parity", () => {
    // Anchored to June, so June / August / October — never July.
    const gas = bill({ frequency: "bimonthly", anchorMonth: at(2026, 6, 1) });
    expect(periodKeyOf(cycleStart(gas, at(2026, 6, 15)))).toBe("2026-06");
    expect(periodKeyOf(cycleStart(gas, at(2026, 7, 15)))).toBe("2026-06");
    expect(periodKeyOf(cycleStart(gas, at(2026, 8, 1)))).toBe("2026-08");
    expect(periodKeyOf(cycleStart(gas, at(2026, 9, 30)))).toBe("2026-08");
  });

  it("keeps that parity across a year boundary", () => {
    const gas = bill({ frequency: "bimonthly", anchorMonth: at(2026, 6, 1) });
    expect(periodKeyOf(cycleStart(gas, at(2026, 12, 5)))).toBe("2026-12");
    expect(periodKeyOf(cycleStart(gas, at(2027, 1, 5)))).toBe("2026-12");
    expect(periodKeyOf(cycleStart(gas, at(2027, 2, 5)))).toBe("2027-02");
  });

  it("works for dates before the anchor", () => {
    // Floor division has to stay correct for a negative month delta.
    const gas = bill({ frequency: "bimonthly", anchorMonth: at(2026, 6, 1) });
    expect(periodKeyOf(cycleStart(gas, at(2026, 3, 5)))).toBe("2026-02");
    expect(periodKeyOf(cycleStart(gas, at(2026, 5, 5)))).toBe("2026-04");
  });

  it("advances a quarterly bill three months at a time", () => {
    const q = bill({ frequency: "quarterly", anchorMonth: at(2026, 1, 1) });
    expect(periodKeyOf(nextCycleStart(q, at(2026, 2, 5)))).toBe("2026-04");
  });
});

describe("bill status", () => {
  const payment = (periodKey: string): BillPayment => ({
    id: `b1:${periodKey}`, billId: "b1", periodKey,
    paidAt: at(2026, 8, 4), amount: rupees(25000),
  });

  it("is upcoming well before the due date", () => {
    const s = billStatus(bill({ dueDay: 25 }), [], at(2026, 8, 1));
    expect(s.state).toBe("upcoming");
    expect(s.daysUntilDue).toBe(24);
  });

  it("is due soon inside the five-day window", () => {
    expect(billStatus(bill({ dueDay: 25 }), [], at(2026, 8, 22)).state).toBe("dueSoon");
  });

  it("is due today on the day itself", () => {
    const s = billStatus(bill({ dueDay: 25 }), [], at(2026, 8, 25, 23));
    expect(s.state).toBe("dueToday");
    expect(s.daysUntilDue).toBe(0);
  });

  it("is overdue once the date has passed unpaid", () => {
    const s = billStatus(bill({ dueDay: 5 }), [], at(2026, 8, 9));
    expect(s.state).toBe("overdue");
    expect(dueDescription(s)).toBe("4 days late");
  });

  it("rolls the due date forward once this cycle is paid, but still reads as paid", () => {
    // Both halves matter. Rolling forward means the card says "next due in
    // September" instead of sitting on a date already dealt with — but the
    // state has to stay `paid`, or the card flips straight back to "Mark paid"
    // and looks exactly like the tap never registered.
    const s = billStatus(bill(), [payment("2026-08")], at(2026, 8, 10));
    expect(s.periodKey).toBe("2026-09");
    expect(new Date(s.dueDate).getMonth()).toBe(8);
    expect(s.state).toBe("paid");
    expect(s.isPaid).toBe(true);
    expect(s.paidPeriodKey).toBe("2026-08");
  });

  it("exposes the settling payment so an undo targets the right cycle", () => {
    const s = billStatus(bill(), [payment("2026-08")], at(2026, 8, 10));
    expect(s.payment?.periodKey).toBe("2026-08");
    // Undoing s.periodKey would delete a payment that was never made.
    expect(s.paidPeriodKey).not.toBe(s.periodKey);
  });

  it("comes due again in the next cycle", () => {
    // September has no payment, so nothing rolls forward.
    const s = billStatus(bill(), [payment("2026-08")], at(2026, 9, 10));
    expect(s.periodKey).toBe("2026-09");
    expect(s.state).toBe("overdue");
  });

  it("handles two cycles paid in advance", () => {
    const s = billStatus(bill(), [payment("2026-08"), payment("2026-09")], at(2026, 8, 10));
    expect(s.paidPeriodKey).toBe("2026-09");
    expect(s.periodKey).toBe("2026-10");
    expect(s.state).toBe("paid");
  });

  it("rolls a bimonthly bill forward by two months", () => {
    const gas = bill({ frequency: "bimonthly", anchorMonth: at(2026, 6, 1) });
    const paid: BillPayment = { id: "b1:2026-08", billId: "b1", periodKey: "2026-08", paidAt: at(2026, 8, 20), amount: 0 };
    expect(billStatus(gas, [paid], at(2026, 8, 25)).periodKey).toBe("2026-10");
  });

  it("ignores another bill's payments", () => {
    const other: BillPayment = { id: "b2:2026-08", billId: "b2", periodKey: "2026-08", paidAt: 0, amount: 0 };
    expect(billStatus(bill(), [other], at(2026, 8, 10)).isPaid).toBe(false);
  });

  it("sorts the most urgent first", () => {
    const now = at(2026, 8, 10);
    const statuses = [
      billStatus(bill({ id: "a", dueDay: 28 }), [], now),          // upcoming
      billStatus(bill({ id: "b", dueDay: 5 }), [], now),           // overdue
      billStatus(bill({ id: "c", dueDay: 12 }), [], now),          // due soon
    ];
    expect(sortBillStatuses(statuses).map((s) => s.state))
      .toEqual(["overdue", "dueSoon", "upcoming"]);
  });
});

describe("credit-card bill dates", () => {
  it("puts the due date in the next month when it falls on or before the statement day", () => {
    // SBI: bills on the 7th, due on the 21st — same month.
    const sbi = creditCardBillDates(7, 21, at(2026, 8, 10));
    expect(new Date(sbi.dueDate).getMonth()).toBe(7);

    // A card billing on the 25th and due on the 10th settles the NEXT month.
    const rolled = creditCardBillDates(25, 10, at(2026, 8, 26));
    expect(new Date(rolled.dueDate).getMonth()).toBe(8);
  });

  it("matches the user's real cards", () => {
    const icici = creditCardBillDates(16, 30, at(2026, 8, 17));
    expect(new Date(icici.statementDate).getDate()).toBe(16);
    expect(new Date(icici.dueDate).getDate()).toBe(30);
  });

  it("clamps a 30th due date in February", () => {
    const feb = creditCardBillDates(16, 30, at(2026, 2, 17));
    expect(new Date(feb.dueDate).getDate()).toBe(28);
  });
});

describe("payment candidates", () => {
  const status = billStatus(bill({ dueDay: 5, expectedAmount: rupees(25000) }), [], at(2026, 8, 3));

  it("ranks an exact-amount debit near the due date highest", () => {
    const exact = txn({ amount: rupees(25000), date: at(2026, 8, 5), categorySlug: "rent", merchantName: "Rent to landlord" });
    const noise = txn({ amount: rupees(320), date: at(2026, 8, 6), merchantName: "Swiggy" });
    const [best] = billCandidates(status, [noise, exact]);
    expect(best!.transaction.id).toBe(exact.id);
    expect(best!.reason).toContain("exact amount");
  });

  it("excludes credits and rows outside the window", () => {
    const credit = txn({ type: "credit", amount: rupees(25000), date: at(2026, 8, 5) });
    const old = txn({ amount: rupees(25000), date: at(2026, 6, 5) });
    expect(billCandidates(status, [credit, old])).toHaveLength(0);
  });

  it("excludes deleted rows", () => {
    const deleted = txn({ amount: rupees(25000), date: at(2026, 8, 5), isDeleted: true });
    expect(billCandidates(status, [deleted])).toHaveLength(0);
  });

  it("still offers a plausible row when nothing matches strongly", () => {
    // A shortlist for a human, not an auto-matcher — better one extra row than
    // a silently wrong auto-match.
    const loose = txn({ amount: rupees(9999), date: at(2026, 8, 4) });
    expect(billCandidates(status, [loose])).toHaveLength(1);
  });
});

describe("salary-triggered reminders", () => {
  const salary = txn({
    type: "credit", amount: rupees(150000), categorySlug: "salary",
    merchantName: "ACME PAYROLL", date: at(2026, 8, 1),
  });

  it("finds the salary credit for the current month", () => {
    expect(salaryCredit([salary], at(2026, 8, 10))?.id).toBe(salary.id);
  });

  it("picks the largest credit when several look like income", () => {
    const small = txn({ type: "credit", amount: rupees(2000), categorySlug: "salary", date: at(2026, 8, 2) });
    expect(salaryCredit([small, salary], at(2026, 8, 10))?.amount).toBe(rupees(150000));
  });

  it("ignores last month's salary", () => {
    expect(salaryCredit([salary], at(2026, 9, 10))).toBeNull();
  });

  it("stays silent until salary lands", () => {
    const statuses = [billStatus(bill({ dueDay: 5 }), [], at(2026, 8, 10))];
    expect(reminderPlan(statuses, [], at(2026, 8, 10)).message).toBeNull();
  });

  it("nags once salary is in and bills are unpaid", () => {
    const statuses = [billStatus(bill({ dueDay: 12 }), [], at(2026, 8, 10))];
    const plan = reminderPlan(statuses, [salary], at(2026, 8, 10));
    expect(plan.message).toContain("1 bill left to pay");
    expect(plan.totalOutstanding).toBe(rupees(25000));
  });

  it("names the overdue bills specifically", () => {
    const statuses = [billStatus(bill({ name: "Electricity", dueDay: 5 }), [], at(2026, 8, 10))];
    expect(reminderPlan(statuses, [salary], at(2026, 8, 10)).message)
      .toContain("Electricity");
  });

  it("goes quiet once everything is paid", () => {
    // This is the "till all is marked paid" requirement: a settled bill drops
    // out of the outstanding list entirely, so the nagging stops the same day.
    const paid: BillPayment = { id: "b1:2026-08", billId: "b1", periodKey: "2026-08", paidAt: at(2026, 8, 4), amount: rupees(25000) };
    const statuses = [billStatus(bill({ dueDay: 5 }), [paid], at(2026, 8, 10))];
    const plan = reminderPlan(statuses, [salary], at(2026, 8, 10));
    expect(plan.outstanding).toHaveLength(0);
    expect(plan.message).toBeNull();
  });

  it("ramps the cadence as the due date closes in", () => {
    expect(reminderFrequency(14)).toBe(0);
    expect(reminderFrequency(5)).toBe(1);
    expect(reminderFrequency(1)).toBe(2);
    expect(reminderFrequency(0)).toBe(3);
    expect(reminderFrequency(-3)).toBe(3);
  });
});
