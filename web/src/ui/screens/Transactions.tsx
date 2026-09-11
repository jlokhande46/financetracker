import { useEffect, useRef, useState } from "react";
import { CATEGORIES, findCategory } from "../../domain/categories";
import { moneyPrecise } from "../format";
import {
  DayHeader, EmptyState, Sheet, TransactionRow,
} from "../components";
import {
  confirmReview, deleteTransaction, saveTransaction, usePendingReview, useTransactionFeed,
} from "../../state/useStore";
import { QuickReviewSheet } from "./QuickReview";
import type { Transaction } from "../../domain/types";

const QUICK_FILTERS = ["food", "travel", "shopping", "bills", "entertainment"];

export function TransactionsScreen({
  hidden, onToast,
}: { hidden: boolean; onToast: (m: string) => void }) {
  const feed = useTransactionFeed();
  const { pending, reload: reloadPending } = usePendingReview();
  const [selected, setSelected] = useState<Transaction | null>(null);
  const [reviewing, setReviewing] = useState(false);
  const sentinel = useRef<HTMLDivElement | null>(null);

  // Infinite scroll via IntersectionObserver rather than firing on every row's
  // mount — the observer only wakes when the sentinel actually reaches the
  // viewport, so scrolling stays free of per-row work.
  useEffect(() => {
    const node = sentinel.current;
    if (!node || !feed.hasMore) return;
    const io = new IntersectionObserver(
      (entries) => { if (entries[0]?.isIntersecting) void feed.loadMore(); },
      { rootMargin: "400px" },
    );
    io.observe(node);
    return () => io.disconnect();
  }, [feed.hasMore, feed.loadMore, feed]);

  return (
    <div className="screen">
      <h1 className="h1" style={{ margin: "0 0 var(--sp-base)" }}>Transactions</h1>

      {/* The queue has to be reachable from where the transactions are, not
          only from a dashboard card the user has already scrolled past. */}
      {pending.length > 0 && (
        <button
          className="card spread"
          onClick={() => setReviewing(true)}
          style={{
            marginBottom: "var(--sp-md)", textAlign: "left",
            background: "rgba(255,181,69,0.08)",
            border: "1px solid rgba(255,181,69,0.3)",
          }}
        >
          <span className="col" style={{ gap: 2 }}>
            <span style={{ fontWeight: 600 }}>
              Review {pending.length} transaction{pending.length === 1 ? "" : "s"}
            </span>
            <span className="tiny muted">
              Sort them one at a time — the app learns each merchant as you go
            </span>
          </span>
          <span className="muted">›</span>
        </button>
      )}

      <input
        className="field"
        placeholder="Search merchants, categories…"
        value={feed.query}
        onChange={(e) => feed.setQuery(e.target.value)}
        style={{ marginBottom: "var(--sp-md)" }}
      />

      <div className="hscroll" style={{ marginBottom: "var(--sp-base)" }}>
        <button
          className="chip"
          data-selected={feed.category === null}
          onClick={() => feed.setCategory(null)}
        >
          All
        </button>
        {QUICK_FILTERS.map((slug) => (
          <button
            key={slug}
            className="chip"
            data-selected={feed.category === slug}
            onClick={() => feed.setCategory(feed.category === slug ? null : slug)}
          >
            {findCategory(slug).name}
          </button>
        ))}
      </div>

      {feed.loading ? (
        <div className="row" style={{ justifyContent: "center", padding: "var(--sp-xxl)" }}>
          <div className="spinner" />
        </div>
      ) : feed.groups.length === 0 ? (
        <EmptyState
          title={feed.query || feed.category ? "No matches" : "No transactions yet"}
          subtitle={
            feed.query || feed.category
              ? "Try a different search or clear the filter."
              : "Connect your Shortcut in Settings, or add one manually with the + button."
          }
        />
      ) : (
        <div className="card" style={{ padding: 0, overflow: "hidden" }}>
          {feed.groups.map((group) => (
            <section key={group.key}>
              <DayHeader
                label={group.key}
                debitTotal={group.debitTotal}
                creditTotal={group.creditTotal}
                hidden={hidden}
              />
              {group.rows.map((txn, i) => (
                <div key={txn.id}>
                  <TransactionRow txn={txn} hidden={hidden} onClick={() => setSelected(txn)} />
                  {i < group.rows.length - 1 && (
                    <div className="divider" style={{ marginLeft: 68 }} />
                  )}
                </div>
              ))}
            </section>
          ))}
        </div>
      )}

      <div ref={sentinel} style={{ height: 1 }} />
      {feed.loadingMore && (
        <div className="row" style={{ justifyContent: "center", padding: "var(--sp-base)" }}>
          <div className="spinner" />
          <span className="small muted">Loading more…</span>
        </div>
      )}

      {reviewing && (
        <QuickReviewSheet
          transactions={pending}
          hidden={hidden}
          onClose={async () => {
            setReviewing(false);
            await Promise.all([feed.reload(), reloadPending()]);
          }}
          onDone={async (message) => {
            await Promise.all([feed.reload(), reloadPending()]);
            onToast(message);
          }}
        />
      )}

      {selected && (
        <TransactionSheet
          txn={selected}
          hidden={hidden}
          onClose={() => setSelected(null)}
          onChanged={async (msg) => {
            await feed.reload();
            setSelected(null);
            if (msg) onToast(msg);
          }}
        />
      )}
    </div>
  );
}

