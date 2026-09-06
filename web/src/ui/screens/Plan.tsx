import { useState } from "react";
import { Bar, EmptyState } from "../components";
import { money, moneyCompact, fullDate, percent } from "../format";
import { findCategory } from "../../domain/categories";
import { dueDescription, FREQUENCY_LABEL, STATE_META } from "../../domain/bills";
import { BUDGET_STATE_META, TOTAL_BUDGET_SLUG } from "../../domain/budgets";
import { GOAL_STATE_META } from "../../domain/goals";
import { useAllTransactions } from "../../state/useStore";
import { markBillUnpaid, usePlan } from "../../state/usePlan";
import { BillEditSheet, BillPaySheet, BudgetEditSheet, GoalEditSheet } from "./PlanSheets";
import type { BillStatus, BudgetStatus, GoalStatus } from "../../state/usePlan";
import type { RecurringBill } from "../../domain/bills";
import type { Budget } from "../../domain/budgets";
import type { Goal } from "../../domain/goals";

type Section = "bills" | "budgets" | "goals";

const SECTIONS: Array<{ id: Section; label: string }> = [
  { id: "bills", label: "Bills" },
  { id: "budgets", label: "Budgets" },
  { id: "goals", label: "Goals" },
];

export function PlanScreen({
  hidden, onToast,
}: { hidden: boolean; onToast: (m: string) => void }) {
  const { all, reload: reloadTransactions } = useAllTransactions();
  const plan = usePlan(all);
  const [section, setSection] = useState<Section>("bills");

  // Sheet state, one at a time.
  const [payingBill, setPayingBill] = useState<BillStatus | null>(null);
  const [editingBill, setEditingBill] = useState<RecurringBill | "new" | null>(null);
  const [editingBudget, setEditingBudget] = useState<Budget | "new" | null>(null);
  const [editingGoal, setEditingGoal] = useState<Goal | "new" | null>(null);

  const refresh = async (message?: string) => {
    await Promise.all([plan.reload(), reloadTransactions()]);
    if (message) onToast(message);
  };

  return (
    <div className="screen col" style={{ gap: "var(--sp-base)" }}>
      <h1 className="h1" style={{ margin: 0 }}>Plan</h1>

      <div className="row" style={{ gap: "var(--sp-sm)" }}>
        {SECTIONS.map((s) => (
          <button
            key={s.id}
            className="chip grow"
            data-selected={section === s.id}
            style={{ textAlign: "center", justifyContent: "center" }}
            onClick={() => setSection(s.id)}
          >
            {s.label}
          </button>
        ))}
      </div>

      {section === "bills" && (
        <BillsSection
          plan={plan}
          hidden={hidden}
          onPay={setPayingBill}
          onEdit={setEditingBill}
          onUnpay={async (s) => {
            // The settled cycle, not the one now showing as next.
            if (!s.paidPeriodKey) return;
            await markBillUnpaid(s.bill.id, s.paidPeriodKey);
            await refresh("Marked unpaid");
          }}
        />
      )}

      {section === "budgets" && (
        <BudgetsSection plan={plan} hidden={hidden} onEdit={setEditingBudget} />
      )}

      {section === "goals" && (
        <GoalsSection plan={plan} hidden={hidden} onEdit={setEditingGoal} />
      )}

      {payingBill && (
        <BillPaySheet
          status={payingBill}
          transactions={all}
          hidden={hidden}
          onClose={() => setPayingBill(null)}
          onDone={async () => { setPayingBill(null); await refresh("Marked paid"); }}
        />
      )}
      {editingBill && (
        <BillEditSheet
          bill={editingBill === "new" ? null : editingBill}
          onClose={() => setEditingBill(null)}
          onDone={async (msg) => { setEditingBill(null); await refresh(msg); }}
        />
      )}
      {editingBudget && (
        <BudgetEditSheet
          budget={editingBudget === "new" ? null : editingBudget}
          existing={plan.budgets}
          onClose={() => setEditingBudget(null)}
          onDone={async (msg) => { setEditingBudget(null); await refresh(msg); }}
        />
      )}
      {editingGoal && (
        <GoalEditSheet
          goal={editingGoal === "new" ? null : editingGoal}
          onClose={() => setEditingGoal(null)}
          onDone={async (msg) => { setEditingGoal(null); await refresh(msg); }}
        />
      )}
    </div>
  );
}

// ── bills ────────────────────────────────────────────────────────────────────

