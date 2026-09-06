import { useMemo, useState } from "react";
import { Sheet, CategoryDot } from "../components";
import { fullDate, money, moneyPrecise } from "../format";
import { CATEGORIES } from "../../domain/categories";
import { FREQUENCY_LABEL, type BillFrequency, type RecurringBill } from "../../domain/bills";
import { billCandidates } from "../../domain/billMatching";
import { TOTAL_BUDGET_SLUG, type Budget } from "../../domain/budgets";
import type { Goal } from "../../domain/goals";
import type { BillStatus } from "../../state/usePlan";
import {
  deleteBill, deleteBudget, deleteGoal, markBillPaid, saveBill, saveBudget, saveGoal,
} from "../../state/usePlan";
import { toRupees, type Transaction } from "../../domain/types";

type Done = (message?: string) => void | Promise<void>;

/** Rupee text field <-> paise. Empty reads as zero rather than NaN. */
function useMoneyField(initial: number) {
  const [text, setText] = useState(initial > 0 ? String(toRupees(initial)) : "");
  const paise = text.trim() === "" ? 0 : Math.round(Number(text) * 100);
  return { text, setText, paise: Number.isFinite(paise) ? paise : 0 };
}

const dateInputValue = (ms: number) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

// ── marking a bill paid ──────────────────────────────────────────────────────

/**
 * Picking the transaction that settled a bill.
 *
 * The shortlist is ranked but never auto-applied — a wrong auto-match silently
 * marks a bill paid that isn't, which is worse than one extra tap. Paying
 * without a matching transaction is still allowed, for cash and for anything
 * the app never saw.
 */
export function BillPaySheet({
  status, transactions, hidden, onClose, onDone,
}: {
  status: BillStatus;
  transactions: Transaction[];
  hidden: boolean;
  onClose: () => void;
  onDone: Done;
}) {
  const candidates = useMemo(
    () => billCandidates(status, transactions),
    [status, transactions],
  );
  // Preselect only a confident match. The shortlist is deliberately generous,
  // so the top row is often just "a debit near the due date" — preselecting
  // that puts a wrong link one tap away.
  const [picked, setPicked] = useState<string | null>(
    candidates[0] && candidates[0].score >= 0.7 ? candidates[0].transaction.id : null,
  );
  const manual = useMoneyField(status.bill.expectedAmount);
  const [busy, setBusy] = useState(false);

  const pickedTxn = candidates.find((c) => c.transaction.id === picked)?.transaction;

  async function confirm() {
    setBusy(true);
    await markBillPaid({
      billId: status.bill.id,
      periodKey: status.periodKey,
      amount: pickedTxn?.amount ?? manual.paise,
      transactionId: pickedTxn?.id,
      paidAt: pickedTxn?.date,
    });
    await onDone();
  }

  return (
    <Sheet
      title={`Mark ${status.bill.name} paid`}
      onClose={onClose}
      footer={
        <button className="btn btn-block" disabled={busy} onClick={() => void confirm()}>
          {busy ? "Saving…" : pickedTxn ? "Link and mark paid" : "Mark paid"}
        </button>
      }
    >
      <p className="small muted" style={{ margin: "0 0 var(--sp-base)" }}>
        Due {fullDate(status.dueDate)}. Pick the payment that settled it, or record it
        without one.
      </p>

      {candidates.length > 0 && (
        <>
          <span className="section-label">Likely payments</span>
          <div className="col" style={{ gap: "var(--sp-sm)", margin: "var(--sp-sm) 0 var(--sp-base)" }}>
            {candidates.map((c) => (
              <button
                key={c.transaction.id}
                className="row card"
                style={{
                  gap: "var(--sp-md)", textAlign: "left", padding: "var(--sp-md)",
                  border: picked === c.transaction.id
                    ? "1px solid var(--brand-primary)"
                    : "1px solid transparent",
                }}
                onClick={() => setPicked(picked === c.transaction.id ? null : c.transaction.id)}
              >
                <CategoryDot slug={c.transaction.categorySlug} size={32} />
                <span className="col grow" style={{ gap: 2 }}>
                  <span className="small truncate" style={{ fontWeight: 600 }}>
                    {c.transaction.merchantName || c.transaction.merchantRaw}
                  </span>
                  <span className="tiny muted">
                    {fullDate(c.transaction.date)} · {c.reason}
                  </span>
                </span>
                <span className="small amount" style={{ fontWeight: 600 }}>
                  {money(c.transaction.amount, hidden)}
                </span>
              </button>
            ))}
          </div>
        </>
      )}

      {!pickedTxn && (
        <>
          <span className="section-label">Amount paid</span>
          <input
            className="field amount"
            type="number"
            inputMode="decimal"
            placeholder="0"
            value={manual.text}
            onChange={(e) => manual.setText(e.target.value)}
            style={{ margin: "var(--sp-xs) 0" }}
          />
          <span className="tiny muted">
            {candidates.length === 0
              ? "No transaction near the due date matched — record the amount by hand."
              : "Nothing selected, so this is recorded without a linked transaction."}
          </span>
        </>
      )}
    </Sheet>
  );
}

