import type { Paise } from "./types";

/**
 * Savings goals.
 *
 * The number that matters isn't the progress bar, it's "what do I have to put
 * aside each month to actually get there" — so that's what the status computes,
 * and it's what decides whether a goal reads as on track.
 */

export interface Goal {
  id: string;
  name: string;
  targetAmount: Paise;
  savedAmount: Paise;
  /** Epoch ms. Optional — a goal without a deadline just tracks progress. */
  targetDate?: number;
  colorHex: string;
  note?: string;
  isArchived?: boolean;
  createdAt: number;
}

export type GoalState = "achieved" | "onTrack" | "behind" | "overdue";

export interface GoalStatus {
  goal: Goal;
  fraction: number;
  remaining: Paise;
  /** Whole months left, floor 0. Null when the goal has no deadline. */
  monthsLeft: number | null;
  /** What to save monthly to land on target; null without a deadline. */
  requiredPerMonth: Paise | null;
  state: GoalState;
}

export const GOAL_STATE_META: Record<GoalState, { label: string; color: string }> = {
  achieved: { label: "Achieved", color: "var(--income-green)" },
  onTrack: { label: "On track", color: "var(--brand-primary)" },
  behind: { label: "Needs a push", color: "var(--warning-amber)" },
  overdue: { label: "Past deadline", color: "var(--expense-red)" },
};

export function goalStatus(goal: Goal, now: number = Date.now()): GoalStatus {
  const remaining = Math.max(0, goal.targetAmount - goal.savedAmount);
  const fraction = goal.targetAmount > 0
    ? Math.min(1, goal.savedAmount / goal.targetAmount)
    : 0;
  const achieved = remaining === 0 && goal.targetAmount > 0;

  if (goal.targetDate === undefined) {
    return {
      goal, fraction, remaining, monthsLeft: null, requiredPerMonth: null,
      state: achieved ? "achieved" : "onTrack",
    };
  }

  const from = new Date(now), to = new Date(goal.targetDate);
  const rawMonths = (to.getFullYear() - from.getFullYear()) * 12 + (to.getMonth() - from.getMonth());
  const monthsLeft = Math.max(0, rawMonths);
  // With no full month left, the whole remainder is due now — dividing by zero
  // months would otherwise report Infinity.
  const requiredPerMonth = monthsLeft > 0 ? Math.ceil(remaining / monthsLeft) : remaining;

  const elapsedFraction = elapsed(goal.createdAt, goal.targetDate, now);
  const state: GoalState =
    achieved ? "achieved"
    : now > goal.targetDate ? "overdue"
    : fraction + 0.1 < elapsedFraction ? "behind"
    : "onTrack";

  return { goal, fraction, remaining, monthsLeft, requiredPerMonth, state };
}

/** How far through the goal's own timeline we are, 0-1. */
function elapsed(start: number, end: number, now: number): number {
  if (end <= start) return 1;
  return Math.min(1, Math.max(0, (now - start) / (end - start)));
}

export function goalStatuses(goals: Goal[], now: number = Date.now()): GoalStatus[] {
  const rank: Record<GoalState, number> = { overdue: 0, behind: 1, onTrack: 2, achieved: 3 };
  return goals
    .filter((g) => !g.isArchived)
    .map((g) => goalStatus(g, now))
    .sort((a, b) => rank[a.state] - rank[b.state] || b.fraction - a.fraction);
}
