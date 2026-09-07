import { useMemo, useState } from "react";
import { Bar, EmptyState, Sheet } from "../components";
import { fullDate, money, moneyCompact, percent } from "../format";
import {
  holdingReturns, INVESTMENT_META, INVESTMENT_TYPES, STALE_AFTER_DAYS,
  type InvestmentHolding, type InvestmentType,
} from "../../domain/investments";
import { deleteHolding, saveHolding, useWealth } from "../../state/useWealth";
import { toRupees, type Account } from "../../domain/types";

/**
 * Net worth and the holdings behind it.
 *
 * Values are entered by hand — there's no live NAV feed, on purpose. Every
 * Indian quote API needs a key and most rate-limit; a portfolio that silently
 * stops updating is worse than one you knowingly refresh. So the UI leans on
 * showing how stale each figure is instead of pretending it's live.
 */
export function NetWorthSection({
  accounts, hidden, onToast,
}: {
  accounts: Account[];
  hidden: boolean;
  onToast: (m: string) => void;
}) {
  const wealth = useWealth(accounts);
  const [editing, setEditing] = useState<InvestmentHolding | "new" | null>(null);
  const { netWorth, trend, holdings } = wealth;

  const byType = useMemo(() => {
    const map = new Map<InvestmentType, number>();
    for (const h of holdings) map.set(h.type, (map.get(h.type) ?? 0) + h.currentValue);
    return [...map.entries()].sort((a, b) => b[1] - a[1]);
  }, [holdings]);

  const stale = holdings.filter(
    (h) => holdingReturns(h).staleDays > STALE_AFTER_DAYS,
  ).length;

  return (
    <>
      <section className="card col" style={{ gap: "var(--sp-base)" }}>
        <span className="section-label">Net worth</span>
        <span className="amount" style={{ fontSize: 30, fontWeight: 700 }}>
          {money(netWorth.netWorth, hidden)}
        </span>

        {trend.change !== null && (
          <span className="tiny" style={{
            color: trend.change >= 0 ? "var(--income-green)" : "var(--expense-red)",
          }}>
            {trend.change >= 0 ? "Up" : "Down"} {moneyCompact(Math.abs(trend.change), hidden)}
            {trend.changePercent !== null && ` (${percent(Math.abs(trend.changePercent))})`}
            {" "}over {trend.points.length} months
          </span>
        )}

        {trend.points.length >= 2 && <TrendChart points={trend.points} hidden={hidden} />}

        <div className="col" style={{ gap: "var(--sp-sm)" }}>
          <Line label="Cash" value={money(netWorth.cash, hidden)} />
          <Line label="Investments" value={money(netWorth.investments, hidden)} />
          <Line
            label="Card outstanding"
            // No minus sign on zero — "−₹0" reads as a mistake.
            value={netWorth.liabilities > 0
              ? `−${money(netWorth.liabilities, hidden)}`
              : money(0, hidden)}
            color={netWorth.liabilities > 0 ? "var(--expense-red)" : undefined}
          />
        </div>

        {netWorth.investments > 0 && netWorth.costBasisCoverage > 0 && (
          <span className="tiny muted">
            {netWorth.investmentGain >= 0 ? "Up" : "Down"}{" "}
            {money(Math.abs(netWorth.investmentGain), hidden)} on invested cost
            {netWorth.costBasisCoverage < 0.99 &&
              ` · across ${percent(netWorth.costBasisCoverage * 100)} of the portfolio`}
          </span>
        )}
      </section>

      <section className="col" style={{ gap: "var(--sp-sm)" }}>
        <div className="spread">
          <span className="section-label">Holdings</span>
          {stale > 0 && (
            <span className="tiny" style={{ color: "var(--warning-amber)" }}>
              {stale} need refreshing
            </span>
          )}
        </div>

        {holdings.length === 0 ? (
          <EmptyState
            title="No holdings tracked"
            subtitle="Add your mutual funds, stocks, FDs or gold and update the values when you check your portfolio. Nothing is fetched automatically — no API keys, nothing leaves the device."
            action={<button className="btn" onClick={() => setEditing("new")}>Add a holding</button>}
          />
        ) : (
          <>
            {byType.length > 1 && (
              <div className="card col" style={{ gap: "var(--sp-sm)" }}>
                {byType.map(([type, value]) => (
                  <div key={type} className="col" style={{ gap: 4 }}>
                    <div className="spread tiny">
                      <span>{INVESTMENT_META[type].label}</span>
                      <span className="muted amount">
                        {money(value, hidden)} · {percent((value / netWorth.investments) * 100)}
                      </span>
                    </div>
                    <Bar
                      fraction={value / netWorth.investments}
                      color={INVESTMENT_META[type].color}
                    />
                  </div>
                ))}
              </div>
            )}

            {holdings.map((h) => (
              <HoldingCard key={h.id} holding={h} hidden={hidden} onEdit={() => setEditing(h)} />
            ))}

            <button className="btn btn-secondary btn-block" onClick={() => setEditing("new")}>
              Add a holding
            </button>
          </>
        )}
      </section>

      {editing && (
        <HoldingSheet
          holding={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onDone={async (message) => {
            setEditing(null);
            await wealth.reload();
            onToast(message);
          }}
        />
      )}
    </>
  );
}

function Line({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="spread">
      <span className="small muted">{label}</span>
      <span className="small amount" style={{ fontWeight: 600, color }}>{value}</span>
    </div>
  );
}

/**
 * Sparkline of the monthly net-worth points.
 *
 * The baseline is the minimum, not zero — the interesting part is the shape of
 * the change, and anchoring at zero flattens a year of real movement into a
 * straight line when the numbers are large.
 */
function TrendChart({ points, hidden }: { points: Array<{ month: string; value: number }>; hidden: boolean }) {
  const values = points.map((p) => p.value);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || 1;
  const w = 100, h = 40;

  const coords = points.map((p, i) => ({
    x: points.length === 1 ? w / 2 : (i / (points.length - 1)) * w,
    y: h - ((p.value - min) / span) * h,
  }));
  const line = coords.map((c, i) => `${i === 0 ? "M" : "L"}${c.x.toFixed(1)},${c.y.toFixed(1)}`).join(" ");
  const area = `${line} L${w},${h} L0,${h} Z`;
  const rising = values[values.length - 1]! >= values[0]!;
  const stroke = rising ? "var(--income-green)" : "var(--expense-red)";

  return (
    <div className="col" style={{ gap: 4 }}>
      <svg
        viewBox={`0 0 ${w} ${h}`}
        preserveAspectRatio="none"
        style={{ width: "100%", height: 64, overflow: "visible" }}
        role="img"
        aria-label={`Net worth over ${points.length} months`}
      >
        <path d={area} fill={stroke} opacity={0.12} />
        <path d={line} fill="none" stroke={stroke} strokeWidth={2} vectorEffect="non-scaling-stroke" />
        <circle cx={coords[coords.length - 1]!.x} cy={coords[coords.length - 1]!.y} r={2.5} fill={stroke} />
      </svg>
      <div className="spread tiny muted">
        <span>{monthLabel(points[0]!.month)}</span>
        {!hidden && <span className="amount">{moneyCompact(min)}–{moneyCompact(max)}</span>}
        <span>{monthLabel(points[points.length - 1]!.month)}</span>
      </div>
    </div>
  );
}

function monthLabel(key: string): string {
  const [y, m] = key.split("-").map(Number);
  return new Date(y!, m! - 1, 1).toLocaleString("en-IN", { month: "short", year: "2-digit" });
}

function HoldingCard({
  holding, hidden, onEdit,
}: { holding: InvestmentHolding; hidden: boolean; onEdit: () => void }) {
  const r = holdingReturns(holding);
  const meta = INVESTMENT_META[holding.type];
  const isStale = r.staleDays > STALE_AFTER_DAYS;

  return (
    <button className="card col" style={{ gap: 6, textAlign: "left" }} onClick={onEdit}>
      <div className="spread">
        <span className="col" style={{ gap: 2, minWidth: 0 }}>
          <span className="truncate" style={{ fontWeight: 600 }}>{holding.name}</span>
          <span className="tiny" style={{ color: meta.color }}>{meta.label}</span>
        </span>
        <span className="col" style={{ alignItems: "flex-end", gap: 2 }}>
          <span className="amount" style={{ fontWeight: 600 }}>
            {money(holding.currentValue, hidden)}
          </span>
          {r.percent !== null && (
            <span className="tiny" style={{
              color: r.gain >= 0 ? "var(--income-green)" : "var(--expense-red)",
            }}>
              {r.gain >= 0 ? "+" : "−"}{money(Math.abs(r.gain), hidden)} ({percent(Math.abs(r.percent), 1)})
            </span>
          )}
        </span>
      </div>
      <span className="tiny" style={{ color: isStale ? "var(--warning-amber)" : "var(--text-secondary)" }}>
        {r.staleDays === 0
          ? "Updated today"
          : `Updated ${fullDate(holding.lastUpdated)}${isStale ? ` · ${r.staleDays} days ago` : ""}`}
      </span>
    </button>
  );
}

function HoldingSheet({
  holding, onClose, onDone,
}: {
  holding: InvestmentHolding | null;
  onClose: () => void;
  onDone: (message: string) => void | Promise<void>;
}) {
  const [name, setName] = useState(holding?.name ?? "");
  const [type, setType] = useState<InvestmentType>(holding?.type ?? "mf");
  const [value, setValue] = useState(
    holding && holding.currentValue > 0 ? String(toRupees(holding.currentValue)) : "",
  );
  const [invested, setInvested] = useState(
    holding && holding.investedAmount > 0 ? String(toRupees(holding.investedAmount)) : "",
  );
  const [busy, setBusy] = useState(false);

  const valuePaise = Math.round(Number(value) * 100);
  const investedPaise = invested.trim() === "" ? 0 : Math.round(Number(invested) * 100);
  const valid = name.trim().length > 0 && Number.isFinite(valuePaise) && valuePaise > 0;
  // Only a changed value re-stamps the date; renaming a holding shouldn't make
  // a months-old figure look freshly checked.
  const valueChanged = holding ? valuePaise !== holding.currentValue : true;

  async function save() {
    if (!valid) return;
    setBusy(true);
    await saveHolding({
      id: holding?.id ?? crypto.randomUUID(),
      name: name.trim(),
      type,
      currentValue: valuePaise,
      investedAmount: Number.isFinite(investedPaise) ? investedPaise : 0,
      lastUpdated: valueChanged ? Date.now() : holding!.lastUpdated,
      note: holding?.note,
      createdAt: holding?.createdAt ?? Date.now(),
    });
    await onDone(holding ? "Holding updated" : "Holding added");
  }

  return (
    <Sheet
      title={holding ? "Edit holding" : "New holding"}
      onClose={onClose}
      footer={
        <div className="col" style={{ gap: "var(--sp-sm)" }}>
          <button className="btn btn-block" disabled={!valid || busy} onClick={() => void save()}>
            {busy ? "Saving…" : "Save holding"}
          </button>
          {holding && (
            <button
              className="btn btn-block btn-secondary"
              style={{ color: "var(--expense-red)" }}
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                await deleteHolding(holding.id);
                await onDone("Holding removed");
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
        placeholder="e.g. Parag Parikh Flexi Cap"
        value={name}
        onChange={(e) => setName(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Current value</label>
      <input
        className="field amount"
        type="number"
        inputMode="decimal"
        placeholder="0"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        style={{ fontSize: 24, fontWeight: 700, margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Invested so far</label>
      <input
        className="field amount"
        type="number"
        inputMode="decimal"
        placeholder="Optional"
        value={invested}
        onChange={(e) => setInvested(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-xs)" }}
      />
      <span className="tiny muted">
        Leave blank if you don't know what you put in — the value still counts towards net
        worth, it just won't show a return.
      </span>

      <label className="section-label" style={{ display: "block", marginTop: "var(--sp-base)" }}>
        Type
      </label>
      <div
        style={{
          display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(104px, 1fr))",
          gap: "var(--sp-sm)", marginTop: "var(--sp-sm)",
        }}
      >
        {INVESTMENT_TYPES.map((t) => (
          <button
            key={t}
            onClick={() => setType(t)}
            style={{
              padding: "8px 6px", borderRadius: "var(--r-md)", fontSize: 12,
              background: type === t ? INVESTMENT_META[t].color : "var(--bg-elevated)",
              color: type === t ? "#fff" : "var(--text-secondary)",
            }}
          >
            {INVESTMENT_META[t].label}
          </button>
        ))}
      </div>
    </Sheet>
  );
}
