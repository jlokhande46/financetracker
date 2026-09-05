import { describe, it, expect } from "vitest";
import { analyseMonth, needsWants, startOfMonth } from "./analysis";
import { rupees, type Transaction } from "./types";

const MAY = new Date(2026, 4, 1).getTime();

function txn(over: Partial<Transaction>): Transaction {
  return {
    id: Math.random().toString(36),
    amount: rupees(100),
    type: "debit",
    merchantRaw: "X",
    merchantName: "X",
    categorySlug: "others",
    date: new Date(2026, 4, 10).getTime(),
    source: "manual",
    confidence: 1,
    isConfirmed: true,
    isRecurring: false,
    tags: [],
    createdAt: Date.now(),
    ...over,
  };
}

describe("analyseMonth", () => {
  it("excludes card payments from income and expenses", () => {
    // The Swift original tested for a slug that didn't exist, so every card
    // bill payment inflated spending. This is the regression guard.
    const a = analyseMonth(MAY, [
      txn({ amount: rupees(1000), type: "debit", categorySlug: "food" }),
      txn({ amount: rupees(35_000), type: "debit", categorySlug: "cc_payment" }),
      txn({ amount: rupees(20_000), type: "credit", categorySlug: "cc_payment" }),
      txn({ amount: rupees(50_000), type: "credit", categorySlug: "salary" }),
    ]);
    expect(a.totalExpenses).toBe(rupees(1000));
    expect(a.totalIncome).toBe(rupees(50_000));
  });

  it("ignores deleted and hidden rows", () => {
    const a = analyseMonth(MAY, [
      txn({ amount: rupees(500), categorySlug: "food" }),
      txn({ amount: rupees(900), categorySlug: "food", isDeleted: true }),
      txn({ amount: rupees(700), categorySlug: "food", isHidden: true }),
    ]);
    expect(a.totalExpenses).toBe(rupees(500));
  });

  it("computes savings rate from income", () => {
    const a = analyseMonth(MAY, [
      txn({ amount: rupees(100_000), type: "credit", categorySlug: "salary" }),
      txn({ amount: rupees(25_000), type: "debit", categorySlug: "rent" }),
    ]);
    expect(a.savings).toBe(rupees(75_000));
    expect(Math.round(a.savingsRate)).toBe(75);
  });

  it("only counts the requested month", () => {
    const a = analyseMonth(MAY, [
      txn({ amount: rupees(500), date: new Date(2026, 4, 10).getTime() }),
      txn({ amount: rupees(900), date: new Date(2026, 3, 10).getTime() }),
    ]);
    expect(a.totalExpenses).toBe(rupees(500));
  });

  it("reports month-over-month change against the previous month", () => {
    const a = analyseMonth(MAY, [
      txn({ amount: rupees(1200), date: new Date(2026, 4, 5).getTime(), categorySlug: "food" }),
      txn({ amount: rupees(1000), date: new Date(2026, 3, 5).getTime(), categorySlug: "food" }),
    ]);
    expect(a.previousMonthExpenses).toBe(rupees(1000));
    expect(Math.round(a.spendChangePercent)).toBe(20);
  });

  it("zero-fills every day of the month for the chart", () => {
    const a = analyseMonth(MAY, [txn({ amount: rupees(500) })]);
    expect(a.dayWiseSpend).toHaveLength(31); // May
    expect(a.dayWiseSpend.filter((d) => d.amount > 0)).toHaveLength(1);
  });

  it("ranks categories and merchants by spend", () => {
    const a = analyseMonth(MAY, [
      txn({ amount: rupees(300), categorySlug: "food", merchantName: "Swiggy" }),
      txn({ amount: rupees(900), categorySlug: "travel", merchantName: "Uber" }),
    ]);
    expect(a.categoryBreakdown[0]!.categorySlug).toBe("travel");
    expect(a.topMerchants[0]!.merchantName).toBe("Uber");
    expect(Math.round(a.categoryBreakdown[0]!.percent)).toBe(75);
  });
});

describe("needsWants", () => {
  it("splits debits across the 50/30/20 frame", () => {
    const b = needsWants([
      txn({ amount: rupees(25_000), categorySlug: "rent" }),        // need
      txn({ amount: rupees(2_000), categorySlug: "shopping" }),     // want
      txn({ amount: rupees(8_000), categorySlug: "investments" }),  // saving
    ]);
    expect(b.need).toBe(rupees(25_000));
    expect(b.want).toBe(rupees(2_000));
    expect(b.saving).toBe(rupees(8_000));
    expect(b.total).toBe(rupees(35_000));
  });

  it("lets a per-transaction override beat the category default", () => {
    const b = needsWants([
      txn({ amount: rupees(1_000), categorySlug: "shopping", intentOverride: "need" }),
    ]);
    expect(b.need).toBe(rupees(1_000));
    expect(b.want).toBe(0);
  });

  it("keeps transfers and card payments out of the split", () => {
    const b = needsWants([
      txn({ amount: rupees(35_000), categorySlug: "cc_payment" }),
      txn({ amount: rupees(5_000), categorySlug: "transfer" }),
    ]);
    expect(b.total).toBe(0);
  });

  it("ignores income", () => {
    const b = needsWants([
      txn({ amount: rupees(100_000), type: "credit", categorySlug: "salary" }),
    ]);
    expect(b.total).toBe(0);
  });
});

describe("startOfMonth", () => {
  it("snaps to the 1st at midnight", () => {
    const d = new Date(startOfMonth(new Date(2026, 4, 17, 13, 45).getTime()));
    expect(d.getDate()).toBe(1);
    expect(d.getHours()).toBe(0);
    expect(d.getMonth()).toBe(4);
  });
});
