import { useState } from "react";
import { Sheet } from "../components";
import { money } from "../format";
import { db } from "../../db/db";
import { recalculateBalances } from "../../ingest/ingest";
import { cardBillId } from "../../db/seed";
import { ACCOUNT_TYPE_LABEL, toRupees, type Account } from "../../domain/types";

/**
 * Editing an account: name, opening balance, and a card's billing cycle.
 *
 * The opening balance is the point. Balances here are *derived* — opening
 * balance plus this account's transactions — which is what stops the net-worth
 * figure being the fiction it was in the iOS build, where seeded sample numbers
 * never updated. But derived from zero is just as wrong, and until now there
 * was no way to set the starting point.
 */
export function AccountSheet({
  account, hidden, onClose, onDone,
}: {
  account: Account;
  hidden: boolean;
  onClose: () => void;
  onDone: (message: string) => void | Promise<void>;
}) {
  const [name, setName] = useState(account.name);
  const [opening, setOpening] = useState(
    account.openingBalance !== 0 ? String(toRupees(account.openingBalance)) : "",
  );
  const [statementDay, setStatementDay] = useState(
    account.statementDay ? String(account.statementDay) : "",
  );
  const [dueDay, setDueDay] = useState(account.dueDay ? String(account.dueDay) : "");
  const [isActive, setIsActive] = useState(account.isActive);
  const [busy, setBusy] = useState(false);

  const isCard = account.type === "credit";
  const openingPaise = opening.trim() === "" ? 0 : Math.round(Number(opening) * 100);
  const stmt = statementDay.trim() === "" ? undefined : Number(statementDay);
  const due = dueDay.trim() === "" ? undefined : Number(dueDay);

  const dayValid = (d?: number) => d === undefined || (d >= 1 && d <= 31);
  const valid = name.trim().length > 0 && Number.isFinite(openingPaise) &&
    dayValid(stmt) && dayValid(due);

  // Transactions already counted, so the user can see what the opening balance
  // is being combined with rather than guessing at the difference.
  const movement = account.balance - account.openingBalance;

  async function save() {
    if (!valid) return;
    setBusy(true);
    await db.accounts.put({
      ...account,
      name: name.trim(),
      openingBalance: openingPaise,
      statementDay: isCard ? stmt : undefined,
      dueDay: isCard ? due : undefined,
      isActive,
    });

    // A card's bill is generated from its due day, so a changed cycle has to
    // reach the bill too — otherwise the Plan tab keeps nagging on the old date.
    if (isCard && due !== undefined) {
      const bill = await db.bills.get(cardBillId(account.id));
      if (bill && bill.dueDay !== due) {
        await db.bills.put({ ...bill, dueDay: due, name: `${name.trim()} bill` });
      }
    }

    await recalculateBalances();
    await onDone("Account updated");
  }

  return (
    <Sheet
      title={account.name}
      onClose={onClose}
      footer={
        <button className="btn btn-block" disabled={!valid || busy} onClick={() => void save()}>
          {busy ? "Saving…" : "Save"}
        </button>
      }
    >
      <div className="col" style={{ alignItems: "center", gap: 2, marginBottom: "var(--sp-lg)" }}>
        <span className="amount" style={{ fontSize: 30, fontWeight: 700 }}>
          {money(account.balance, hidden)}
        </span>
        <span className="tiny muted">
          {ACCOUNT_TYPE_LABEL[account.type]}
          {account.last4 && ` · ••${account.last4}`}
        </span>
      </div>

      <label className="section-label">Name</label>
      <input
        className="field"
        value={name}
        onChange={(e) => setName(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Opening balance</label>
      <input
        className="field amount"
        type="number"
        inputMode="decimal"
        placeholder="0"
        value={opening}
        onChange={(e) => setOpening(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-xs)" }}
      />
      <span className="tiny muted">
        {isCard
          ? "What was already outstanding on this card before tracking started."
          : "What was in this account before tracking started."}
        {movement !== 0 && (
          <> Tracked transactions since then come to {money(Math.abs(movement), hidden)}
            {movement >= 0 ? " in" : " out"}.</>
        )}
      </span>

      {isCard && (
        <>
          <label className="section-label" style={{ display: "block", marginTop: "var(--sp-base)" }}>
            Billing cycle
          </label>
          <div className="row" style={{ gap: "var(--sp-sm)", marginTop: "var(--sp-sm)" }}>
            <label className="col grow" style={{ gap: 4 }}>
              <span className="tiny muted">Statement day</span>
              <input
                className="field"
                type="number"
                min={1}
                max={31}
                value={statementDay}
                onChange={(e) => setStatementDay(e.target.value)}
              />
            </label>
            <label className="col grow" style={{ gap: 4 }}>
              <span className="tiny muted">Due day</span>
              <input
                className="field"
                type="number"
                min={1}
                max={31}
                value={dueDay}
                onChange={(e) => setDueDay(e.target.value)}
              />
            </label>
          </div>
          <span className="tiny muted" style={{ display: "block", marginTop: "var(--sp-xs)" }}>
            A due day on or before the statement day settles the following month — that's the
            difference between "bills 7th, due 21st" and "bills 25th, due 10th".
          </span>
        </>
      )}

      <label
        className="spread card"
        style={{ padding: "var(--sp-md)", cursor: "pointer", marginTop: "var(--sp-base)" }}
      >
        <span className="col" style={{ gap: 2 }}>
          <span className="small">Active</span>
          <span className="tiny muted">Closed accounts drop out of net worth and the dashboard</span>
        </span>
        <input
          type="checkbox"
          checked={isActive}
          onChange={(e) => setIsActive(e.target.checked)}
          style={{ width: 20, height: 20, accentColor: "var(--brand-primary)" }}
        />
      </label>
    </Sheet>
  );
}
