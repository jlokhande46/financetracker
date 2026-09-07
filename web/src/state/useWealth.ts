import { useCallback, useEffect, useMemo, useState } from "react";
import { db } from "../db/db";
import {
  computeNetWorth, monthKey, netWorthTrend, recordNetWorth,
  type InvestmentHolding, type NetWorthPoint,
} from "../domain/investments";
import type { Account, Paise } from "../domain/types";

/**
 * Holdings, net worth, and the monthly trend behind it.
 *
 * The history point for the current month is refreshed every time this loads,
 * so the trend follows real state rather than whenever the app happened to be
 * open. Older months are left alone — they're a record, not a recomputation.
 */
export function useWealth(accounts: Account[]) {
  const [holdings, setHoldings] = useState<InvestmentHolding[]>([]);
  const [history, setHistory] = useState<NetWorthPoint[]>([]);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    const [h, hist] = await Promise.all([
      db.investments.toArray(),
      db.netWorthHistory.toArray(),
    ]);
    setHoldings(h);
    setHistory(hist.sort((a, b) => a.month.localeCompare(b.month)));
    setLoading(false);
  }, []);

  useEffect(() => { void reload(); }, [reload]);

  const netWorth = useMemo(
    () => computeNetWorth(accounts, holdings),
    [accounts, holdings],
  );

  // Snapshot this month once the underlying figures are actually loaded —
  // writing during the initial empty render would stamp a zero over a real
  // month's value.
  useEffect(() => {
    if (loading || accounts.length === 0) return;
    const key = monthKey();
    const existing = history.find((p) => p.month === key);
    if (existing?.value === netWorth.netWorth) return;
    void db.netWorthHistory.put({ month: key, value: netWorth.netWorth })
      .then(() => setHistory((prev) => recordNetWorth(prev, netWorth.netWorth)));
  }, [loading, accounts.length, netWorth.netWorth, history]);

  const trend = useMemo(() => netWorthTrend(history), [history]);

  return { holdings, history, netWorth, trend, loading, reload };
}

export async function saveHolding(holding: InvestmentHolding): Promise<void> {
  await db.investments.put(holding);
}

export async function deleteHolding(id: string): Promise<void> {
  await db.investments.delete(id);
}

/** Refresh just the value, stamping the date — the common monthly update. */
export async function updateHoldingValue(id: string, currentValue: Paise): Promise<void> {
  const existing = await db.investments.get(id);
  if (!existing) return;
  await db.investments.put({ ...existing, currentValue, lastUpdated: Date.now() });
}
