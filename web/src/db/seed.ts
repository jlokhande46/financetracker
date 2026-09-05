import { db } from "./db";
import { rupees, type Account } from "../domain/types";

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

/** First-run bootstrap. */
export async function seedIfEmpty(): Promise<void> {
  const count = await db.accounts.count();
  if (count === 0) await seedDefaultAccounts();
}
