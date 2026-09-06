import { db } from "./db";
import { rupees, type Account } from "../domain/types";
import type { BillFrequency, RecurringBill } from "../domain/bills";

/**
 * The user's real cards, carried over from Data/SampleData.swift including the
 * billing cycle days they supplied (HDFC 14/30, ICICI 16/30, SBI 7/21).
 *
 * Opening balances start at zero here rather than inheriting the Swift app's
 * seeded figures — those were sample numbers that never updated, which is what
 * made the iOS net-worth reading fiction. Balances are derived from
 * transactions; set a real opening balance per account if you have one.
 */
const DEFAULT_ACCOUNTS: Omit<Account, "createdAt">[] = [
  { id: "acc-hdfc-savings", name: "HDFC Savings", bankName: "HDFC Bank", type: "savings", last4: "6311", balance: 0, openingBalance: 0, colorHex: "#3B82F6", isActive: true },
  { id: "acc-hdfc-tataneu", name: "HDFC Tata Neu Infinity", bankName: "HDFC Bank", type: "credit", last4: "6624", balance: 0, openingBalance: 0, creditLimit: rupees(5_00_000), colorHex: "#8B5CF6", isActive: true, statementDay: 14, dueDay: 30 },
  { id: "acc-hdfc-regalia", name: "HDFC Regalia Gold", bankName: "HDFC Bank", type: "credit", last4: "4493", balance: 0, openingBalance: 0, creditLimit: rupees(3_00_000), colorHex: "#6366F1", isActive: true, statementDay: 14, dueDay: 30 },
  { id: "acc-icici-sapphiro", name: "ICICI Sapphiro", bankName: "ICICI Bank", type: "credit", last4: "2000", balance: 0, openingBalance: 0, creditLimit: rupees(4_00_000), colorHex: "#F59E0B", isActive: true, statementDay: 16, dueDay: 30 },
  { id: "acc-sbi-cashback", name: "SBI Cashback", bankName: "SBI", type: "credit", last4: "5075", balance: 0, openingBalance: 0, creditLimit: rupees(2_00_000), colorHex: "#10B981", isActive: true, statementDay: 7, dueDay: 21 },
  { id: "acc-federal-savings", name: "Federal Bank Savings", bankName: "Federal Bank", type: "savings", last4: "8708", balance: 0, openingBalance: 0, colorHex: "#06B6D4", isActive: true },
];

/**
 * Adds any missing default account. Existing rows are left alone so a user's
 * edited names, colours and opening balances survive.
 * @returns how many accounts were created
 */
export async function seedDefaultAccounts(): Promise<number> {
  const existing = await db.accounts.toArray();
  const known = new Set(existing.map((a) => a.id));
  const missing = DEFAULT_ACCOUNTS
    .filter((a) => !known.has(a.id))
    .map((a) => ({ ...a, createdAt: Date.now() }));
  if (missing.length) await db.accounts.bulkPut(missing);
  return missing.length;
}

/**
 * The recurring bills the user named: rent, electricity, postpaid and the
 * credit cards monthly; the gas cylinder every second month.
 *
 * Amounts start at zero and due days at a plausible default — both are meant to
 * be edited. Seeding them beats an empty screen that has to be filled in from
 * scratch before anything useful shows up.
 */
const DEFAULT_BILLS: Array<{
  id: string; name: string; categorySlug: string; dueDay: number; frequency: BillFrequency;
}> = [
  { id: "bill-rent", name: "Rent", categorySlug: "rent", dueDay: 5, frequency: "monthly" },
  { id: "bill-electricity", name: "Electricity", categorySlug: "bills", dueDay: 12, frequency: "monthly" },
  { id: "bill-postpaid", name: "Mobile postpaid", categorySlug: "bills", dueDay: 18, frequency: "monthly" },
  { id: "bill-gas", name: "Gas cylinder", categorySlug: "bills", dueDay: 20, frequency: "bimonthly" },
];

/** Deterministic id so re-running never duplicates a card's bill. */
export const cardBillId = (accountId: string) => `bill-card-${accountId}`;

/**
 * Adds any missing recurring bill, including one per credit card so the Cards
 * section and the Bills list are backed by the same paid/unpaid state rather
 * than two views that can disagree.
 * @returns how many bills were created
 */
export async function seedDefaultBills(): Promise<number> {
  const [existing, accounts] = await Promise.all([db.bills.toArray(), db.accounts.toArray()]);
  const known = new Set(existing.map((b) => b.id));
  const now = Date.now();
  const anchorMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).getTime();

  const fresh: RecurringBill[] = [];

  for (const b of DEFAULT_BILLS) {
    if (known.has(b.id)) continue;
    fresh.push({ ...b, expectedAmount: 0, anchorMonth, isActive: true, createdAt: now });
  }

  for (const a of accounts) {
    if (a.type !== "credit" || !a.dueDay) continue;
    const id = cardBillId(a.id);
    if (known.has(id)) continue;
    fresh.push({
      id,
      name: `${a.name} bill`,
      categorySlug: "cc_payment",
      expectedAmount: 0,
      dueDay: a.dueDay,
      frequency: "monthly",
      anchorMonth,
      accountId: a.id,
      isActive: true,
      createdAt: now,
    });
  }

  if (fresh.length) await db.bills.bulkPut(fresh);
  return fresh.length;
}

/** First-run bootstrap. */
export async function seedIfEmpty(): Promise<void> {
  const count = await db.accounts.count();
  if (count === 0) await seedDefaultAccounts();
  if ((await db.bills.count()) === 0) await seedDefaultBills();
}
