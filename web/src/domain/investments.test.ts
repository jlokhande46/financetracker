import { describe, expect, it } from "vitest";
import { rupees, type Account } from "./types";
import {
  computeNetWorth, holdingReturns, monthKey, netWorthTrend, recordNetWorth,
  type InvestmentHolding, type NetWorthPoint,
} from "./investments";

const at = (y: number, m: number, d: number) => new Date(y, m - 1, d, 12).getTime();

const account = (over: Partial<Account> = {}): Account => ({
  id: crypto.randomUUID(), name: "A", bankName: "Bank", type: "savings",
  balance: 0, openingBalance: 0, colorHex: "#000", isActive: true, createdAt: 0,
  ...over,
});

const holding = (over: Partial<InvestmentHolding> = {}): InvestmentHolding => ({
  id: crypto.randomUUID(), name: "Nifty index", type: "mf",
  currentValue: rupees(120000), investedAmount: rupees(100000),
  lastUpdated: at(2026, 9, 1), createdAt: 0,
  ...over,
});

describe("holding returns", () => {
  it("reports gain and percentage against the cost basis", () => {
    const r = holdingReturns(holding(), at(2026, 9, 1));
    expect(r.gain).toBe(rupees(20000));
    expect(r.percent).toBeCloseTo(20);
  });

  it("reports a loss as a negative", () => {
    const r = holdingReturns(holding({ currentValue: rupees(80000) }), at(2026, 9, 1));
    expect(r.gain).toBe(rupees(-20000));
    expect(r.percent).toBeCloseTo(-20);
  });

  it("gives no percentage without a cost basis rather than dividing by zero", () => {
    // Gold bought years ago at a price nobody remembers still has a value worth
    // tracking; it just has no meaningful return.
    const r = holdingReturns(holding({ investedAmount: 0 }), at(2026, 9, 1));
    expect(r.percent).toBeNull();
  });

  it("reports how stale the figure is", () => {
    // No live NAV fetch, so how old the number is IS the information.
    expect(holdingReturns(holding(), at(2026, 10, 16)).staleDays).toBe(45);
    expect(holdingReturns(holding(), at(2026, 9, 1)).staleDays).toBe(0);
  });
});

describe("net worth", () => {
  it("is assets minus card outstanding", () => {
    const accounts = [
      account({ type: "savings", balance: rupees(250000) }),
      account({ type: "savings", balance: rupees(50000) }),
      account({ type: "credit", balance: rupees(35000) }),
    ];
    const n = computeNetWorth(accounts, [holding()]);
    expect(n.cash).toBe(rupees(300000));
    expect(n.investments).toBe(rupees(120000));
    expect(n.liabilities).toBe(rupees(35000));
    expect(n.assets).toBe(rupees(420000));
    expect(n.netWorth).toBe(rupees(385000));
  });

  it("subtracts card outstanding rather than adding it as a negative asset", () => {
    // recalculateBalances stores card outstanding as a positive number. Adding
    // it would double the debt in the wrong direction.
    const n = computeNetWorth([account({ type: "credit", balance: rupees(35000) })], []);
    expect(n.netWorth).toBe(rupees(-35000));
  });

  it("ignores closed accounts", () => {
    const n = computeNetWorth([
      account({ balance: rupees(100000) }),
      account({ balance: rupees(999999), isActive: false }),
    ], []);
    expect(n.cash).toBe(rupees(100000));
  });

  it("counts gain only from holdings that have a cost basis", () => {
    const n = computeNetWorth([], [
      holding({ currentValue: rupees(120000), investedAmount: rupees(100000) }),
      holding({ currentValue: rupees(200000), investedAmount: 0 }),
    ]);
    expect(n.investments).toBe(rupees(320000));
    expect(n.investmentGain).toBe(rupees(20000));
    // And says how much of the portfolio that gain actually speaks for.
    expect(n.costBasisCoverage).toBeCloseTo(120000 / 320000);
  });

  it("handles an empty portfolio", () => {
    const n = computeNetWorth([], []);
    expect(n).toMatchObject({ netWorth: 0, investments: 0, costBasisCoverage: 0 });
  });
});

describe("net worth history", () => {
  it("keeps one point per month, overwriting the current one", () => {
    // Paying a card and then being paid inside one month shouldn't produce two
    // points and a sawtooth trend line.
    let h: NetWorthPoint[] = [];
    h = recordNetWorth(h, rupees(100000), at(2026, 9, 3));
    h = recordNetWorth(h, rupees(140000), at(2026, 9, 20));
    expect(h).toEqual([{ month: "2026-09", value: rupees(140000) }]);
  });

  it("appends across months in order", () => {
    let h: NetWorthPoint[] = [];
    h = recordNetWorth(h, rupees(100000), at(2026, 8, 3));
    h = recordNetWorth(h, rupees(120000), at(2026, 9, 3));
    expect(h.map((p) => p.month)).toEqual(["2026-08", "2026-09"]);
  });

  it("caps the stored history at two years", () => {
    let h: NetWorthPoint[] = [];
    for (let i = 0; i < 40; i++) {
      h = recordNetWorth(h, rupees(1000 * i), at(2024, 1, 1) + i * 31 * 86_400_000);
    }
    expect(h.length).toBeLessThanOrEqual(24);
  });

  it("builds a month key that is sortable as a string", () => {
    expect(monthKey(at(2026, 9, 5))).toBe("2026-09");
    expect(monthKey(at(2026, 12, 5)) > monthKey(at(2026, 9, 5))).toBe(true);
  });
});

describe("net worth trend", () => {
  const history: NetWorthPoint[] = [
    { month: "2026-07", value: rupees(200000) },
    { month: "2026-08", value: rupees(230000) },
    { month: "2026-09", value: rupees(250000) },
  ];

  it("measures change across the window shown", () => {
    const t = netWorthTrend(history);
    expect(t.change).toBe(rupees(50000));
    expect(t.changePercent).toBeCloseTo(25);
  });

  it("gives no change with a single month", () => {
    const t = netWorthTrend(history.slice(0, 1));
    expect(t.change).toBeNull();
    expect(t.changePercent).toBeNull();
  });

  it("suppresses a percentage measured from zero or debt", () => {
    // "Up 300% from minus ₹40,000" is a number that means nothing.
    const t = netWorthTrend([
      { month: "2026-07", value: rupees(-40000) },
      { month: "2026-08", value: rupees(80000) },
    ]);
    expect(t.change).toBe(rupees(120000));
    expect(t.changePercent).toBeNull();
  });

  it("shows at most the requested window", () => {
    const long = Array.from({ length: 20 }, (_, i) => ({
      month: `2025-${String((i % 12) + 1).padStart(2, "0")}`, value: rupees(i * 1000),
    }));
    expect(netWorthTrend(long, 12).points).toHaveLength(12);
  });
});