function TransactionSheet({
  txn, hidden, onClose, onChanged,
}: {
  txn: Transaction;
  hidden: boolean;
  onClose: () => void;
  onChanged: (message?: string) => void | Promise<void>;
}) {
  const [name, setName] = useState(txn.merchantName || txn.merchantRaw);
  const [slug, setSlug] = useState(txn.categorySlug);
  const [rememberName, setRememberName] = useState(true);
  const [rememberCategory, setRememberCategory] = useState(true);
  const [applyToPast, setApplyToPast] = useState(true);
  const [busy, setBusy] = useState(false);

  const needsReview = !txn.isConfirmed && txn.confidence < 0.85;
  const pickable = CATEGORIES.filter((c) =>
    txn.type === "credit" ? c.isIncome || c.isTransfer : !c.isIncome,
  );

  async function save() {
    setBusy(true);
    const updated = await confirmReview({
      transaction: txn, newName: name, newSlug: slug,
      rememberName, rememberCategory, applyToPast,
    });
    await onChanged(
      updated > 0
        ? `Updated ${updated} past transaction${updated === 1 ? "" : "s"} too`
        : "Saved",
    );
  }

  return (
    <Sheet
      title={needsReview ? "Review transaction" : "Edit transaction"}
      onClose={onClose}
      footer={
        <div className="col" style={{ gap: "var(--sp-sm)" }}>
          <button className="btn btn-block" onClick={() => void save()} disabled={busy}>
            {busy ? "Saving…" : "Save"}
          </button>
          <button
            className="btn btn-block btn-secondary"
            style={{ color: "var(--expense-red)" }}
            onClick={async () => {
              setBusy(true);
              await deleteTransaction(txn.id);
              await onChanged("Deleted");
            }}
            disabled={busy}
          >
            Delete
          </button>
        </div>
      }
    >
      <div className="col" style={{ alignItems: "center", gap: 4, marginBottom: "var(--sp-lg)" }}>
        <span
          className="amount"
          style={{
            fontSize: 34, fontWeight: 700,
            color: txn.type === "credit" ? "var(--income-green)" : "var(--text-primary)",
          }}
        >
          {txn.type === "credit" ? "+" : "−"}{moneyPrecise(txn.amount, hidden)}
        </span>
        <span className="tiny muted">
          {new Date(txn.date).toLocaleString("en-IN")} · {txn.source.toUpperCase()}
        </span>
      </div>

      <label className="section-label">Merchant</label>
      <input
        className="field"
        value={name}
        onChange={(e) => setName(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Category</label>
      <div
        style={{
          display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))",
          gap: "var(--sp-sm)", margin: "var(--sp-sm) 0 var(--sp-base)",
        }}
      >
        {pickable.map((c) => (
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

      <div className="col" style={{ gap: "var(--sp-sm)" }}>
        <Toggle label="Remember this name" checked={rememberName} onChange={setRememberName} />
        <Toggle label="Remember this category" checked={rememberCategory} onChange={setRememberCategory} />
        {rememberCategory && (
          <Toggle
            label="Fix past transactions too"
            hint="Re-categorises every past transaction from this merchant"
            checked={applyToPast}
            onChange={setApplyToPast}
          />
        )}
      </div>

      {txn.rawContent && (
        <details style={{ marginTop: "var(--sp-base)" }}>
          <summary className="small muted" style={{ cursor: "pointer" }}>Original message</summary>
          <p
            className="tiny muted"
            style={{
              fontFamily: "ui-monospace, monospace", whiteSpace: "pre-wrap",
              background: "var(--bg-card)", padding: "var(--sp-md)",
              borderRadius: "var(--r-md)", marginTop: "var(--sp-sm)",
            }}
          >
            {txn.rawContent}
          </p>
        </details>
      )}
    </Sheet>
  );
}

function Toggle({
  label, hint, checked, onChange,
}: { label: string; hint?: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="spread card" style={{ padding: "var(--sp-md)", cursor: "pointer" }}>
      <span className="col" style={{ gap: 2 }}>
        <span className="small">{label}</span>
        {hint && <span className="tiny muted">{hint}</span>}
      </span>
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        style={{ width: 20, height: 20, accentColor: "var(--brand-primary)" }}
      />
    </label>
  );
}

/** Manual entry — the web equivalent of AddTransactionView. */
export function AddTransactionSheet({
  onClose, onSaved,
}: { onClose: () => void; onSaved: () => void | Promise<void> }) {
  const [amount, setAmount] = useState("");
  const [type, setType] = useState<"debit" | "credit">("debit");
  const [merchant, setMerchant] = useState("");
  const [slug, setSlug] = useState("others");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));

  const paise = Math.round(Number(amount) * 100);
  const valid = Number.isFinite(paise) && paise > 0;
  const pickable = CATEGORIES.filter((c) => (type === "credit" ? c.isIncome : !c.isIncome));

  async function save() {
    if (!valid) return;
    // Keep the current time-of-day so same-day manual entries stay ordered
    // relative to captured ones.
    const now = new Date();
    const picked = new Date(date);
    picked.setHours(now.getHours(), now.getMinutes(), now.getSeconds());

    await saveTransaction({
      id: crypto.randomUUID(),
      amount: paise,
      type,
      merchantRaw: merchant,
      merchantName: merchant,
      categorySlug: slug,
      date: picked.getTime(),
      source: "manual",
      confidence: 1,
      isConfirmed: true,
      isRecurring: false,
      tags: [],
      createdAt: Date.now(),
    });
    await onSaved();
  }

  return (
    <Sheet
      title="Add transaction"
      onClose={onClose}
      footer={
        <button className="btn btn-block" disabled={!valid} onClick={() => void save()}>
          Add transaction
        </button>
      }
    >
      <label className="section-label">Amount</label>
      <input
        className="field amount"
        type="number"
        inputMode="decimal"
        placeholder="0"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        style={{ fontSize: 28, fontWeight: 700, margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <div className="row" style={{ gap: "var(--sp-sm)", marginBottom: "var(--sp-base)" }}>
        {(["debit", "credit"] as const).map((t) => (
          <button
            key={t}
            onClick={() => { setType(t); setSlug(t === "credit" ? "salary" : "others"); }}
            className="grow"
            style={{
              padding: 10, borderRadius: "var(--r-md)",
              background: type === t
                ? (t === "debit" ? "var(--expense-red)" : "var(--income-green)")
                : "var(--bg-card)",
              color: type === t ? "#fff" : "var(--text-secondary)",
              fontWeight: 600,
            }}
          >
            {t === "debit" ? "Expense" : "Income"}
          </button>
        ))}
      </div>

      <label className="section-label">Merchant</label>
      <input
        className="field"
        placeholder="e.g. Swiggy"
        value={merchant}
        onChange={(e) => setMerchant(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Date</label>
      <input
        className="field"
        type="date"
        value={date}
        onChange={(e) => setDate(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Category</label>
      <div
        style={{
          display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))",
          gap: "var(--sp-sm)", marginTop: "var(--sp-sm)",
        }}
      >
        {pickable.map((c) => (
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
    </Sheet>
  );
}
