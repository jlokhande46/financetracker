// Core value types, ported from the Swift Domain/Entities layer.
//
// Money note: Swift used `Decimal` and converted at the SwiftData boundary via
// a lossless string round-trip. JS has no decimal type, and float arithmetic on
// currency is how you end up with 0.1 + 0.2 problems in a finance app. So the
// web port stores money as INTEGER PAISE (1 rupee = 100 paise) everywhere, and
// only converts to a display string at the edge. All arithmetic stays integer.

/** Money in paise. 25000 paise = ₹250.00 */
export type Paise = number;

export const rupees = (r: number): Paise => Math.round(r * 100);
export const toRupees = (p: Paise): number => p / 100;

export type TransactionType = "debit" | "credit";

export type TransactionSource = "sms" | "email" | "pdf" | "aa" | "manual" | "upi";

export const SOURCE_LABEL: Record<TransactionSource, string> = {
  sms: "SMS",
  email: "Email",
  pdf: "Statement",
  aa: "Bank Sync",
  manual: "Manual",
  upi: "UPI",
};

/** The 50/30/20 budgeting frame. */
export type CategoryIntent = "need" | "want" | "saving";

export const INTENT_META: Record<
  CategoryIntent,
  { label: string; targetPercent: number; color: string }
> = {
  need: { label: "Needs", targetPercent: 50, color: "#3B82F6" },
  want: { label: "Wants", targetPercent: 30, color: "#F59E0B" },
  saving: { label: "Savings", targetPercent: 20, color: "#10B981" },
};

export interface Transaction {
  id: string;
  amount: Paise;
  type: TransactionType;
  /** As parsed from SMS/PDF, before normalisation. */
  merchantRaw: string;
  /** Display name, possibly user-renamed. */
  merchantName: string;
  categorySlug: string;
  date: number; // epoch ms
  source: TransactionSource;
  /** 0-1. Below 0.85 and unconfirmed => needs review. */
  confidence: number;
  isConfirmed: boolean;
  isRecurring: boolean;
  tags: string[];
  notes?: string;
  accountId?: string;
  upiRef?: string;
  bankRef?: string;
  /** Original SMS text / PDF row — also the dedup key. */
  rawContent?: string;
  intentOverride?: CategoryIntent;
  createdAt: number;
  isDeleted?: boolean;
  isHidden?: boolean;
}

export const isDebit = (t: Transaction) => t.type === "debit";
export const isCredit = (t: Transaction) => t.type === "credit";
export const needsReview = (t: Transaction) => !t.isConfirmed && t.confidence < 0.85;

export type AccountType = "savings" | "current" | "credit" | "wallet" | "investment";

export const ACCOUNT_TYPE_LABEL: Record<AccountType, string> = {
  savings: "Savings Account",
  current: "Current Account",
  credit: "Credit Card",
  wallet: "Wallet",
  investment: "Investment",
};

export interface Account {
  id: string;
  name: string;
  bankName: string;
  type: AccountType;
  last4?: string;
  /** Derived: openingBalance combined with this account's transactions. */
  balance: Paise;
  /** Starting point the derived balance builds on. User-editable. */
  openingBalance: Paise;
  creditLimit?: Paise;
  colorHex: string;
  isActive: boolean;
  /** Day of month the CC statement is generated (1-31). */
  statementDay?: number;
  /** Day of month the bill is due. */
  dueDay?: number;
  createdAt: number;
}

export interface Category {
  name: string;
  slug: string;
  /** Lucide-style icon name; the UI maps this to a component. */
  icon: string;
  colorHex: string;
  isIncome: boolean;
  isTransfer: boolean;
  sortOrder: number;
}
