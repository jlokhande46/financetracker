import { useCallback, useEffect, useMemo, useState } from "react";
import { db, fetchTransactionPage, type MerchantRule } from "../db/db";
import { recalculateBalances } from "../ingest/ingest";
import { merchantRuleKey } from "../categorization/merchantNormalizer";
import { relativeDay } from "../ui/format";
import type { Account, Paise, Transaction } from "../domain/types";

const PAGE_SIZE = 50;

export interface DayGroup {
  key: string;
  rows: Transaction[];
  debitTotal: Paise;
  creditTotal: Paise;
}

/**
 * Groups rows into day sections and pre-computes each section's totals.
 *
 * The Swift version summed these inside a pinned header, which SwiftUI
 * re-evaluated on every scroll frame. Doing it once here keeps the header a
 * pure render. Day labels are memoised by start-of-day because Intl formatting
 * is not cheap and the naive version called it once per row.
 */
export function groupByDay(rows: Transaction[]): DayGroup[] {
  const labelCache = new Map<number, string>();
  const order: string[] = [];
  const buckets = new Map<string, Transaction[]>();

  for (const t of rows) {
    const d = new Date(t.date);
    const dayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    let label = labelCache.get(dayStart);
    if (label === undefined) {
      label = relativeDay(t.date);
      labelCache.set(dayStart, label);
    }
    if (!buckets.has(label)) {
      buckets.set(label, []);
      order.push(label);
    }
    buckets.get(label)!.push(t);
  }

  return order.map((key) => {
    const groupRows = buckets.get(key)!;
    let debitTotal = 0, creditTotal = 0;
    for (const t of groupRows) {
      if (t.type === "debit") debitTotal += t.amount;
      else creditTotal += t.amount;
    }
    return { key, rows: groupRows, debitTotal, creditTotal };
  });
}

/** Paginated transaction feed backed by the IndexedDB date index. */
export function useTransactionFeed() {
  const [rows, setRows] = useState<Transaction[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<string | null>(null);

  const reload = useCallback(async () => {
    setLoading(true);
    const page = await fetchTransactionPage(undefined, PAGE_SIZE);
    setRows(page.rows);
    setHasMore(page.hasMore);
    setLoading(false);
  }, []);

  useEffect(() => { void reload(); }, [reload]);

  const loadMore = useCallback(async () => {
    if (loadingMore || !hasMore) return;
    setLoadingMore(true);
    const oldest = rows[rows.length - 1]?.date;
    const page = await fetchTransactionPage(oldest, PAGE_SIZE);
    // Append rather than re-sorting everything: fetchTransactionPage walks
    // strictly backwards in time, so the new rows always belong at the end.
    setRows((prev) => [...prev, ...page.rows]);
    setHasMore(page.hasMore);
    setLoadingMore(false);
  }, [rows, hasMore, loadingMore]);

  // Filtering is in-memory over what's loaded. A search that must span the
  // whole history pulls everything first so results can't silently miss
  // older rows the way a partial view would.
  const [fullSet, setFullSet] = useState<Transaction[] | null>(null);
  const filtering = query.trim().length > 0 || category !== null;

  useEffect(() => {
    if (!filtering) { setFullSet(null); return; }
    let cancelled = false;
    void (async () => {
      const all = await db.transactions.orderBy("date").reverse().toArray();
      if (!cancelled) setFullSet(all.filter((t) => !t.isDeleted && !t.isHidden));
    })();
    return () => { cancelled = true; };
  }, [filtering]);

  const visible = useMemo(() => {
    const source = filtering ? (fullSet ?? []) : rows;
    const q = query.trim().toLowerCase();
    return source.filter((t) => {
      if (category && t.categorySlug !== category) return false;
      if (!q) return true;
      return (
        t.merchantName.toLowerCase().includes(q) ||
        t.merchantRaw.toLowerCase().includes(q) ||
        t.categorySlug.includes(q) ||
        (t.notes?.toLowerCase().includes(q) ?? false)
      );
    });
  }, [rows, fullSet, filtering, query, category]);

  const groups = useMemo(() => groupByDay(visible), [visible]);

  return {
    rows: visible, groups, loading, loadingMore,
    hasMore: hasMore && !filtering,
    loadMore, reload,
    query, setQuery, category, setCategory,
  };
}

/** Every tag ever used, for the review flow's autocomplete. */
export function useKnownTags(): string[] {
  const [tags, setTags] = useState<string[]>([]);
  useEffect(() => {
    void db.transactions.toArray().then((rows) => {
      const set = new Set<string>();
      for (const t of rows) for (const tag of t.tags) set.add(tag);
      setTags([...set].sort());
    });
  }, []);
  return tags;
}

/** Skip a transaction without categorising it — confirmed, but left as-is. */
export async function skipReview(transaction: Transaction): Promise<void> {
  // Confirming without changing the category is a real answer: "the guess was
  // fine". Leaving it pending forever would make the review queue meaningless.
  await db.transactions.put({ ...transaction, isConfirmed: true });
}

/** Everything needing review — confidence below the 0.85 bar. */
export function usePendingReview() {
  const [pending, setPending] = useState<Transaction[]>([]);
  const reload = useCallback(async () => {
    const all = await db.transactions.toArray();
    setPending(
      all.filter((t) => !t.isDeleted && !t.isHidden && !t.isConfirmed && t.confidence < 0.85)
         .sort((a, b) => b.date - a.date),
    );
  }, []);
  useEffect(() => { void reload(); }, [reload]);
  return { pending, reload };
}

export function useAccounts() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const reload = useCallback(async () => {
    setAccounts(await db.accounts.toArray());
  }, []);
  useEffect(() => { void reload(); }, [reload]);
  return { accounts, reload };
}

