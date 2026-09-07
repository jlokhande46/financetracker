import Dexie, { type Table } from "dexie";
import type { Account, Transaction } from "../domain/types";
import type { BillPayment, RecurringBill } from "../domain/bills";
import type { Budget } from "../domain/budgets";
import type { Goal } from "../domain/goals";
import type { InvestmentHolding, NetWorthPoint } from "../domain/investments";

/** A merchant rule the user taught the app during review. */
export interface MerchantRule {
  key: string; // normalised lookup key (merchantRuleKey)
  displayName: string;
  categorySlug: string;
  matchCount: number;
  updatedAt: number;
}

/** Trace of everything the SMS pipeline did, for "where did my SMS go?". */
export interface AuditEvent {
  id?: number;
  timestamp: number;
  kind:
    | "receivedFromServer"
    | "parsed"
    | "parseFailed"
    | "saved"
    | "dedupSkipped";
  textPreview: string;
  detail?: string;
}

/** Local mutations awaiting push to the server. */
export interface OutboxItem {
  id?: number;
  op: "upsertTransaction" | "deleteTransaction";
  payload: unknown;
  createdAt: number;
}

class FinanceDB extends Dexie {
  transactions!: Table<Transaction, string>;
  accounts!: Table<Account, string>;
  merchantRules!: Table<MerchantRule, string>;
  audit!: Table<AuditEvent, number>;
  outbox!: Table<OutboxItem, number>;
  bills!: Table<RecurringBill, string>;
  billPayments!: Table<BillPayment, string>;
  budgets!: Table<Budget, string>;
  goals!: Table<Goal, string>;
  investments!: Table<InvestmentHolding, string>;
  netWorthHistory!: Table<NetWorthPoint, string>;

  constructor() {
    super("financetracker");
    this.version(1).stores({
      // Indexed on date for the paginated feed, and on rawContent because
      // that's the dedup key for re-imported SMS and PDF rows.
      transactions: "id, date, categorySlug, accountId, rawContent, createdAt",
      accounts: "id, type",
      merchantRules: "key",
      audit: "++id, timestamp",
      outbox: "++id, createdAt",
    });
    // v2 adds planning. Dexie carries v1 data forward untouched — only the new
    // stores are created, so an installed PWA upgrades without losing history.
    this.version(2).stores({
      bills: "id, categorySlug, accountId",
      billPayments: "id, billId, periodKey, transactionId",
      budgets: "id, categorySlug",
      goals: "id",
    });
    // v3 adds net worth. History is a table rather than a JSON blob in
    // localStorage (where the Swift build kept it) so it survives a cleared
    // cache alongside everything else, and lands in the backup export.
    this.version(3).stores({
      investments: "id, type",
      netWorthHistory: "month",
    });
  }
}

export const db = new FinanceDB();

/**
 * Newest-first page of transactions.
 *
 * The Swift app's pagination was accidentally quadratic — each page re-filtered,
 * re-sorted and re-grouped everything already loaded. Here the date index does
 * the ordering in IndexedDB, so a page costs the same whether it's the first or
 * the twentieth.
 */
export async function fetchTransactionPage(
  beforeDate: number | undefined,
  limit = 50,
): Promise<{ rows: Transaction[]; hasMore: boolean }> {
  let collection = beforeDate === undefined
    ? db.transactions.orderBy("date").reverse()
    : db.transactions.where("date").below(beforeDate).reverse();

  // Peek one extra to detect "more exist" without a second count query.
  const rows = await collection.limit(limit + 1).toArray();
  const visible = rows.filter((t) => !t.isDeleted && !t.isHidden);
  return {
    rows: visible.slice(0, limit),
    hasMore: rows.length > limit,
  };
}

export async function recordAudit(
  kind: AuditEvent["kind"],
  text: string,
  detail?: string,
): Promise<void> {
  await db.audit.add({
    timestamp: Date.now(),
    kind,
    textPreview: text.slice(0, 120),
    detail,
  });
  // Keep the trace bounded.
  const count = await db.audit.count();
  if (count > 200) {
    const oldest = await db.audit.orderBy("timestamp").limit(count - 200).primaryKeys();
    await db.audit.bulkDelete(oldest);
  }
}
