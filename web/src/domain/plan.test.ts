import { describe, expect, it } from "vitest";
import { rupees, type Transaction } from "./types";
import { budgetStatus, budgetStatuses, TOTAL_BUDGET_SLUG, type Budget } from "./budgets";
import { goalStatus, goalStatuses, type Goal } from "./goals";

const at = (y: number, m: number, d: number, h = 12) => new Date(y, m - 1, d, h).getTime();
const AUG = at(2026, 8, 1);

function txn(over: Partial<Transaction> = {}): Transaction {
  return {
    id: crypto.randomUUID(), amount: rupees(1000), type: "debit",
    merchantRaw: "X", merchantName: "X", categorySlug: "food",
    date: at(2026, 8, 5), source: "sms", confidence: 1, isConfirmed: true,
    isRecurring: false, tags: [], createdAt: Date.now(),
    ...over,
  };
}

const budget = (over: Partial<Budget> = {}): Budget => ({
  id: "bg1", categorySlug: "food", limit: rupees(10000), createdAt: AUG, ...over,
});

describe("budgets", () => {
  it("counts only this month's debits in the category", () => {
    const rows = [
      txn({ amount: rupees(3000) }),
      txn({ amount: rupees(500), categorySlug: "travel" }),   // other category
      txn({ amount: rupees(900), type: "credit" }),           // a refund, not spend
      txn({ amount: rupees(4000), date: at(2026, 7, 5) }),    // last month
    ];
    expect(budgetStatus(budget(), rows, AUG, at(2026, 8, 10)).spent).toBe(rupees(3000));
  });

  it("excludes card payments from a total budget", () => {
    // A ₹35,000 statement settlement moves money, it doesn't spend it. Counting
    // it would blow the budget the moment the card is paid.
    const rows = [
      txn({ amount: rupees(3000) }),
      txn({ amount: rupees(35000), categorySlug: "cc_payment" }),
      txn({ amount: rupees(5000), categorySlug: "transfer" }),
    ];
    const s = budgetStatus(budget({ categorySlug: TOTAL_BUDGET_SLUG }), rows, AUG, at(2026, 8, 10));
    expect(s.spent).toBe(rupees(3000));
  });

  it("reads pacing, not just the total", () => {
    // ₹8,000 of ₹10,000 is fine on the 28th and alarming on the 9th.
    const rows = [txn({ amount: rupees(8000), date: at(2026, 8, 5) })];
    expect(budgetStatus(budget(), rows, AUG, at(2026, 8, 9)).state).toBe("warning");
    expect(budgetStatus(budget(), rows, AUG, at(2026, 8, 28)).state).toBe("under");
  });

  it("goes over once the limit is passed", () => {
    const s = budgetStatus(budget(), [txn({ amount: rupees(12000) })], AUG, at(2026, 8, 20));
    expect(s.state).toBe("over");
    expect(s.remaining).toBe(rupees(-2000));
    expect(s.dailyAllowance).toBe(0);
  });

  it("divides what's left across the days that remain", () => {
    // ₹6,000 left with 11 days to go on the 20th of a 31-day month.
    const s = budgetStatus(budget(), [txn({ amount: rupees(4000) })], AUG, at(2026, 8, 20));
    expect(s.dailyAllowance).toBe(Math.floor(rupees(6000) / 11));
  });

  it("projects the month-end total from the run rate", () => {
    // ₹5,000 in 10 days of a 31-day month.
    const s = budgetStatus(budget(), [txn({ amount: rupees(5000) })], AUG, at(2026, 8, 10));
    expect(s.projectedSpend).toBe(Math.round(rupees(5000) / 10 * 31));
  });

  it("treats a past month as fully elapsed rather than dividing by zero", () => {
    const s = budgetStatus(budget(), [txn({ amount: rupees(4000) })], AUG, at(2026, 11, 10));
    expect(s.expectedFraction).toBe(1);
    expect(Number.isFinite(s.projectedSpend)).toBe(true);
  });

  it("sorts the most-consumed budget first", () => {
    const rows = [txn({ amount: rupees(9000) }), txn({ amount: rupees(200), categorySlug: "travel" })];
    const list = budgetStatuses(
      [budget(), budget({ id: "bg2", categorySlug: "travel", limit: rupees(10000) })],
      rows, AUG, at(2026, 8, 10),
    );
    expect(list[0]!.budget.categorySlug).toBe("food");
  });
});

describe("goals", () => {
  const goal = (over: Partial<Goal> = {}): Goal => ({
    id: "g1", name: "Emergency fund", targetAmount: rupees(300000), savedAmount: rupees(60000),
    colorHex: "#10B981", createdAt: at(2026, 1, 1), targetDate: at(2026, 12, 31),
    ...over,
  });

  it("reports the monthly contribution needed to land on target", () => {
    // ₹2,40,000 to go across 4 whole months.
    const s = goalStatus(goal(), at(2026, 8, 15));
    expect(s.monthsLeft).toBe(4);
    expect(s.requiredPerMonth).toBe(rupees(60000));
  });

  it("puts the whole remainder on now when no full month is left", () => {
    // Dividing by zero months would otherwise report Infinity.
    const s = goalStatus(goal({ targetDate: at(2026, 8, 31) }), at(2026, 8, 15));
    expect(s.monthsLeft).toBe(0);
    expect(s.requiredPerMonth).toBe(rupees(240000));
  });

  it("flags a goal whose progress lags its timeline", () => {
    // 20% saved with about 60% of the year gone.
    expect(goalStatus(goal(), at(2026, 8, 15)).state).toBe("behind");
  });

  it("calls a goal on track when progress keeps up", () => {
    expect(goalStatus(goal({ savedAmount: rupees(200000) }), at(2026, 8, 15)).state).toBe("onTrack");
  });

  it("recognises an achieved goal even past its deadline", () => {
    const s = goalStatus(goal({ savedAmount: rupees(300000) }), at(2027, 3, 1));
    expect(s.state).toBe("achieved");
    expect(s.fraction).toBe(1);
    expect(s.remaining).toBe(0);
  });

  it("marks an unmet goal overdue after the deadline", () => {
    expect(goalStatus(goal(), at(2027, 3, 1)).state).toBe("overdue");
  });

  it("caps progress at 100% when oversaved", () => {
    expect(goalStatus(goal({ savedAmount: rupees(400000) }), at(2026, 8, 15)).fraction).toBe(1);
  });

  it("tracks progress without a deadline and asks for no monthly figure", () => {
    const s = goalStatus(goal({ targetDate: undefined }), at(2026, 8, 15));
    expect(s.monthsLeft).toBeNull();
    expect(s.requiredPerMonth).toBeNull();
    expect(s.state).toBe("onTrack");
  });

  it("hides archived goals and puts the neediest first", () => {
    const list = goalStatuses([
      goal({ id: "done", savedAmount: rupees(300000) }),
      goal({ id: "late", targetDate: at(2026, 6, 1) }),
      goal({ id: "gone", isArchived: true }),
    ], at(2026, 8, 15));
    expect(list.map((s) => s.goal.id)).toEqual(["late", "done"]);
  });
});