function BillsSection({
  plan, hidden, onPay, onEdit, onUnpay,
}: {
  plan: ReturnType<typeof usePlan>;
  hidden: boolean;
  onPay: (s: BillStatus) => void;
  onEdit: (b: RecurringBill | "new") => void;
  onUnpay: (s: BillStatus) => void | Promise<void>;
}) {
  const { billStatuses, reminders } = plan;

  return (
    <>
      {/* The salary-triggered nudge: silent until money has landed, gone once
          everything is settled. */}
      {reminders.message && (
        <section
          className="card col"
          style={{
            gap: 4,
            background: "rgba(255,181,69,0.08)",
            border: "1px solid rgba(255,181,69,0.3)",
          }}
        >
          <span style={{ fontWeight: 600 }}>{reminders.message}</span>
          <span className="tiny muted">
            Salary landed {fullDate(reminders.salaryDate!)}
            {reminders.totalOutstanding > 0 &&
              ` · about ${moneyCompact(reminders.totalOutstanding, hidden)} to go`}
          </span>
        </section>
      )}

      {billStatuses.length === 0 ? (
        <EmptyState
          title="No recurring bills"
          subtitle="Add rent, electricity, your postpaid bill or a card settlement and this screen will track what's still outstanding each cycle."
          action={<button className="btn" onClick={() => onEdit("new")}>Add a bill</button>}
        />
      ) : (
        <div className="col" style={{ gap: "var(--sp-sm)" }}>
          {billStatuses.map((s) => (
            <BillCard
              key={s.bill.id}
              status={s}
              hidden={hidden}
              onPay={() => onPay(s)}
              onUnpay={() => void onUnpay(s)}
              onEdit={() => onEdit(s.bill)}
            />
          ))}
          <button className="btn btn-secondary btn-block" onClick={() => onEdit("new")}>
            Add a bill
          </button>
        </div>
      )}
    </>
  );
}

function BillCard({
  status, hidden, onPay, onUnpay, onEdit,
}: {
  status: BillStatus;
  hidden: boolean;
  onPay: () => void;
  onUnpay: () => void;
  onEdit: () => void;
}) {
  const { bill, state, isPaid } = status;
  const meta = STATE_META[state];
  const cat = findCategory(bill.categorySlug);

  return (
    <section
      className="card col"
      style={{
        gap: "var(--sp-sm)",
        borderLeft: `3px solid ${meta.color}`,
      }}
    >
      <div className="spread">
        <button className="col grow" style={{ gap: 2, textAlign: "left" }} onClick={onEdit}>
          <span style={{ fontWeight: 600 }}>{bill.name}</span>
          <span className="tiny muted">
            {cat.name} · {FREQUENCY_LABEL[bill.frequency].toLowerCase()}
          </span>
        </button>
        <div className="col" style={{ alignItems: "flex-end", gap: 2 }}>
          {bill.expectedAmount > 0 && (
            <span className="amount" style={{ fontWeight: 600 }}>
              {money(bill.expectedAmount, hidden)}
            </span>
          )}
          <span className="tiny" style={{ color: meta.color }}>{dueDescription(status)}</span>
        </div>
      </div>

      <div className="spread">
        <span className="tiny muted">
          {isPaid
            ? `Settled ${fullDate(status.payment!.paidAt)} · next ${fullDate(status.dueDate)}`
            : `Due ${fullDate(status.dueDate)}`}
        </span>
        {isPaid ? (
          <button className="chip" onClick={onUnpay}>Undo</button>
        ) : (
          <button className="chip" data-selected onClick={onPay}>Mark paid</button>
        )}
      </div>
    </section>
  );
}

// ── budgets ──────────────────────────────────────────────────────────────────

function BudgetsSection({
  plan, hidden, onEdit,
}: {
  plan: ReturnType<typeof usePlan>;
  hidden: boolean;
  onEdit: (b: Budget | "new") => void;
}) {
  if (plan.budgetList.length === 0) {
    return (
      <EmptyState
        title="No budgets set"
        subtitle="Cap a category — or the whole month — and this tracks not just how much is left, but whether you're spending it too fast."
        action={<button className="btn" onClick={() => onEdit("new")}>Set a budget</button>}
      />
    );
  }

  return (
    <div className="col" style={{ gap: "var(--sp-sm)" }}>
      {plan.budgetList.map((s) => (
        <BudgetCard key={s.budget.id} status={s} hidden={hidden} onEdit={() => onEdit(s.budget)} />
      ))}
      <button className="btn btn-secondary btn-block" onClick={() => onEdit("new")}>
        Set another budget
      </button>
    </div>
  );
}

