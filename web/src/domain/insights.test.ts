import { describe, expect, it } from "vitest";
import { rupees, type Transaction } from "./types";
import { detectSubscriptions, totalAnnualCost } from "./subscriptions";
import { generateInsights } from "./insights";
import type { Budget } from "./budgets";
import type { Goal } from "./goals";

const at = (y: number, m: number, d: number) => new Date(y, m - 1, d, 12).getTime();
const NOW = at(2026, 9, 20);
const SEP = at(2026, 9, 1);

function txn(over: Partial<Transaction> = {}): Transaction {
  return {
    id: crypto.randomUUID(), amount: rupees(500), type: "debit",
    merchantRaw: "X", merchantName: "X", categorySlug: "food",
    date: at(2026, 9, 5), source: "sms", confidence: 1, isConfirmed: true,
    isRecurring: false, tags: [], createdAt: 0,
    ...over,
  };
}

/** n monthly charges ending in the given month. */
function monthly(name: string, amount: number, count: number, endMonth = 9, slug = "entertainment") {
  return Array.from({ length: count }, (_, i) =>
    txn({
      merchantName: name, merchantRaw: name, categorySlug: slug,
      amount: rupees(amount), date: at(2026, endMonth - (count - 1 - i), 8),
    }),
  );
}

describe("subscription detection", () => {
  it("spots a steady monthly charge", () => {
    const subs = detectSubscriptions(monthly("Netflix", 649, 4), NOW);
    expect(subs).toHaveLength(1);
    expect(subs[0]).toMatchObject({
      merchantName: "Netflix",
      cadence: "monthly",
      typicalAmount: rupees(649),
      occurrences: 4,
    });
    // The annual figure is the number that actually lands.
    expect(subs[0]!.annualCost).toBe(rupees(649 * 12));
  });

  it("needs three charges — two could be coincidence", () => {
    expect(detectSubscriptions(monthly("Netflix", 649, 2), NOW)).toHaveLength(0);
    expect(detectSubscriptions(monthly("Netflix", 649, 3), NOW)).toHaveLength(1);
  });

  it("ignores a merchant whose amounts vary", () => {
    // Groceries at the same shop every month is not a subscription.
    const varied = [
      txn({ merchantName: "BigBasket", amount: rupees(2400), date: at(2026, 7, 8) }),
      txn({ merchantName: "BigBasket", amount: rupees(800), date: at(2026, 8, 8) }),
      txn({ merchantName: "BigBasket", amount: rupees(4100), date: at(2026, 9, 8) }),
    ];
    expect(detectSubscriptions(varied, NOW)).toHaveLength(0);
  });

  it("ignores irregular timing", () => {
    const irregular = [
      txn({ merchantName: "Cafe", amount: rupees(300), date: at(2026, 9, 1) }),
      txn({ merchantName: "Cafe", amount: rupees(300), date: at(2026, 9, 3) }),
      txn({ merchantName: "Cafe", amount: rupees(300), date: at(2026, 9, 18) }),
    ];
    expect(detectSubscriptions(irregular, NOW)).toHaveLength(0);
  });

  it("drops a subscription that has clearly stopped", () => {
    // Last charged in March, checked in September — cancelled.
    const stale = monthly("OldGym", 1500, 4, 3);
    expect(detectSubscriptions(stale, NOW)).toHaveLength(0);
  });

  it("never counts card payments or transfers", () => {
    const payments = monthly("HDFC CC Payment", 35000, 4, 9, "cc_payment");
    expect(detectSubscriptions(payments, NOW)).toHaveLength(0);
  });

  it("ignores credits", () => {
    const salary = monthly("ACME", 150000, 4).map((t) => ({ ...t, type: "credit" as const }));
    expect(detectSubscriptions(salary, NOW)).toHaveLength(0);
  });

  it("recognises weekly and yearly cadences", () => {
    const weekly = Array.from({ length: 5 }, (_, i) =>
      txn({ merchantName: "Milk", amount: rupees(210), date: at(2026, 9, 20) - i * 7 * 86_400_000 }));
    expect(detectSubscriptions(weekly, NOW)[0]?.cadence).toBe("weekly");

    const yearly = Array.from({ length: 3 }, (_, i) =>
      txn({ merchantName: "Domain", amount: rupees(1200), date: at(2026 - (2 - i), 9, 8) }));
    const [sub] = detectSubscriptions(yearly, NOW);
    expect(sub?.cadence).toBe("yearly");
    expect(sub?.annualCost).toBe(rupees(1200));
  });

  it("uses the median so one odd month doesn't skew the amount", () => {
    const withOutlier = [
      ...monthly("Spotify", 119, 4),
      txn({ merchantName: "Spotify", amount: rupees(1428), date: at(2026, 9, 9) }),
    ];
    const [sub] = detectSubscriptions(withOutlier, NOW);
    expect(sub?.typicalAmount).toBe(rupees(119));
  });

  it("ranks by what it costs a year and totals them", () => {
    const subs = detectSubscriptions(
      [...monthly("Netflix", 649, 4), ...monthly("Spotify", 119, 4)], NOW,
    );
    expect(subs.map((s) => s.merchantName)).toEqual(["Netflix", "Spotify"]);
    expect(totalAnnualCost(subs)).toBe(rupees((649 + 119) * 12));
  });
});

