/**
 * Money tips shown on the dashboard and pushed as the daily nudge.
 *
 * Picked deterministically from the date rather than at random, so the tip is
 * stable through a day — one that reshuffles on every render reads as noise,
 * and the push notification has to match what the app shows.
 */

export interface Tip {
  text: string;
  /** Where it came from, so nothing reads as an invented statistic. */
  kind: "habit" | "rule" | "india" | "trap";
}

export const TIPS: Tip[] = [
  { kind: "rule", text: "The 50/30/20 split: half your take-home on needs, 30% on wants, 20% to savings. Miss it by a little and you're still ahead of not measuring." },
  { kind: "habit", text: "Automate the transfer to savings for the day after payday. Saving what's left at month end almost never works." },
  { kind: "trap", text: "A credit card's minimum due is designed to keep you paying interest. Clearing the full statement is the only way to use the free credit period." },
  { kind: "india", text: "UPI made small spends invisible — ₹80 twelve times a month is ₹960. Check your under-₹200 transactions; that's usually where the leak is." },
  { kind: "rule", text: "Keep 6 months of essential expenses as an emergency fund before chasing returns. Liquidity beats yield when you actually need the money." },
  { kind: "trap", text: "No-cost EMI isn't free — the interest is usually baked into the price as a discount you'd have got for paying upfront." },
  { kind: "habit", text: "Review subscriptions quarterly. The ones that hurt are the small monthly charges you stopped noticing." },
  { kind: "india", text: "Section 80C caps at ₹1.5 lakh. If you're in the old regime and not using it fully, that's tax you're choosing to pay." },
  { kind: "rule", text: "Before an impulse buy, wait 48 hours. Most wants don't survive it; the ones that do were probably worth it." },
  { kind: "habit", text: "Pay yourself first: treat savings as a bill with a due date, not as whatever is left over." },
  { kind: "trap", text: "Card reward points are worth roughly 25 paise each on most Indian cards. Spending ₹5,000 to earn 500 points is a bad trade." },
  { kind: "india", text: "An SIP's advantage is that it removes the decision. Timing the market is a skill most professional funds don't reliably have either." },
  { kind: "rule", text: "Keep credit utilisation under 30% of your limit. It's a large slice of your credit score and costs nothing to manage." },
  { kind: "habit", text: "Track for one month before setting budgets. Guessing your own spending is how budgets end up unrealistic and abandoned." },
  { kind: "trap", text: "Free trials that need a card are betting you'll forget. Set a reminder for the day before it converts." },
  { kind: "india", text: "Health insurance premiums rise with age and pre-existing conditions. Buying earlier costs less over a lifetime, not more." },
  { kind: "habit", text: "Round up: when a bill comes in under budget, move the difference to savings the same day rather than absorbing it." },
  { kind: "rule", text: "Clear debt costing more than ~10% before investing. A 14% card balance beats almost any return you'll get elsewhere." },
  { kind: "trap", text: "Lifestyle creep is the quiet one. When income rises, raise savings by the same proportion before adjusting spending." },
  { kind: "india", text: "A statement's 'total amount due' includes everything since the last cycle — check it against your own log before paying blind." },
  { kind: "habit", text: "One no-spend day a week is easier to sustain than a permanent cut, and it makes the routine spending visible." },
  { kind: "rule", text: "Insurance is for catastrophes, not for small losses. Cover what would actually break you and self-insure the rest." },
];

/** Days since the epoch, in local time. */
function dayNumber(now: number): number {
  const d = new Date(now);
  return Math.floor(new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() / 86_400_000);
}

/** The tip for a given day. Same day, same tip — on every device. */
export function tipOfTheDay(now: number = Date.now()): Tip {
  return TIPS[Math.abs(dayNumber(now)) % TIPS.length]!;
}