function BudgetCard({
  status, hidden, onEdit,
}: { status: BudgetStatus; hidden: boolean; onEdit: () => void }) {
  const { budget, spent, remaining, fraction, expectedFraction, state } = status;
  const meta = BUDGET_STATE_META[state];
  const isTotal = budget.categorySlug === TOTAL_BUDGET_SLUG;
  const cat = findCategory(budget.categorySlug);
  const label = isTotal ? "Everything" : cat.name;
  const color = isTotal ? "var(--brand-primary)" : cat.colorHex;

  return (
    <button className="card col" style={{ gap: "var(--sp-sm)", textAlign: "left" }} onClick={onEdit}>
      <div className="spread">
        <span style={{ fontWeight: 600 }}>{label}</span>
        <span className="tiny" style={{ color: meta.color }}>{meta.label}</span>
      </div>

      <div style={{ position: "relative" }}>
        <Bar fraction={fraction} color={state === "over" ? "var(--expense-red)" : color} />
        {/* Pace marker: where spending should be by today. A bar alone can't
            tell you whether ₹8,000 of ₹10,000 is fine or alarming. */}
        {expectedFraction > 0 && expectedFraction < 1 && (
          <div
            aria-hidden
            style={{
              position: "absolute", top: -2, bottom: -2,
              left: `${expectedFraction * 100}%`,
              width: 2, background: "var(--text-primary)", opacity: 0.5,
            }}
          />
        )}
      </div>

      <div className="spread tiny muted">
        <span>{money(spent, hidden)} of {money(budget.limit, hidden)}</span>
        <span>{percent(fraction * 100)}</span>
      </div>

      <span className="tiny muted">
        {remaining >= 0
          ? status.dailyAllowance > 0
            ? `${money(remaining, hidden)} left · ${money(status.dailyAllowance, hidden)}/day to stay on budget`
            : `${money(remaining, hidden)} left`
          : `${money(-remaining, hidden)} over`}
        {status.projectedSpend > 0 &&
          ` · heading for ${moneyCompact(status.projectedSpend, hidden)}`}
      </span>
    </button>
  );
}

// ── goals ────────────────────────────────────────────────────────────────────

function GoalsSection({
  plan, hidden, onEdit,
}: {
  plan: ReturnType<typeof usePlan>;
  hidden: boolean;
  onEdit: (g: Goal | "new") => void;
}) {
  if (plan.goalList.length === 0) {
    return (
      <EmptyState
        title="No goals yet"
        subtitle="Name something you're saving for and this works out what you'd need to put aside each month to actually get there."
        action={<button className="btn" onClick={() => onEdit("new")}>Add a goal</button>}
      />
    );
  }

  return (
    <div className="col" style={{ gap: "var(--sp-sm)" }}>
      {plan.goalList.map((s) => (
        <GoalCard key={s.goal.id} status={s} hidden={hidden} onEdit={() => onEdit(s.goal)} />
      ))}
      <button className="btn btn-secondary btn-block" onClick={() => onEdit("new")}>
        Add another goal
      </button>
    </div>
  );
}

function GoalCard({
  status, hidden, onEdit,
}: { status: GoalStatus; hidden: boolean; onEdit: () => void }) {
  const { goal, fraction, remaining, monthsLeft, requiredPerMonth, state } = status;
  const meta = GOAL_STATE_META[state];

  return (
    <button className="card col" style={{ gap: "var(--sp-sm)", textAlign: "left" }} onClick={onEdit}>
      <div className="spread">
        <span style={{ fontWeight: 600 }}>{goal.name}</span>
        <span className="tiny" style={{ color: meta.color }}>{meta.label}</span>
      </div>

      <Bar fraction={fraction} color={goal.colorHex} />

      <div className="spread tiny muted">
        <span>{money(goal.savedAmount, hidden)} of {money(goal.targetAmount, hidden)}</span>
        <span>{percent(fraction * 100)}</span>
      </div>

      {requiredPerMonth !== null && remaining > 0 && (
        <span className="tiny muted">
          {monthsLeft === 0
            ? `${money(remaining, hidden)} due by ${fullDate(goal.targetDate!)}`
            : `${money(requiredPerMonth, hidden)}/month for ${monthsLeft} more month${monthsLeft === 1 ? "" : "s"}`}
        </span>
      )}
      {remaining === 0 && <span className="tiny" style={{ color: "var(--income-green)" }}>Fully funded</span>}
    </button>
  );
}
