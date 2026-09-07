import { useMemo, useState } from "react";
import {
  addMonths, analyseMonth, effectiveIntent, inMonth, needsWants, startOfMonth,
} from "../../domain/analysis";
import { INTENT_META, type CategoryIntent } from "../../domain/types";
import { findCategory } from "../../domain/categories";
import { Bar, EmptyState } from "../components";
import { money, moneyCompact, monthYear, percent } from "../format";
import { useAccounts, useAllTransactions } from "../../state/useStore";
import { NetWorthSection } from "./NetWorth";

export function AnalyticsScreen({
  hidden, onToast,
}: { hidden: boolean; onToast: (m: string) => void }) {
  const { all, loading } = useAllTransactions();
  const { accounts } = useAccounts();
  const [month, setMonth] = useState(() => startOfMonth(Date.now()));
  const [view, setView] = useState<"spending" | "wealth">("spending");

  const monthTxns = useMemo(
    () => all.filter((t) => inMonth(t.date, month)),
    [all, month],
  );
  const analysis = useMemo(() => analyseMonth(month, all), [month, all]);
  const split = useMemo(() => needsWants(monthTxns), [monthTxns]);

  // Trailing six months for the trend bars.
  const trend = useMemo(() => {
    return Array.from({ length: 6 }, (_, i) => {
      const m = addMonths(month, -(5 - i));
      return { month: m, analysis: analyseMonth(m, all) };
    });
  }, [month, all]);

  const peak = Math.max(...trend.map((t) => t.analysis.totalExpenses), 1);
  const isCurrentMonth = month === startOfMonth(Date.now());

  if (loading) {
    return (
      <div className="screen row" style={{ justifyContent: "center", paddingTop: 80 }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div className="screen col" style={{ gap: "var(--sp-lg)" }}>
      <div className="row" style={{ gap: "var(--sp-sm)" }}>
        {(["spending", "wealth"] as const).map((v) => (
          <button
            key={v}
            className="chip grow"
            data-selected={view === v}
            style={{ textAlign: "center", justifyContent: "center" }}
            onClick={() => setView(v)}
          >
            {v === "spending" ? "Spending" : "Net worth"}
          </button>
        ))}
      </div>

      {view === "wealth" ? (
        <NetWorthSection accounts={accounts} hidden={hidden} onToast={onToast} />
      ) : (
        <SpendingView />
      )}
    </div>
  );

  function SpendingView() {
    return (
      <>
      <div className="spread">
        <button className="chip" onClick={() => setMonth(addMonths(month, -1))} aria-label="Previous month">‹</button>
        <div className="col" style={{ alignItems: "center", gap: 0 }}>
          <span className="h2">{monthYear(month)}</span>
          <span className="tiny muted">Analytics</span>
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
        <EmptyState title="No analytics yet" subtitle="Add transactions and this fills in automatically." />
      ) : (
        <>
          <section className="card col" style={{ gap: "var(--sp-md)" }}>
            <span className="section-label">50 / 30 / 20</span>
            {split.total === 0 ? (
              <span className="small muted">No spending this month to split.</span>
            ) : (
              (["need", "want", "saving"] as CategoryIntent[]).map((intent) => {
                const meta = INTENT_META[intent];
                const amount = split[intent];
                const actual = (amount / split.total) * 100;
                // Compare against the 50/30/20 target, not just the raw share —
                // that's what makes the number actionable.
                const delta = actual - meta.targetPercent;
                return (
                  <div key={intent} className="col" style={{ gap: 6 }}>
                    <div className="spread">
                      <span className="small">{meta.label}</span>
                      <span className="row small amount" style={{ gap: 8 }}>
                        <span style={{ fontWeight: 600 }}>{money(amount, hidden)}</span>
                        <span className="muted">{percent(actual)}</span>
                      </span>
                    </div>
                    <Bar fraction={actual / 100} color={meta.color} />
                    <span className="tiny muted">
                      Target {meta.targetPercent}%
                      {Math.abs(delta) >= 1 && (
                        <span style={{ color: overTarget(intent, delta) ? "var(--warning-amber)" : "var(--income-green)" }}>
                          {" "}· {delta > 0 ? "+" : ""}{percent(delta)}
                        </span>
                      )}
                    </span>
                  </div>
                );
              })
            )}
          </section>

          <section className="card col" style={{ gap: "var(--sp-md)" }}>
            <span className="section-label">Last 6 months</span>
            <div
              style={{
                display: "flex", alignItems: "flex-end", gap: "var(--sp-sm)",
                height: 120,
              }}
            >
              {trend.map((t) => {
                const h = Math.max(4, (t.analysis.totalExpenses / peak) * 100);
                const active = t.month === month;
                return (
                  <button
                    key={t.month}
                    onClick={() => setMonth(t.month)}
                    className="col grow"
                    style={{ gap: 4, alignItems: "center", justifyContent: "flex-end", height: "100%" }}
                    title={money(t.analysis.totalExpenses)}
                  >
                    <span className="tiny muted amount">
                      {t.analysis.totalExpenses > 0 ? moneyCompact(t.analysis.totalExpenses, hidden) : ""}
                    </span>
                    <div
                      style={{
                        width: "100%", height: `${h}%`,
                        borderRadius: "var(--r-sm)",
                        background: active ? "var(--brand-primary)" : "var(--bg-elevated)",
                        transition: "height 0.3s ease",
                      }}
                    />
                    <span className="tiny muted">
                      {new Date(t.month).toLocaleString("en-IN", { month: "short" })}
                    </span>
                  </button>
                );
              })}
            </div>
            {analysis.previousMonthExpenses > 0 && (
              <span className="tiny muted">
                {analysis.spendChangePercent >= 0 ? "Up" : "Down"}{" "}
                {percent(Math.abs(analysis.spendChangePercent))} vs last month
              </span>
            )}
          </section>

          <section className="card col" style={{ gap: "var(--sp-md)" }}>
            <span className="section-label">Category breakdown</span>
            {analysis.categoryBreakdown.length === 0 ? (
              <span className="small muted">No spending recorded this month.</span>
            ) : (
              analysis.categoryBreakdown.map((c) => {
                const cat = findCategory(c.categorySlug);
                const intent = effectiveIntentLabel(c.categorySlug);
                return (
                  <div key={c.categorySlug} className="col" style={{ gap: 6 }}>
                    <div className="spread">
                      <span className="row small" style={{ gap: 6 }}>
                        <span style={{ color: cat.colorHex, fontWeight: 600 }}>{cat.name}</span>
                        {intent && <span className="tiny muted">· {intent}</span>}
                      </span>
                      <span className="small amount">
                        {money(c.amount, hidden)} <span className="muted tiny">{percent(c.percent)}</span>
                      </span>
                    </div>
                    <Bar fraction={c.percent / 100} color={cat.colorHex} />
                  </div>
                );
              })
            )}
          </section>
        </>
      )}
      </>
    );
  }
}

/** Wants over target is a warning; needs/savings over target is fine. */
function overTarget(intent: CategoryIntent, delta: number): boolean {
  if (intent === "saving") return delta < 0;
  return delta > 0;
}

function effectiveIntentLabel(slug: string): string | null {
  const intent = effectiveIntent({ categorySlug: slug } as never);
  return intent ? INTENT_META[intent].label : null;
}