/** All transactions — analytics needs the full set, not a page. */
export function useAllTransactions() {
  const [all, setAll] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const reload = useCallback(async () => {
    const rows = await db.transactions.toArray();
    setAll(rows.filter((t) => !t.isDeleted && !t.isHidden));
    setLoading(false);
  }, []);
  useEffect(() => { void reload(); }, [reload]);
  return { all, loading, reload };
}

// ── mutations ────────────────────────────────────────────────────────────────

export async function saveTransaction(t: Transaction): Promise<void> {
  await db.transactions.put(t);
  await recalculateBalances();
}

export async function deleteTransaction(id: string): Promise<void> {
  // Soft delete, matching the Swift model — keeps rawContent around so a
  // re-import of the same statement doesn't resurrect the row.
  const existing = await db.transactions.get(id);
  if (!existing) return;
  await db.transactions.put({ ...existing, isDeleted: true });
  await recalculateBalances();
}

/**
 * Confirm a reviewed transaction, optionally teaching the app to categorise
 * this merchant automatically and applying the fix to past rows.
 */
export async function confirmReview(opts: {
  transaction: Transaction;
  newName: string;
  newSlug: string;
  rememberName: boolean;
  rememberCategory: boolean;
  applyToPast: boolean;
  newTags?: string[];
}): Promise<number> {
  const { transaction, newName, newSlug, rememberName, rememberCategory, applyToPast } = opts;

  await db.transactions.put({
    ...transaction,
    merchantName: newName.trim() || transaction.merchantName,
    categorySlug: newSlug,
    tags: opts.newTags ?? transaction.tags,
    isConfirmed: true,
    confidence: 1,
  });

  if (rememberName || rememberCategory) {
    const key = merchantRuleKey(transaction.merchantRaw || transaction.merchantName);
    if (key) {
      const existing = await db.merchantRules.get(key);
      const rule: MerchantRule = {
        key,
        displayName: rememberName ? newName.trim() : (existing?.displayName ?? ""),
        categorySlug: rememberCategory ? newSlug : (existing?.categorySlug ?? newSlug),
        matchCount: (existing?.matchCount ?? 0) + 1,
        updatedAt: Date.now(),
      };
      await db.merchantRules.put(rule);
    }
  }

  let updated = 0;
  if (applyToPast && rememberCategory) {
    const rawKey = transaction.merchantRaw;
    const nameKey = transaction.merchantName;
    const all = await db.transactions.toArray();
    const targets = all.filter(
      (t) => !t.isDeleted && t.id !== transaction.id && t.categorySlug !== newSlug &&
             (t.merchantRaw === rawKey || t.merchantName === nameKey),
    );
    if (targets.length) {
      await db.transactions.bulkPut(targets.map((t) => ({ ...t, categorySlug: newSlug })));
      updated = targets.length;
    }
  }

  await recalculateBalances();
  return updated;
}
