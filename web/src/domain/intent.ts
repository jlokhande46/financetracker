import type { CategoryIntent, Transaction } from "./types";
import { categoryIntent, findCategory, isTransferCategory } from "./categories";

/**
 * Per-transaction Needs / Wants / Savings overrides.
 *
 * The category's own mapping is only ever a default. A ₹900 Swiggy order is a
 * want; the same order on the night nobody could cook is a need, and the whole
 * 50/30/20 frame is worthless if the user can't say so. The Swift build put
 * this on a swipe gesture, and this is the shared logic behind the web version
 * of it.
 */

/** The cycle a tap walks through: default → need → want → saving → default. */
export const INTENT_CYCLE: Array<CategoryIntent | undefined> = [
  undefined, "need", "want", "saving",
];

export function nextIntent(current: CategoryIntent | undefined): CategoryIntent | undefined {
  const at = INTENT_CYCLE.indexOf(current ?? undefined);
  return INTENT_CYCLE[(at + 1) % INTENT_CYCLE.length];
}

/**
 * Whether this row can carry an intent at all.
 *
 * Income and transfers are outside the split — a salary credit isn't a "need",
 * and a card settlement isn't spending. The Swift feed skipped the intent UI
 * for income rows for the same reason; showing a control that can't change any
 * number is worse than showing nothing.
 */
export function supportsIntent(t: Transaction): boolean {
  return t.type === "debit" &&
    !findCategory(t.categorySlug).isIncome &&
    !isTransferCategory(t.categorySlug);
}

/** What this row currently counts as: the override if set, else the category's default. */
export function intentOf(t: Transaction): CategoryIntent | undefined {
  return t.intentOverride ?? categoryIntent(t.categorySlug) ?? undefined;
}

/** True when the user has moved this row off its category's default. */
export function isOverridden(t: Transaction): boolean {
  return t.intentOverride !== undefined &&
    t.intentOverride !== (categoryIntent(t.categorySlug) ?? undefined);
}
