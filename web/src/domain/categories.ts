import type { Category, CategoryIntent } from "./types";

/**
 * The 26 system categories, ported 1:1 from CategoryEntity.system so slugs stay
 * compatible with data exported from the Swift app.
 */
export const CATEGORIES: Category[] = [
  { name: "Food & Dining",     slug: "food",          icon: "utensils",     colorHex: "#FF8C42", isIncome: false, isTransfer: false, sortOrder: 1 },
  { name: "Groceries",         slug: "groceries",     icon: "shopping-cart",colorHex: "#22C55E", isIncome: false, isTransfer: false, sortOrder: 2 },
  { name: "Dining Out",        slug: "dining",        icon: "utensils",     colorHex: "#F97316", isIncome: false, isTransfer: false, sortOrder: 3 },
  { name: "Travel",            slug: "travel",        icon: "plane",        colorHex: "#4ECDC4", isIncome: false, isTransfer: false, sortOrder: 4 },
  { name: "Shopping",          slug: "shopping",      icon: "shopping-bag", colorHex: "#A855F7", isIncome: false, isTransfer: false, sortOrder: 5 },
  { name: "Entertainment",     slug: "entertainment", icon: "popcorn",      colorHex: "#F59E0B", isIncome: false, isTransfer: false, sortOrder: 6 },
  { name: "Bills & Utilities", slug: "bills",         icon: "zap",          colorHex: "#3B82F6", isIncome: false, isTransfer: false, sortOrder: 7 },
  { name: "Fuel",              slug: "fuel",          icon: "fuel",         colorHex: "#EF4444", isIncome: false, isTransfer: false, sortOrder: 8 },
  { name: "Health",            slug: "health",        icon: "heart",        colorHex: "#EF4444", isIncome: false, isTransfer: false, sortOrder: 9 },
  { name: "Personal Care",     slug: "personal_care", icon: "scissors",     colorHex: "#EC4899", isIncome: false, isTransfer: false, sortOrder: 10 },
  { name: "Fitness",           slug: "fitness",       icon: "activity",     colorHex: "#10B981", isIncome: false, isTransfer: false, sortOrder: 11 },
  { name: "Pets",              slug: "pets",          icon: "paw-print",    colorHex: "#8B5CF6", isIncome: false, isTransfer: false, sortOrder: 12 },
  { name: "Gifts",             slug: "gifts",         icon: "gift",         colorHex: "#F472B6", isIncome: false, isTransfer: false, sortOrder: 13 },
  { name: "Donations",         slug: "donations",     icon: "hand-heart",   colorHex: "#06B6D4", isIncome: false, isTransfer: false, sortOrder: 14 },
  { name: "Rent",              slug: "rent",          icon: "home",         colorHex: "#8B5CF6", isIncome: false, isTransfer: false, sortOrder: 15 },
  { name: "Subscriptions",     slug: "subscriptions", icon: "repeat",       colorHex: "#EC4899", isIncome: false, isTransfer: false, sortOrder: 16 },
  { name: "EMI",               slug: "emi",           icon: "calendar-clock",colorHex: "#F97316",isIncome: false, isTransfer: false, sortOrder: 17 },
  { name: "Education",         slug: "education",     icon: "graduation-cap",colorHex: "#06B6D4",isIncome: false, isTransfer: false, sortOrder: 18 },
  { name: "Insurance",         slug: "insurance",     icon: "shield",       colorHex: "#84CC16", isIncome: false, isTransfer: false, sortOrder: 19 },
  { name: "Investments",       slug: "investments",   icon: "trending-up",  colorHex: "#00D09C", isIncome: false, isTransfer: false, sortOrder: 20 },
  { name: "Others",            slug: "others",        icon: "circle-ellipsis",colorHex: "#94A3B8",isIncome: false,isTransfer: false, sortOrder: 21 },
  { name: "Salary",            slug: "salary",        icon: "banknote",     colorHex: "#22C55E", isIncome: true,  isTransfer: false, sortOrder: 22 },
  { name: "Freelance",         slug: "freelance",     icon: "laptop",       colorHex: "#4ADE80", isIncome: true,  isTransfer: false, sortOrder: 23 },
  { name: "Refund",            slug: "refund",        icon: "undo",         colorHex: "#34D399", isIncome: true,  isTransfer: false, sortOrder: 24 },
  { name: "Transfer",          slug: "transfer",      icon: "arrow-left-right",colorHex: "#64748B",isIncome:false,isTransfer: true,  sortOrder: 25 },
  { name: "CC Payment",        slug: "cc_payment",    icon: "credit-card",  colorHex: "#A78BFA", isIncome: false, isTransfer: true,  sortOrder: 26 },
];

const BY_SLUG = new Map(CATEGORIES.map((c) => [c.slug, c]));

const OTHERS: Category = {
  name: "Others", slug: "others", icon: "circle-ellipsis",
  colorHex: "#94A3B8", isIncome: false, isTransfer: false, sortOrder: 21,
};

export function findCategory(slug: string): Category {
  return BY_SLUG.get(slug) ?? OTHERS;
}

const NEED_SLUGS = new Set([
  "rent", "bills", "fuel", "health", "emi", "insurance",
  "education", "food", "groceries", "pets",
]);
const SAVING_SLUGS = new Set(["investments", "donations"]);

/**
 * Maps a category to the 50/30/20 frame. Income and transfer categories return
 * null — they aren't part of the spend split.
 */
export function categoryIntent(slug: string): CategoryIntent | null {
  const cat = findCategory(slug);
  if (cat.isIncome || cat.isTransfer) return null;
  if (NEED_SLUGS.has(slug)) return "need";
  if (SAVING_SLUGS.has(slug)) return "saving";
  return "want";
}

/**
 * Categories excluded from income/expense totals.
 *
 * NOTE: the Swift app shipped a bug here for a long time — it tested for
 * "credit-card-payment", a slug that does not exist, so every credit-card bill
 * payment was counted as ordinary spending. The correct slug is "cc_payment".
 */
const TRANSFER_SLUGS = new Set(["transfer", "internal-transfer", "cc_payment"]);
export const isTransferCategory = (slug: string) => TRANSFER_SLUGS.has(slug);
