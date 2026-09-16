import { describe, expect, it } from "vitest";
import { rupees, type Transaction } from "./types";
import {
  activeFilterCount, EMPTY_FILTER, endOfDay, filterSummary, isFilterActive,
  matchesFilter, startOfDay, type TransactionFilter,
} from "./filters";
import { intentOf, isOverridden, nextIntent, supportsIntent } from "./intent";
import { generateInsights, insightId } from "./insights";

const at = (y: number, m: number, d: number, h = 12) => new Date(y, m - 1, d, h).getTime();

function txn(over: Partial<Transaction> = {}): Transaction {
  return {
    id: crypto.randomUUID(), amount: rupees(1000), type: "debit",
    merchantRaw: "SWIGGY", merchantName: "Swiggy", categorySlug: "food",
    date: at(2026, 9, 5), source: "sms", confidence: 1, isConfirmed: true,
    isRecurring: false, tags: [], createdAt: at(2026, 9, 5),
    ...over,
  };
}

const filter = (over: Partial<TransactionFilter> = {}): TransactionFilter =>
  ({ ...EMPTY_FILTER, ...over });

describe("filter predicate", () => {
  it("passes everything when nothing is set", () => {
    expect(matchesFilter(txn(), EMPTY_FILTER)).toBe(true);
    expect(isFilterActive(EMPTY_FILTER)).toBe(false);
  });

  it("never shows deleted or hidden rows, filter or no filter", () => {
    expect(matchesFilter(txn({ isDeleted: true }), EMPTY_FILTER)).toBe(false);
    expect(matchesFilter(txn({ isHidden: true }), EMPTY_FILTER)).toBe(false);
  });

  it("treats an empty list as 'all', not 'none'", () => {
    // An accidentally-cleared filter must show the ledger, never a blank screen
    // the user has to work out how to escape.
    expect(matchesFilter(txn(), filter({ categories: [], types: [], sources: [] }))).toBe(true);
  });

  it("matches the review queue", () => {
    const pending = txn({ isConfirmed: false, confidence: 0.4 });
    expect(matchesFilter(pending, filter({ needsReviewOnly: true }))).toBe(true);
    expect(matchesFilter(txn(), filter({ needsReviewOnly: true }))).toBe(false);
  });

  it("requires every selected tag, not any of them", () => {
    const both = txn({ tags: ["trip", "reimbursable"] });
    const one = txn({ tags: ["trip"] });
    const f = filter({ tags: ["trip", "reimbursable"] });
    expect(matchesFilter(both, f)).toBe(true);
    expect(matchesFilter(one, f)).toBe(false);
  });

  it("includes the whole of the 'to' day", () => {
    // to: 14 Sep must include a 9pm transaction on the 14th, or the most recent
    // day of any range silently vanishes.
    const evening = txn({ date: at(2026, 9, 14, 21) });
    const f = filter({ from: startOfDay(at(2026, 9, 1)), to: endOfDay(at(2026, 9, 14)) });
    expect(matchesFilter(evening, f)).toBe(true);
    expect(matchesFilter(txn({ date: at(2026, 9, 15, 1) }), f)).toBe(false);
  });

  it("filters on amount bounds inclusively", () => {
    const f = filter({ minAmount: rupees(500), maxAmount: rupees(1000) });
    expect(matchesFilter(txn({ amount: rupees(500) }), f)).toBe(true);
    expect(matchesFilter(txn({ amount: rupees(1000) }), f)).toBe(true);
    expect(matchesFilter(txn({ amount: rupees(1001) }), f)).toBe(false);
  });

  it("searches merchant, category name, tags and notes", () => {
    expect(matchesFilter(txn(), filter({ query: "swig" }))).toBe(true);
    expect(matchesFilter(txn(), filter({ query: "food & dining" }))).toBe(true);
    expect(matchesFilter(txn({ tags: ["office"] }), filter({ query: "offi" }))).toBe(true);
    expect(matchesFilter(txn({ notes: "split with Riya" }), filter({ query: "riya" }))).toBe(true);
    expect(matchesFilter(txn(), filter({ query: "zomato" }))).toBe(false);
  });

  it("combines conditions with AND", () => {
    const f = filter({ types: ["debit"], categories: ["food"], query: "swig" });
    expect(matchesFilter(txn(), f)).toBe(true);
    expect(matchesFilter(txn({ type: "credit" }), f)).toBe(false);
    expect(matchesFilter(txn({ categorySlug: "travel" }), f)).toBe(false);
  });
});