describe("insights", () => {
  const empty = { budgets: [] as Budget[], goals: [] as Goal[], month: SEP, now: NOW };

  it("says nothing when there's nothing to say", () => {
    expect(generateInsights({ all: [], ...empty })).toHaveLength(0);
  });

  it("flags wants over target with the amount to trim", () => {
    const all = [
      txn({ categorySlug: "entertainment", amount: rupees(6000) }), // want
      txn({ categorySlug: "rent", amount: rupees(4000) }),          // need
    ];
    const wants = generateInsights({ all, ...empty }).find((i) => i.kind === "wantsOverTarget");
    expect(wants?.headline).toContain("60%");
    expect(wants?.detail).toContain("₹3,000");
  });

  it("flags a category well above its own trailing average", () => {
    // Not a fixed threshold — 'a lot' only means something relative to normal.
    const all = [
      txn({ categorySlug: "travel", amount: rupees(2000), date: at(2026, 6, 5) }),
      txn({ categorySlug: "travel", amount: rupees(2000), date: at(2026, 7, 5) }),
      txn({ categorySlug: "travel", amount: rupees(2000), date: at(2026, 8, 5) }),
      txn({ categorySlug: "travel", amount: rupees(9000), date: at(2026, 9, 5) }),
    ];
    const spike = generateInsights({ all, ...empty }).find((i) => i.kind === "categorySpike");
    expect(spike?.headline).toMatch(/Travel is up \d+%/);
  });

  it("does not call a category's first month a spike", () => {
    const all = [txn({ categorySlug: "travel", amount: rupees(9000), date: at(2026, 9, 5) })];
    expect(generateInsights({ all, ...empty }).some((i) => i.kind === "categorySpike")).toBe(false);
  });

  it("warns when a budget is on pace to overshoot", () => {
    const budgets: Budget[] = [{ id: "b", categorySlug: "food", limit: rupees(5000), createdAt: 0 }];
    // ₹4,000 by the 20th of a 30-day month projects to ₹6,000.
    const all = [txn({ categorySlug: "food", amount: rupees(4000), date: at(2026, 9, 15) })];
    const over = generateInsights({ all, budgets, goals: [], month: SEP, now: NOW })
      .find((i) => i.kind === "budgetProjectedOver");
    expect(over?.headline).toContain("Food");
  });

  it("measures a goal against what's actually spare", () => {
    const goals: Goal[] = [{
      id: "g", name: "Emergency fund", targetAmount: rupees(600000), savedAmount: 0,
      targetDate: at(2027, 3, 1), colorHex: "#10B981", createdAt: at(2026, 1, 1),
    }];
    // ₹50,000 in, ₹45,000 out — only ₹5,000 spare against a six-figure need.
    const all = [
      txn({ type: "credit", categorySlug: "salary", amount: rupees(50000), date: at(2026, 9, 1) }),
      txn({ categorySlug: "rent", amount: rupees(45000), date: at(2026, 9, 2) }),
    ];
    const goal = generateInsights({ all, budgets: [], goals, month: SEP, now: NOW })
      .find((i) => i.kind === "goalShortfall");
    expect(goal?.headline).toContain("Emergency fund");
    expect(goal?.detail).toContain("short by");
  });

  it("surfaces recurring charges once there are a few", () => {
    const all = [...monthly("Netflix", 649, 4), ...monthly("Spotify", 119, 4)];
    const subs = generateInsights({ all, ...empty }).find((i) => i.kind === "subscriptions");
    expect(subs?.headline).toContain("2 recurring charges");
  });

  it("credits a month that came in lower", () => {
    const all = [
      txn({ amount: rupees(10000), date: at(2026, 8, 5) }),
      txn({ amount: rupees(4000), date: at(2026, 9, 5) }),
    ];
    const down = generateInsights({ all, ...empty }).find((i) => i.kind === "spendDown");
    expect(down?.headline).toContain("down 60%");
  });

  it("shows at most four, most important first", () => {
    // Enough signal to trip several rules at once.
    const all = [
      ...monthly("Netflix", 649, 4),
      ...monthly("Spotify", 119, 4),
      txn({ categorySlug: "entertainment", amount: rupees(20000), date: at(2026, 9, 5) }),
      txn({ categorySlug: "travel", amount: rupees(2000), date: at(2026, 7, 5) }),
      txn({ categorySlug: "travel", amount: rupees(2000), date: at(2026, 8, 5) }),
      txn({ categorySlug: "travel", amount: rupees(9000), date: at(2026, 9, 5) }),
    ];
    const insights = generateInsights({ all, ...empty });
    expect(insights.length).toBeLessThanOrEqual(4);
    const priorities = insights.map((i) => i.priority);
    expect([...priorities].sort((a, b) => a - b)).toEqual(priorities);
  });

  it("ignores deleted and hidden transactions", () => {
    const all = [
      txn({ categorySlug: "entertainment", amount: rupees(90000), isDeleted: true }),
      txn({ categorySlug: "entertainment", amount: rupees(90000), isHidden: true }),
    ];
    expect(generateInsights({ all, ...empty })).toHaveLength(0);
  });
});
