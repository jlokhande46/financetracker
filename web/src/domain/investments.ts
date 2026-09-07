import type { Account, Paise } from "./types";

/**
 * Manually-tracked holdings — mutual funds, stocks, FDs, gold, PPF/NPS.
 *
 * No live NAV fetch, deliberately. Every Indian quote API wants a key, most
 * rate-limit, and a portfolio that silently stops updating is worse than one
 * you knowingly refresh yourself. The user updates `currentValue` when they
 * check their portfolio; `lastUpdated` says how stale the figure is, which is
 * the honest version of the same information.
 */

export type InvestmentType = "mf" | "stock" | "fd" | "gold" | "ppf_nps" | "crypto" | "other";

export const INVESTMENT_META: Record<InvestmentType, { label: string; color: string }> = {
  mf: { label: "Mutual Fund", color: "#00D09C" },
  stock: { label: "Stocks", color: "#3B82F6" },
  fd: { label: "Fixed Deposit", color: "#F59E0B" },
  gold: { label: "Gold", color: "#EAB308" },
  ppf_nps: { label: "PPF / NPS", color: "#8B5CF6" },
  crypto: { label: "Crypto", color: "#F97316" },
  other: { label: "Other", color: "#94A3B8" },
};

export const INVESTMENT_TYPES = Object.keys(INVESTMENT_META) as InvestmentType[];

export interface InvestmentHolding {
  id: string;
  name: string;
  type: InvestmentType;
  currentValue: Paise;
  /** What was put in. Zero means "not tracking cost", and returns are hidden. */
  investedAmount: Paise;
  lastUpdated: number;
  note?: string;
  createdAt: number;
}

export interface HoldingReturns {
  gain: Paise;
  /** Null when there's no cost basis to compare against. */
  percent: number | null;
  /** Days since the value was last refreshed. */
  staleDays: number;
}

const DAY = 86_400_000;

/** Past this, the figure is old enough that the UI should say so. */
export const STALE_AFTER_DAYS = 45;

export function holdingReturns(h: InvestmentHolding, now: number = Date.now()): HoldingReturns {
  const gain = h.currentValue - h.investedAmount;
  return {
    gain,
    percent: h.investedAmount > 0 ? (gain / h.investedAmount) * 100 : null,
    staleDays: Math.max(0, Math.floor((now - h.lastUpdated) / DAY)),
  };
}

// ── net worth ────────────────────────────────────────────────────────────────

export interface NetWorth {
  /** Deposit-account balances. */
  cash: Paise;
  investments: Paise;
  /** Credit-card outstanding. */
  liabilities: Paise;
  assets: Paise;
  netWorth: Paise;
  /** Total unrealised gain across holdings with a cost basis. */
  investmentGain: Paise;
  /** How much of the portfolio has a cost basis, for honesty about the gain. */
  costBasisCoverage: number;
}

/**
 * Assets (cash + holdings) minus liabilities (card outstanding).
 *
 * Cards track outstanding as a positive number — `recalculateBalances` builds
 * them that way — so they subtract here rather than being negative assets.
 */
export function computeNetWorth(
  accounts: Account[],
  holdings: InvestmentHolding[],
): NetWorth {
  const active = accounts.filter((a) => a.isActive);
  const cash = active.filter((a) => a.type !== "credit")
    .reduce((sum, a) => sum + a.balance, 0);
  const liabilities = active.filter((a) => a.type === "credit")
    .reduce((sum, a) => sum + a.balance, 0);

  const investments = holdings.reduce((sum, h) => sum + h.currentValue, 0);
  const withCost = holdings.filter((h) => h.investedAmount > 0);
  const investmentGain = withCost.reduce((sum, h) => sum + h.currentValue - h.investedAmount, 0);
  const covered = withCost.reduce((sum, h) => sum + h.currentValue, 0);

  const assets = cash + investments;
  return {
    cash, investments, liabilities, assets,
    netWorth: assets - liabilities,
    investmentGain,
    costBasisCoverage: investments > 0 ? covered / investments : 0,
  };
}

// ── history ──────────────────────────────────────────────────────────────────

export interface NetWorthPoint {
  /** "2026-09" — one per calendar month. */
  month: string;
  value: Paise;
}

export function monthKey(ms: number = Date.now()): string {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

/** Two years is plenty of trend for a chart, and keeps the stored blob small. */
const MAX_POINTS = 24;

/**
 * Fold today's figure into the history, overwriting this month's point.
 *
 * A month holds one value — the latest — rather than a reading per app launch.
 * A trend line is about the shape across months; intra-month noise from paying
 * a card and then being paid would just make it unreadable.
 */
export function recordNetWorth(
  history: NetWorthPoint[],
  value: Paise,
  now: number = Date.now(),
): NetWorthPoint[] {
  const key = monthKey(now);
  const rest = history.filter((p) => p.month !== key);
  const next = [...rest, { month: key, value }]
    .sort((a, b) => a.month.localeCompare(b.month));
  return next.slice(-MAX_POINTS);
}

export interface NetWorthTrend {
  points: NetWorthPoint[];
  /** Change against the earliest point shown; null with fewer than two months. */
  change: Paise | null;
  changePercent: number | null;
}

export function netWorthTrend(history: NetWorthPoint[], months = 12): NetWorthTrend {
  const points = history.slice(-months);
  if (points.length < 2) return { points, change: null, changePercent: null };

  const first = points[0]!.value;
  const last = points[points.length - 1]!.value;
  const change = last - first;
  return {
    points,
    change,
    // A percentage against a negative or zero starting point is meaningless —
    // "up 300% from minus ₹40,000" says nothing useful.
    changePercent: first > 0 ? (change / first) * 100 : null,
  };
}