// ── bill editing ─────────────────────────────────────────────────────────────

const FREQUENCIES: BillFrequency[] = ["monthly", "bimonthly", "quarterly", "yearly"];

export function BillEditSheet({
  bill, onClose, onDone,
}: { bill: RecurringBill | null; onClose: () => void; onDone: Done }) {
  const [name, setName] = useState(bill?.name ?? "");
  const [slug, setSlug] = useState(bill?.categorySlug ?? "bills");
  const amount = useMoneyField(bill?.expectedAmount ?? 0);
  const [dueDay, setDueDay] = useState(String(bill?.dueDay ?? 5));
  const [frequency, setFrequency] = useState<BillFrequency>(bill?.frequency ?? "monthly");
  const [anchor, setAnchor] = useState(() =>
    dateInputValue(bill?.anchorMonth ?? Date.now()),
  );
  const [isActive, setIsActive] = useState(bill?.isActive ?? true);
  const [busy, setBusy] = useState(false);

  const day = Number(dueDay);
  const valid = name.trim().length > 0 && day >= 1 && day <= 31;
  const expenseCategories = CATEGORIES.filter((c) => !c.isIncome);

  async function save() {
    if (!valid) return;
    setBusy(true);
    const anchorDate = new Date(anchor);
    await saveBill({
      id: bill?.id ?? crypto.randomUUID(),
      name: name.trim(),
      categorySlug: slug,
      expectedAmount: amount.paise,
      dueDay: day,
      frequency,
      anchorMonth: new Date(anchorDate.getFullYear(), anchorDate.getMonth(), 1).getTime(),
      accountId: bill?.accountId,
      isActive,
      createdAt: bill?.createdAt ?? Date.now(),
    });
    await onDone(bill ? "Bill updated" : "Bill added");
  }

  return (
    <Sheet
      title={bill ? "Edit bill" : "New bill"}
      onClose={onClose}
      footer={
        <div className="col" style={{ gap: "var(--sp-sm)" }}>
          <button className="btn btn-block" disabled={!valid || busy} onClick={() => void save()}>
            {busy ? "Saving…" : "Save bill"}
          </button>
          {bill && (
            <button
              className="btn btn-block btn-secondary"
              style={{ color: "var(--expense-red)" }}
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                await deleteBill(bill.id);
                await onDone("Bill deleted");
              }}
            >
              Delete
            </button>
          )}
        </div>
      }
    >
      <label className="section-label">Name</label>
      <input
        className="field"
        placeholder="e.g. Electricity"
        value={name}
        onChange={(e) => setName(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Usual amount</label>
      <input
        className="field amount"
        type="number"
        inputMode="decimal"
        placeholder="Optional"
        value={amount.text}
        onChange={(e) => amount.setText(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Due on day</label>
      <input
        className="field"
        type="number"
        min={1}
        max={31}
        value={dueDay}
        onChange={(e) => setDueDay(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-xs)" }}
      />
      <span className="tiny muted">
        A day past the end of a short month lands on its last day — the 31st becomes 28 Feb,
        never 3 March.
      </span>

      <label className="section-label" style={{ display: "block", marginTop: "var(--sp-base)" }}>
        Repeats
      </label>
      <div className="hscroll" style={{ margin: "var(--sp-sm) 0" }}>
        {FREQUENCIES.map((f) => (
          <button
            key={f}
            className="chip"
            data-selected={frequency === f}
            onClick={() => setFrequency(f)}
          >
            {FREQUENCY_LABEL[f]}
          </button>
        ))}
      </div>

      {frequency !== "monthly" && (
        <>
          <label className="section-label">Next one falls in</label>
          <input
            className="field"
            type="date"
            value={anchor}
            onChange={(e) => setAnchor(e.target.value)}
            style={{ margin: "var(--sp-xs) 0 var(--sp-xs)" }}
          />
          <span className="tiny muted">
            Sets which months the cycle lands in — a gas bill anchored to June comes due in
            June, August and October, not July.
          </span>
        </>
      )}

      <label className="section-label" style={{ display: "block", marginTop: "var(--sp-base)" }}>
        Category
      </label>
      <div
        style={{
          display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))",
          gap: "var(--sp-sm)", margin: "var(--sp-sm) 0 var(--sp-base)",
        }}
      >
        {expenseCategories.map((c) => (
          <button
            key={c.slug}
            onClick={() => setSlug(c.slug)}
            style={{
              padding: "8px 6px", borderRadius: "var(--r-md)", fontSize: 12,
              background: slug === c.slug ? c.colorHex : "var(--bg-elevated)",
              color: slug === c.slug ? "#fff" : "var(--text-secondary)",
            }}
          >
            {c.name}
          </button>
        ))}
      </div>

      <label className="spread card" style={{ padding: "var(--sp-md)", cursor: "pointer" }}>
        <span className="col" style={{ gap: 2 }}>
          <span className="small">Active</span>
          <span className="tiny muted">Turn off to stop tracking without losing history</span>
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

// ── budget editing ───────────────────────────────────────────────────────────

export function BudgetEditSheet({
  budget, existing, onClose, onDone,
}: {
  budget: Budget | null;
  existing: Budget[];
  onClose: () => void;
  onDone: Done;
}) {
  const [slug, setSlug] = useState(budget?.categorySlug ?? TOTAL_BUDGET_SLUG);
  const limit = useMoneyField(budget?.limit ?? 0);
  const [busy, setBusy] = useState(false);

  // One budget per category, or the list becomes two rows that disagree.
  const taken = new Set(existing.filter((b) => b.id !== budget?.id).map((b) => b.categorySlug));
  const options = [
    { slug: TOTAL_BUDGET_SLUG, name: "Everything", colorHex: "#7b6ef6" },
    ...CATEGORIES.filter((c) => !c.isIncome && !c.isTransfer),
  ].filter((o) => o.slug === slug || !taken.has(o.slug));

  const valid = limit.paise > 0;

  async function save() {
    if (!valid) return;
    setBusy(true);
    await saveBudget({
      id: budget?.id ?? crypto.randomUUID(),
      categorySlug: slug,
      limit: limit.paise,
      createdAt: budget?.createdAt ?? Date.now(),
    });
    await onDone(budget ? "Budget updated" : "Budget set");
  }

  return (
    <Sheet
      title={budget ? "Edit budget" : "New budget"}
      onClose={onClose}
      footer={
        <div className="col" style={{ gap: "var(--sp-sm)" }}>
          <button className="btn btn-block" disabled={!valid || busy} onClick={() => void save()}>
            {busy ? "Saving…" : "Save budget"}
          </button>
          {budget && (
            <button
              className="btn btn-block btn-secondary"
              style={{ color: "var(--expense-red)" }}
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                await deleteBudget(budget.id);
                await onDone("Budget removed");
              }}
            >
              Delete
            </button>
          )}
        </div>
      }
    >
      <label className="section-label">Monthly limit</label>
      <input
        className="field amount"
        type="number"
        inputMode="decimal"
        placeholder="0"
        value={limit.text}
        onChange={(e) => limit.setText(e.target.value)}
        style={{ fontSize: 24, fontWeight: 700, margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Applies to</label>
      <div
        style={{
          display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))",
          gap: "var(--sp-sm)", margin: "var(--sp-sm) 0 var(--sp-base)",
        }}
      >
        {options.map((c) => (
          <button
            key={c.slug}
            onClick={() => setSlug(c.slug)}
            style={{
              padding: "8px 6px", borderRadius: "var(--r-md)", fontSize: 12,
              background: slug === c.slug ? c.colorHex : "var(--bg-elevated)",
              color: slug === c.slug ? "#fff" : "var(--text-secondary)",
            }}
          >
            {c.name}
          </button>
        ))}
      </div>

      <span className="tiny muted">
        Card payments and transfers never count towards a budget — settling a statement moves
        money, it doesn't spend it.
      </span>
    </Sheet>
  );
}

// ── goal editing ─────────────────────────────────────────────────────────────

const GOAL_COLORS = ["#10B981", "#7b6ef6", "#F59E0B", "#EC4899", "#06B6D4", "#EF4444"];

export function GoalEditSheet({
  goal, onClose, onDone,
}: { goal: Goal | null; onClose: () => void; onDone: Done }) {
  const [name, setName] = useState(goal?.name ?? "");
  const target = useMoneyField(goal?.targetAmount ?? 0);
  const saved = useMoneyField(goal?.savedAmount ?? 0);
  // New goals default to having a deadline: the monthly figure is the useful
  // part, and it needs one. An existing goal keeps whatever it was saved with.
  const [hasDeadline, setHasDeadline] = useState(goal ? goal.targetDate !== undefined : true);
  const [deadline, setDeadline] = useState(() =>
    dateInputValue(goal?.targetDate ?? Date.now() + 365 * 86_400_000),
  );
  const [color, setColor] = useState(goal?.colorHex ?? GOAL_COLORS[0]!);
  const [busy, setBusy] = useState(false);

  const valid = name.trim().length > 0 && target.paise > 0;
  // Live preview of the monthly figure — the number that decides whether the
  // target is realistic before it's committed to.
  const preview = useMemo(() => {
    if (!valid || !hasDeadline) return null;
    const to = new Date(deadline), from = new Date();
    const months = Math.max(0, (to.getFullYear() - from.getFullYear()) * 12 + (to.getMonth() - from.getMonth()));
    const remaining = Math.max(0, target.paise - saved.paise);
    return months > 0 ? Math.ceil(remaining / months) : remaining;
  }, [valid, hasDeadline, deadline, target.paise, saved.paise]);

  async function save() {
    if (!valid) return;
    setBusy(true);
    await saveGoal({
      id: goal?.id ?? crypto.randomUUID(),
      name: name.trim(),
      targetAmount: target.paise,
      savedAmount: saved.paise,
      targetDate: hasDeadline ? new Date(deadline).getTime() : undefined,
      colorHex: color,
      isArchived: goal?.isArchived,
      createdAt: goal?.createdAt ?? Date.now(),
    });
    await onDone(goal ? "Goal updated" : "Goal added");
  }

  return (
    <Sheet
      title={goal ? "Edit goal" : "New goal"}
      onClose={onClose}
      footer={
        <div className="col" style={{ gap: "var(--sp-sm)" }}>
          <button className="btn btn-block" disabled={!valid || busy} onClick={() => void save()}>
            {busy ? "Saving…" : "Save goal"}
          </button>
          {goal && (
            <button
              className="btn btn-block btn-secondary"
              style={{ color: "var(--expense-red)" }}
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                await deleteGoal(goal.id);
                await onDone("Goal deleted");
              }}
            >
              Delete
            </button>
          )}
        </div>
      }
    >
      <label className="section-label">Goal</label>
      <input
        className="field"
        placeholder="e.g. Emergency fund"
        value={name}
        onChange={(e) => setName(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Target</label>
      <input
        className="field amount"
        type="number"
        inputMode="decimal"
        placeholder="0"
        value={target.text}
        onChange={(e) => target.setText(e.target.value)}
        style={{ fontSize: 24, fontWeight: 700, margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Saved so far</label>
      <input
        className="field amount"
        type="number"
        inputMode="decimal"
        placeholder="0"
        value={saved.text}
        onChange={(e) => saved.setText(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="spread card" style={{ padding: "var(--sp-md)", cursor: "pointer" }}>
        <span className="small">Set a deadline</span>
        <input
          type="checkbox"
          checked={hasDeadline}
          onChange={(e) => setHasDeadline(e.target.checked)}
          style={{ width: 20, height: 20, accentColor: "var(--brand-primary)" }}
        />
      </label>

      {hasDeadline && (
        <input
          className="field"
          type="date"
          value={deadline}
          onChange={(e) => setDeadline(e.target.value)}
          style={{ margin: "var(--sp-sm) 0 var(--sp-xs)" }}
        />
      )}

      {preview !== null && preview > 0 && (
        <p className="tiny muted" style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}>
          That's {moneyPrecise(preview)} a month from now until then.
        </p>
      )}

      <label className="section-label" style={{ display: "block", marginTop: "var(--sp-base)" }}>
        Colour
      </label>
      <div className="row" style={{ gap: "var(--sp-sm)", marginTop: "var(--sp-sm)" }}>
        {GOAL_COLORS.map((c) => (
          <button
            key={c}
            aria-label={`Colour ${c}`}
            onClick={() => setColor(c)}
            style={{
              width: 32, height: 32, borderRadius: "50%", background: c,
              border: color === c ? "2px solid var(--text-primary)" : "2px solid transparent",
            }}
          />
        ))}
      </div>
    </Sheet>
  );
}