describe("filter summary", () => {
  it("marks tag filters with a #, the one people forget is on", () => {
    expect(filterSummary(filter({ tags: ["trip"] }))).toContain("#trip");
  });

  it("names each active condition", () => {
    const labels = filterSummary(filter({
      query: "swiggy", types: ["debit"], categories: ["food"],
      sources: ["sms"], needsReviewOnly: true,
    }));
    expect(labels).toEqual(['"swiggy"', "Needs review", "Expenses", "Food & Dining", "SMS"]);
  });

  it("counts a tag each, so the badge reflects what's really on", () => {
    expect(activeFilterCount(filter({ tags: ["a", "b"], needsReviewOnly: true }))).toBe(3);
    expect(activeFilterCount(EMPTY_FILTER)).toBe(0);
  });
});

describe("intent override", () => {
  it("cycles default → need → want → saving → default", () => {
    expect(nextIntent(undefined)).toBe("need");
    expect(nextIntent("need")).toBe("want");
    expect(nextIntent("want")).toBe("saving");
    expect(nextIntent("saving")).toBeUndefined();
  });

  it("falls back to the category's own mapping", () => {
    expect(intentOf(txn({ categorySlug: "rent" }))).toBe("need");
    expect(intentOf(txn({ categorySlug: "shopping" }))).toBe("want");
  });

  it("lets the user's answer win", () => {
    const moved = txn({ categorySlug: "shopping", intentOverride: "need" });
    expect(intentOf(moved)).toBe("need");
    expect(isOverridden(moved)).toBe(true);
  });

  it("doesn't call an override that agrees with the default an override", () => {
    // The dot in the chip means "you changed this"; showing it on a row that
    // matches its category would make the marker meaningless.
    expect(isOverridden(txn({ categorySlug: "rent", intentOverride: "need" }))).toBe(false);
  });

  it("offers no intent on income or transfers", () => {
    expect(supportsIntent(txn({ type: "credit", categorySlug: "salary" }))).toBe(false);
    expect(supportsIntent(txn({ categorySlug: "cc_payment" }))).toBe(false);
    expect(supportsIntent(txn({ categorySlug: "food" }))).toBe(true);
  });
});

describe("insight ids", () => {
  it("is stable for the same kind and month", () => {
    expect(insightId("savingsLow", at(2026, 9, 1))).toBe(insightId("savingsLow", at(2026, 9, 20)));
  });

  it("differs by month, so last month's dismissal doesn't hide this month's", () => {
    expect(insightId("savingsLow", at(2026, 9, 1))).not.toBe(insightId("savingsLow", at(2026, 8, 1)));
  });

  it("differs by kind", () => {
    expect(insightId("savingsLow", at(2026, 9, 1))).not.toBe(insightId("topWant", at(2026, 9, 1)));
  });

  it("stamps an id on everything generated", () => {
    const month = at(2026, 9, 1);
    const all = [
      txn({ amount: rupees(80000), type: "credit", categorySlug: "salary", date: at(2026, 9, 1) }),
      txn({ amount: rupees(40000), categorySlug: "shopping", date: at(2026, 9, 3) }),
      txn({ amount: rupees(20000), categorySlug: "entertainment", date: at(2026, 9, 4) }),
    ];
    const insights = generateInsights({ all, budgets: [], goals: [], month, now: at(2026, 9, 20) });
    expect(insights.length).toBeGreaterThan(0);
    for (const i of insights) expect(i.id).toMatch(/^[0-9a-f]{8}$/);
  });
});
