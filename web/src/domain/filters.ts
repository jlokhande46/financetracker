import { findCategory } from "./categories";
import { needsReview, SOURCE_LABEL } from "./types";
import type { Paise, Transaction, TransactionSource, TransactionType } from "./types";

/**
 * The feed's filter state, ported from `TransactionFilterSheet.swift`.
 *
 * Every list field is "empty means all", not "empty means nothing" — an
 * accidentally-cleared filter should show the ledger, never an empty screen the
 * user has to work out how to escape.
 */
export interface TransactionFilter {
  query: string;
  types: TransactionType[];
  categories: string[];
  sources: TransactionSource[];
  tags: string[];
  /** The review queue as a filter, so it stays reachable when the banner is gone. */
  needsReviewOnly: boolean;
  from?: number;
  to?: number;
  minAmount?: Paise;
  maxAmount?: Paise;
}

export const EMPTY_FILTER: TransactionFilter = {
  query: "", types: [], categories: [], sources: [], tags: [], needsReviewOnly: false,
};

export function isFilterActive(f: TransactionFilter): boolean {
  return f.query.trim().length > 0 || f.types.length > 0 || f.categories.length > 0 ||
    f.sources.length > 0 || f.tags.length > 0 || f.needsReviewOnly ||
    f.from !== undefined || f.to !== undefined ||
    f.minAmount !== undefined || f.maxAmount !== undefined;
}

/** How many separate conditions are on — the count shown on the Filter button. */
export function activeFilterCount(f: TransactionFilter): number {
  let n = 0;
  if (f.query.trim()) n++;
  if (f.types.length) n++;
  if (f.categories.length) n++;
  if (f.sources.length) n++;
  n += f.tags.length;
  if (f.needsReviewOnly) n++;
  if (f.from !== undefined || f.to !== undefined) n++;
  if (f.minAmount !== undefined || f.maxAmount !== undefined) n++;
  return n;
}

const DATE = new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short" });
const inr = (p: Paise) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 })
    .format(p / 100);

/**
 * One label per active condition, for the banner above the feed.
 *
 * The Swift banner showed `#tag` markers specifically, because a tag filter is
 * the one a user forgets they left on — the rows still look ordinary, there is
 * just mysteriously less of the month than there should be.
 */
export function filterSummary(f: TransactionFilter): string[] {
  const out: string[] = [];
  if (f.query.trim()) out.push(`"${f.query.trim()}"`);
  if (f.needsReviewOnly) out.push("Needs review");
  if (f.types.length === 1) out.push(f.types[0] === "debit" ? "Expenses" : "Income");
  for (const slug of f.categories) out.push(findCategory(slug).name);
  for (const source of f.sources) out.push(SOURCE_LABEL[source]);
  for (const tag of f.tags) out.push(`#${tag}`);
  if (f.from !== undefined || f.to !== undefined) {
    const from = f.from === undefined ? "…" : DATE.format(f.from);
    const to = f.to === undefined ? "…" : DATE.format(f.to);
    out.push(`${from} – ${to}`);
  }
  if (f.minAmount !== undefined || f.maxAmount !== undefined) {
    const min = f.minAmount === undefined ? "…" : inr(f.minAmount);
    const max = f.maxAmount === undefined ? "…" : inr(f.maxAmount);
    out.push(`${min} – ${max}`);
  }
  return out;
}

/** Free-text match across the fields a user would plausibly search by. */
function matchesQuery(t: Transaction, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return (
    t.merchantName.toLowerCase().includes(q) ||
    t.merchantRaw.toLowerCase().includes(q) ||
    findCategory(t.categorySlug).name.toLowerCase().includes(q) ||
    t.categorySlug.includes(q) ||
    t.tags.some((tag) => tag.toLowerCase().includes(q)) ||
    (t.notes?.toLowerCase().includes(q) ?? false)
  );
}

export function matchesFilter(t: Transaction, f: TransactionFilter): boolean {
  if (t.isDeleted || t.isHidden) return false;
  if (f.needsReviewOnly && !needsReview(t)) return false;
  if (f.types.length && !f.types.includes(t.type)) return false;
  if (f.categories.length && !f.categories.includes(t.categorySlug)) return false;
  if (f.sources.length && !f.sources.includes(t.source)) return false;
  // Tags are AND, not OR: picking #trip and #reimbursable means the rows that
  // are both, which is the only reading that makes a two-tag selection useful.
  if (f.tags.length && !f.tags.every((tag) => t.tags.includes(tag))) return false;
  if (f.from !== undefined && t.date < f.from) return false;
  if (f.to !== undefined && t.date > f.to) return false;
  if (f.minAmount !== undefined && t.amount < f.minAmount) return false;
  if (f.maxAmount !== undefined && t.amount > f.maxAmount) return false;
  return matchesQuery(t, f.query);
}

/** End of that calendar day, so "to: 14 Sep" includes everything on the 14th. */
export function endOfDay(ms: number): number {
  const d = new Date(ms);
  d.setHours(23, 59, 59, 999);
  return d.getTime();
}

export function startOfDay(ms: number): number {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}
