import { useMemo, useState } from "react";
import { analyseMonth, addMonths, inMonth, needsWants, startOfMonth } from "../../domain/analysis";
import { INTENT_META, type CategoryIntent } from "../../domain/types";
import { findCategory } from "../../domain/categories";
import { creditCardBillDates } from "../../domain/billMatching";
import { dueDescription, STATE_META } from "../../domain/bills";
import { tipOfTheDay } from "../../domain/tips";
import { Bar, CategoryDot, EmptyState } from "../components";
import { AccountSheet } from "./AccountSheet";
import { fullDate, money, moneyCompact, monthYear, percent } from "../format";
import { useAccounts, useAllTransactions, usePendingReview } from "../../state/useStore";
import { usePlan } from "../../state/usePlan";
import type { Account } from "../../domain/types";

export function DashboardScreen({
  hidden, onGoToTransactions, onToast,
}: {
  hidden: boolean;
  onGoToTransactions: () => void;
  onToast: (m: string) => void;
}) {
  const { all, loading } = useAllTransactions();
  const { accounts, reload: reloadAccounts } = useAccounts();
  const [editingAccount, setEditingAccount] = useState<Account | null>(null);
  const { pending } = usePendingReview();
  const plan = usePlan(all);
  const [month, setMonth] = useState(() => startOfMonth(Date.now()));
  const tip = useMemo(() => tipOfTheDay(), []);

  const analysis = useMemo(() => analyseMonth(month, all), [month, all]);
  const split = useMemo(
    () => needsWants(all.filter((t) => inMonth(t.date, month))),
    [all, month],
  );
  const isCurrentMonth = month === startOfMonth(Date.now());

  const creditCards = accounts.filter((a) => a.isActive && a.type === "credit");
  const deposits = accounts.filter((a) => a.isActive && a.type !== "credit");

  // Only what's close enough to act on. A bill three weeks out is noise here;
  // the Plan tab has the full list.
  const upcoming = plan.billStatuses.filter((s) => !s.isPaid && s.daysUntilDue <= 10).slice(0, 5);

  if (loading) {
    return (
      <div className="screen row" style={{ justifyContent: "center", paddingTop: 80 }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div className="screen col" style={{ gap: "var(--sp-lg)" }}>
      <div className="spread">
        <button className="chip" onClick={() => setMonth(addMonths(month, -1))} aria-label="Previous month">‹</button>
        <div className="col" style={{ alignItems: "center", gap: 0 }}>
          <span className="h2">{monthYear(month)}</span>
          <span className="tiny muted">Finance overview</span>
        </div>
        <button
          className="chip"
          onClick={() => setMonth(addMonths(month, 1))}
          disabled={isCurrentMonth}
          style={{ opacity: isCurrentMonth ? 0.3 : 1 }}
          aria-label="Next month"
        >
          ›
        </button>
      </div>

      {all.length === 0 ? (
        <EmptyState
          title="Nothing tracked yet"
          subtitle="Set up the Shortcut in Settings so bank SMS flow in automatically, or add a transaction by hand."
        />
      ) : (
        <>
          <SpendingCard analysis={analysis} hidden={hidden} />

          {pending.length > 0 && (
            <button
              className="card spread"
              onClick={onGoToTransactions}
              style={{
                background: "rgba(255,181,69,0.08)",
                border: "1px solid rgba(255,181,69,0.3)",
                textAlign: "left",
              }}
            >
              <span className="col" style={{ gap: 2 }}>
                <span style={{ fontWeight: 600 }}>
                  {pending.length} transaction{pending.length === 1 ? "" : "s"} need review
                </span>
                <span className="tiny muted">Low-confidence auto-categorisations</span>
              </span>
              <span className="muted">›</span>
            </button>
          )}

          {/* The 50/30/20 split belongs on the home screen, not only behind a
              toggle in Insights — it's the number this app exists to show. */}
          {split.total > 0 && (
            <section className="card col" style={{ gap: "var(--sp-md)" }}>
              <div className="spread">
                <span className="section-label">Needs · Wants · Savings</span>
                <span className="tiny muted">50 / 30 / 20</span>
              </div>
              <div style={{ display: "flex", height: 10, borderRadius: 5, overflow: "hidden" }}>
                {(["need", "want", "saving"] as CategoryIntent[]).map((i) =>
                  split[i] > 0 ? (
                    <div
                      key={i}
                      style={{ width: `${(split[i] / split.total) * 100}%`, background: INTENT_META[i].color }}
                      title={INTENT_META[i].label}
                    />
                  ) : null,
                )}
              </div>
              <div className="row" style={{ gap: "var(--sp-base)" }}>
                {(["need", "want", "saving"] as CategoryIntent[]).map((i) => {
                  const actual = (split[i] / split.total) * 100;
                  const delta = actual - INTENT_META[i].targetPercent;
                  return (
                    <div key={i} className="col grow" style={{ gap: 2 }}>
                      <span className="tiny" style={{ color: INTENT_META[i].color }}>
                        {INTENT_META[i].label}
                      </span>
                      <span className="amount small" style={{ fontWeight: 700 }}>
                        {money(split[i], hidden)}
                      </span>
                      <span className="tiny muted">
                        {percent(actual)} vs {INTENT_META[i].targetPercent}%
                        {Math.abs(delta) >= 1 && (
                          <span style={{ color: offTarget(i, delta) ? "var(--warning-amber)" : "var(--income-green)" }}>
                            {" "}{delta > 0 ? "↑" : "↓"}
                          </span>
                        )}
                      </span>
                    </div>
                  );
                })}
              </div>
            </section>
          )}

          {/* What's actually outstanding right now, ahead of the month's
              analysis — it's the thing that needs acting on today. */}
          {upcoming.length > 0 && (
            <section className="card col" style={{ gap: "var(--sp-md)" }}>
              <span className="section-label">Coming up</span>
              {upcoming.map((s) => (
                <div key={s.bill.id} className="spread">
                  <span className="col" style={{ gap: 2 }}>
                    <span className="small">{s.bill.name}</span>
                    <span className="tiny" style={{ color: STATE_META[s.state].color }}>
                      {dueDescription(s)}
                    </span>
                  </span>
                  {s.bill.expectedAmount > 0 && (
                    <span className="small amount" style={{ fontWeight: 600 }}>
                      {money(s.bill.expectedAmount, hidden)}
                    </span>
                  )}
                </div>
              ))}
            </section>
          )}

          {analysis.categoryBreakdown.length > 0 && (
            <section className="card col" style={{ gap: "var(--sp-md)" }}>
              <span className="section-label">Where it went</span>
              {analysis.categoryBreakdown.map((c) => {
                const cat = findCategory(c.categorySlug);
                return (
                  <div key={c.categorySlug} className="col" style={{ gap: 6 }}>
                    <div className="spread">
                      <span className="row" style={{ gap: "var(--sp-sm)" }}>
                        <CategoryDot slug={c.categorySlug} size={28} />
                        <span className="small">{cat.name}</span>
                      </span>
                      <span className="small amount" style={{ fontWeight: 600 }}>
                        {money(c.amount, hidden)}
                      </span>
                    </div>
                    <Bar fraction={c.percent / 100} color={cat.colorHex} />
                  </div>
                );
              })}
            </section>
          )}

          {creditCards.length > 0 && (
            <section className="col" style={{ gap: "var(--sp-sm)" }}>
              <span className="section-label">My cards</span>
              <div className="hscroll">
                {creditCards.map((a) => (
                  <CardTile
                    key={a.id}
                    account={a}
                    hidden={hidden}
                    onEdit={() => setEditingAccount(a)}
                  />
                ))}
              </div>
            </section>
          )}

          {deposits.length > 0 && (
            <section className="col" style={{ gap: "var(--sp-sm)" }}>
              <span className="section-label">Accounts</span>
              <div className="hscroll">
                {deposits.map((a) => (
                  <button
                    key={a.id}
                    className="card col"
                    style={{ gap: 4, minWidth: 150, textAlign: "left" }}
                    onClick={() => setEditingAccount(a)}
                  >
                    <span className="tiny muted">{a.bankName}</span>
                    <span className="small truncate" style={{ fontWeight: 600 }}>{a.name}</span>
                    <span className="amount" style={{ fontSize: 17, fontWeight: 700 }}>
                      {money(a.balance, hidden)}
                    </span>
                  </button>
                ))}
              </div>
            </section>
          )}

          {analysis.topMerchants.length > 0 && (
            <section className="card col" style={{ gap: "var(--sp-md)" }}>
              <span className="section-label">Top merchants</span>
              {analysis.topMerchants.map((m) => (
                <div key={m.merchantName} className="spread">
                  <span className="row" style={{ gap: "var(--sp-sm)" }}>
                    <CategoryDot slug={m.categorySlug} size={28} />
                    <span className="col" style={{ gap: 0 }}>
                      <span className="small truncate" style={{ maxWidth: 180 }}>{m.merchantName}</span>
                      <span className="tiny muted">{m.count} txn{m.count === 1 ? "" : "s"}</span>
                    </span>
                  </span>
                  <span className="small amount" style={{ fontWeight: 600 }}>
                    {money(m.amount, hidden)}
                  </span>
                </div>
              ))}
            </section>
          )}
        </>
      )}

      {/* Stable through the day, and the same text the daily push carries —
          a tip that reshuffles on every render just reads as noise. */}
      <section className="card col" style={{ gap: 6 }}>
        <span className="section-label">Money tip</span>
        <p className="small" style={{ margin: 0, lineHeight: 1.5 }}>{tip.text}</p>
      </section>

      {editingAccount && (
        <AccountSheet
          account={editingAccount}
          hidden={hidden}
          onClose={() => setEditingAccount(null)}
          onDone={async (message) => {
            setEditingAccount(null);
            await reloadAccounts();
            onToast(message);
          }}
        />
      )}
    </div>
  );
}

function SpendingCard({
  analysis, hidden,
}: { analysis: ReturnType<typeof analyseMonth>; hidden: boolean }) {
  const usedFraction = analysis.totalIncome > 0
    ? analysis.totalExpenses / analysis.totalIncome
    : 0;
  const barColor =
    usedFraction < 0.7 ? "var(--income-green)"
    : usedFraction < 0.9 ? "var(--warning-amber)"
    : "var(--expense-red)";

  return (
    <section
      className="card col"
      style={{
        gap: "var(--sp-base)",
        background: "linear-gradient(135deg, rgba(123,110,246,0.25), var(--bg-card))",
      }}
    >
      <span className="section-label">Spent this month</span>
      <span className="amount" style={{ fontSize: 34, fontWeight: 700 }}>
        {money(analysis.totalExpenses, hidden)}
      </span>

      {analysis.totalIncome > 0 && (
        <div className="col" style={{ gap: 6 }}>
          <Bar fraction={usedFraction} color={barColor} />
          <div className="spread tiny muted">
            <span>{percent(usedFraction * 100)} of income used</span>
            <span>{money(analysis.totalIncome, hidden)}</span>
          </div>
        </div>
      )}

      <div className="row" style={{ gap: "var(--sp-lg)" }}>
        <Stat label="Income" value={moneyCompact(analysis.totalIncome, hidden)} color="var(--income-green)" />
        <Stat
          label="Savings"
          value={moneyCompact(analysis.savings, hidden)}
          color={analysis.savings >= 0 ? "var(--income-green)" : "var(--expense-red)"}
          note={analysis.totalIncome > 0 ? percent(analysis.savingsRate) : undefined}
        />
      </div>
    </section>
  );
}

function Stat({
  label, value, color, note,
}: { label: string; value: string; color: string; note?: string }) {
  return (
    <div className="col grow" style={{ gap: 2 }}>
      <span className="tiny muted">{label}</span>
      <span className="row" style={{ gap: 6, alignItems: "baseline" }}>
        <span className="amount" style={{ fontSize: 17, fontWeight: 700 }}>{value}</span>
        {note && <span className="tiny" style={{ color }}>{note}</span>}
      </span>
    </div>
  );
}

function CardTile({
  account, hidden, onEdit,
}: { account: Account; hidden: boolean; onEdit: () => void }) {
  const utilisation = account.creditLimit && account.creditLimit > 0
    ? Math.min(1, account.balance / account.creditLimit)
    : null;

  return (
    <button
      className="card col"
      onClick={onEdit}
      style={{
        gap: 6, minWidth: 210, textAlign: "left",
        background: `linear-gradient(135deg, ${account.colorHex}38, var(--bg-card))`,
        border: `1px solid ${account.colorHex}4D`,
      }}
    >
      <div className="spread">
        <span className="small truncate" style={{ fontWeight: 600 }}>{account.name}</span>
        {account.last4 && <span className="tiny muted">••{account.last4}</span>}
      </div>
      <span className="tiny muted">Outstanding</span>
      <span className="amount" style={{ fontSize: 20, fontWeight: 700 }}>
        {money(account.balance, hidden)}
      </span>
      {utilisation !== null && !hidden && (
        <>
          <Bar fraction={utilisation} color={account.colorHex} />
          <span className="tiny muted">
            {percent(utilisation * 100)} of {moneyCompact(account.creditLimit!)} limit
          </span>
        </>
      )}
      {account.statementDay && account.dueDay && (
        <span className="tiny muted">
          Bills {ordinal(account.statementDay)} · due {fullDate(
            creditCardBillDates(account.statementDay, account.dueDay).dueDate,
          )}
        </span>
      )}
    </button>
  );
}

/** Overspending on wants is a warning; under-saving is too. Needs over is fine. */
function offTarget(intent: CategoryIntent, delta: number): boolean {
  if (intent === "saving") return delta < 0;
  return intent === "want" && delta > 0;
}

function ordinal(day: number): string {
  const rem100 = day % 100;
  if (rem100 >= 11 && rem100 <= 13) return `${day}th`;
  switch (day % 10) {
    case 1: return `${day}st`;
    case 2: return `${day}nd`;
    case 3: return `${day}rd`;
    default: return `${day}th`;
  }
}
