import type { Paise, TransactionType } from "../domain/types";

export interface Classification {
  categorySlug: string;
  confidence: number;
  source: "exactRule" | "keywordMatch" | "fallback";
}

/** Merchant substring -> category slug, ordered by specificity. */
const MERCHANT_RULES: Array<[needle: string, slug: string]> = [
  // Food
  ["swiggy", "food"], ["zomato", "food"], ["blinkit", "food"],
  ["bigbasket", "food"], ["dunzo", "food"], ["dominos", "food"],
  ["mcdonalds", "food"], ["kfc", "food"], ["subway", "food"],
  ["starbucks", "food"], ["cafe", "food"], ["restaurant", "food"],
  ["pizza", "food"], ["biryani", "food"], ["dhaba", "food"],
  // Travel
  ["uber", "travel"], ["ola", "travel"], ["rapido", "travel"],
  ["irctc", "travel"], ["makemytrip", "travel"], ["goibibo", "travel"],
  ["metro", "travel"], ["dmrc", "travel"], ["bmtc", "travel"],
  ["yatra", "travel"], ["cleartrip", "travel"], ["redbus", "travel"],
  // Fuel
  ["bpcl", "fuel"], ["hpcl", "fuel"], ["indian oil", "fuel"],
  ["iocl", "fuel"], ["petrol", "fuel"], ["diesel", "fuel"],
  ["fuel", "fuel"], ["pump", "fuel"],
  // Entertainment
  ["netflix", "entertainment"], ["spotify", "entertainment"],
  ["hotstar", "entertainment"], ["amazon prime", "entertainment"],
  ["youtube premium", "entertainment"], ["zee5", "entertainment"],
  ["sonyliv", "entertainment"], ["voot", "entertainment"],
  ["pvr", "entertainment"], ["inox", "entertainment"],
  ["book my show", "entertainment"], ["bookmyshow", "entertainment"],
  // Shopping
  ["amazon", "shopping"], ["flipkart", "shopping"], ["myntra", "shopping"],
  ["meesho", "shopping"], ["nykaa", "shopping"], ["ajio", "shopping"],
  ["snapdeal", "shopping"], ["jiomart", "shopping"],
  // Bills
  ["electricity", "bills"], ["bescom", "bills"], ["tata power", "bills"],
  ["mahanagar gas", "bills"], ["igl gas", "bills"], ["bsnl", "bills"],
  ["airtel", "bills"], ["jio", "bills"], ["vodafone", "bills"],
  ["water", "bills"], ["internet", "bills"], ["broadband", "bills"],
  // Health
  ["apollo", "health"], ["medplus", "health"], ["pharmeasy", "health"],
  ["1mg", "health"], ["netmeds", "health"], ["hospital", "health"],
  ["clinic", "health"], ["pharmacy", "health"], ["doctor", "health"],
  // Subscriptions
  ["notion", "subscriptions"], ["dropbox", "subscriptions"],
  ["microsoft 365", "subscriptions"], ["adobe", "subscriptions"],
  ["github", "subscriptions"], ["slack", "subscriptions"],
  ["zoom", "subscriptions"], ["chatgpt", "subscriptions"],
  // Investments
  ["zerodha", "investments"], ["groww", "investments"],
  ["mutual fund", "investments"], ["sip", "investments"],
  ["equity", "investments"], ["nse", "investments"],
  // Income
  ["salary", "salary"], ["payroll", "salary"],
  // Transfers / payment gateways
  ["transfer", "transfer"], ["neft", "transfer"], ["rtgs", "transfer"],
  ["imps", "transfer"], ["phonepe", "transfer"], ["gpay", "transfer"],
  ["paytm", "transfer"], ["upi", "transfer"],
  ["payu", "transfer"], ["razorpay", "transfer"], ["cashfree", "transfer"],
  ["billdesk", "transfer"], ["ccavenue", "transfer"],
  // Rent
  ["rent", "rent"], ["nobroker", "rent"], ["magicbricks", "rent"],
  // EMI
  ["emi", "emi"], ["loan", "emi"], ["equated", "emi"],
];

/**
 * Narrations that always mean "paid my card bill". Checked before the
 * amount heuristic, because a ₹26K CC payment would otherwise trip the
 * "large credit == salary" rule and show up as income.
 */
const CC_PAYMENT_MARKERS = [
  "cc payment", "card payment", "bppy cc", "bppy/", "bppy ",
  "payment received", "payment thank you", "payment - thank you",
  "credit card payment", "bill payment received", "auto debit-cc payment",
];

/** Credits at or above this are assumed to be salary when nothing else matched. */
const SALARY_THRESHOLD_PAISE = 10_000_00;

export interface ClassifyInput {
  merchantName: string;
  amount: Paise;
  type: TransactionType;
  /** Full SMS / PDF row. Some markers only appear here, not in the merchant. */
  rawContent?: string;
  /** Category from a saved user rule, if one matched. Wins outright. */
  userRuleSlug?: string | null;
}

/**
 * 5-step cascade, ported from CategoryClassifier.swift:
 *   0. CC-payment shortcut   1.0
 *   1. user rule             1.0
 *   2. built-in keywords     0.92
 *   3. amount heuristic      0.6
 *   4. fallback              0.40  (this is what triggers Review)
 */
export function classify(input: ClassifyInput): Classification {
  const { merchantName, amount, type, rawContent, userRuleSlug } = input;
  const lower = merchantName.toLowerCase();
  const rawLower = (rawContent ?? "").toLowerCase();

  if (type === "credit" &&
      CC_PAYMENT_MARKERS.some((m) => lower.includes(m) || rawLower.includes(m))) {
    return { categorySlug: "cc_payment", confidence: 1.0, source: "keywordMatch" };
  }

  if (userRuleSlug) {
    return { categorySlug: userRuleSlug, confidence: 1.0, source: "exactRule" };
  }

  for (const [needle, slug] of MERCHANT_RULES) {
    if (lower.includes(needle) || rawLower.includes(needle)) {
      return { categorySlug: slug, confidence: 0.92, source: "keywordMatch" };
    }
  }

  if (type === "credit" && amount >= SALARY_THRESHOLD_PAISE) {
    return { categorySlug: "salary", confidence: 0.6, source: "keywordMatch" };
  }
  if (type === "credit") {
    return { categorySlug: "transfer", confidence: 0.55, source: "fallback" };
  }

  return { categorySlug: "others", confidence: 0.4, source: "fallback" };
}
