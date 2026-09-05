import type { Paise } from "../domain/types";

/**
 * Formatting helpers. All money enters as integer paise and is only turned into
 * a string here — arithmetic never touches a float.
 */

const INR = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  maximumFractionDigits: 0,
});

const INR_PRECISE = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export const HIDDEN = "₹••••";

/** ₹1,23,450 — Indian digit grouping, no decimals. */
export function money(p: Paise, hidden = false): string {
  return hidden ? HIDDEN : INR.format(p / 100);
}

/** ₹1,23,450.75 */
export function moneyPrecise(p: Paise, hidden = false): string {
  return hidden ? HIDDEN : INR_PRECISE.format(p / 100);
}

/** ₹1.2L / ₹12.3K / ₹450 — compact, using Indian units (lakh, crore). */
export function moneyCompact(p: Paise, hidden = false): string {
  if (hidden) return HIDDEN;
  const r = Math.abs(p) / 100;
  const sign = p < 0 ? "-" : "";
  if (r >= 1_00_00_000) return `${sign}₹${(r / 1_00_00_000).toFixed(1)}Cr`;
  if (r >= 1_00_000) return `${sign}₹${(r / 1_00_000).toFixed(1)}L`;
  if (r >= 1_000) return `${sign}₹${(r / 1_000).toFixed(1)}K`;
  return `${sign}₹${Math.round(r)}`;
}

/** Signed for the feed: "+₹5,000" for credits, "₹380" for debits. */
export function signedMoney(p: Paise, type: "debit" | "credit", hidden = false): string {
  if (hidden) return HIDDEN;
  return type === "credit" ? `+${money(p)}` : money(p);
}

const DAY = new Intl.DateTimeFormat("en-IN", { weekday: "long", day: "numeric", month: "short" });
const TIME = new Intl.DateTimeFormat("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
const DATE_FULL = new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short", year: "numeric" });
const MONTH_YEAR = new Intl.DateTimeFormat("en-IN", { month: "long", year: "numeric" });

export const fullDate = (ms: number) => DATE_FULL.format(ms);
export const monthYear = (ms: number) => MONTH_YEAR.format(ms);

const startOfDay = (ms: number) => {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};

/**
 * "Today" / "Yesterday" / "Monday, 12 May" — the feed's day-section header.
 * Callers should memoise by start-of-day; Intl formatting is not free and the
 * Swift version called it once per row, which showed up while scrolling.
 */
export function relativeDay(ms: number, now = Date.now()): string {
  const today = startOfDay(now);
  const day = startOfDay(ms);
  if (day === today) return "Today";
  if (day === today - 86_400_000) return "Yesterday";
  return DAY.format(ms);
}

/** Hide midnight — PDF imports default to 00:00 and it means nothing. */
export function timeOfDay(ms: number): string | null {
  const d = new Date(ms);
  if (d.getHours() === 0 && d.getMinutes() === 0) return null;
  return TIME.format(ms);
}

export function percent(value: number, digits = 0): string {
  return `${value.toFixed(digits)}%`;
}
