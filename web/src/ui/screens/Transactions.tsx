import { useEffect, useMemo, useRef, useState } from "react";
import { CATEGORIES, findCategory } from "../../domain/categories";
import { moneyPrecise } from "../format";
import {
  DayHeader, EmptyState, Sheet, TransactionRow,
} from "../components";
import {
  confirmReview, deleteTransaction, saveTransaction, setIntentOverride, updateTransaction,
  useAccounts, useKnownTags, usePendingReview, useTransactionFeed,
} from "../../state/useStore";
import { QuickReviewSheet } from "./QuickReview";
import { FilterSheet } from "./FilterSheet";
import {
  activeFilterCount, EMPTY_FILTER, filterSummary, isFilterActive,
} from "../../domain/filters";
import { intentOf, isOverridden, supportsIntent } from "../../domain/intent";
import { INTENT_META, type CategoryIntent, type Transaction } from "../../domain/types";

const QUICK_FILTERS = ["food", "travel", "shopping", "bills", "entertainment"];

export function TransactionsScreen({
  hidden, onToast, onPendingChanged,
}: {
  hidden: boolean;
  onToast: (m: string) => void;
  /** Tells the shell to re-read the review queue, which drives the tab badge. */
  onPendingChanged?: () => void | Promise<void>;
}) {
  const feed = useTransactionFeed();
  const { pending, reload: reloadPending } = usePendingReview();
  const { accounts } = useAccounts();
  const knownTags = useKnownTags();
  const [selected, setSelected] = useState<Transaction | null>(null);
  const [reviewing, setReviewing] = useState(false);
  const [filtering, setFiltering] = useState(false);
  const sentinel = useRef<HTMLDivElement | null>(null);

  const { filter, setFilter } = feed;
  const summary = useMemo(() => filterSummary(filter), [filter]);

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

  async function applyIntent(txn: Transaction, intent: CategoryIntent | undefined) {
    await setIntentOverride(txn, intent);
    await feed.reload();
    onToast(
      intent === undefined ? "Back to its category's default"
        : intent === "saving" ? "Marked as savings"
        : `Marked as a ${INTENT_META[intent].label.replace(/s$/, "").toLowerCase()}`,
    );
  }

  function toggleTag(tag: string) {
    setFilter({
      ...filter,
      tags: filter.tags.includes(tag)
        ? filter.tags.filter((t) => t !== tag)
        : [...filter.tags, tag],
    });
  }

  const categoryChip = (slug: string | null) => {
    const selectedSlug = filter.categories.length === 1 ? filter.categories[0] : null;
    return {
      "data-selected": slug === null ? filter.categories.length === 0 : selectedSlug === slug,
      onClick: () => setFilter({ ...filter, categories: slug === null || selectedSlug === slug ? [] : [slug] }),
    };
  };

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

      <div className="row" style={{ gap: "var(--sp-sm)", marginBottom: "var(--sp-md)" }}>
        <input
          className="field grow"
          placeholder="Search merchants, tags, notes…"
          value={filter.query}
          onChange={(e) => setFilter({ ...filter, query: e.target.value })}
        />
        <button
          className="btn btn-secondary"
          onClick={() => setFiltering(true)}
          style={{ flexShrink: 0 }}
        >
          Filter{activeFilterCount(filter) > 0 ? ` · ${activeFilterCount(filter)}` : ""}
        </button>
      </div>

      {/* PF-17: say what's being hidden. A filter left on is otherwise
          indistinguishable from a month where nothing happened. */}
      {isFilterActive(filter) && (
        <div
          className="card row"
          style={{
            gap: "var(--sp-sm)", flexWrap: "wrap", marginBottom: "var(--sp-md)",
            background: "rgba(123,110,246,0.08)", border: "1px solid rgba(123,110,246,0.3)",
          }}
        >
          <span className="tiny muted">Showing</span>
          {summary.map((label) => (
            <span key={label} className="pill" style={{ background: "var(--bg-elevated)", color: "var(--text-primary)" }}>
              {label}
            </span>
          ))}
          <button className="tiny grow" style={{ textAlign: "right", color: "var(--brand-primary)" }}
            onClick={() => setFilter(EMPTY_FILTER)}>
            Clear
          </button>
        </div>
      )}

      <div className="hscroll" style={{ marginBottom: "var(--sp-base)" }}>
        <button className="chip" {...categoryChip(null)}>All</button>
        {/* Keeps the review queue one tap away even when nothing is pending,
            which is the state the banner above disappears in. */}
        <button
          className="chip"
          data-selected={filter.needsReviewOnly}
          onClick={() => setFilter({ ...filter, needsReviewOnly: !filter.needsReviewOnly })}
        >
          Needs review
        </button>
        {QUICK_FILTERS.map((slug) => (
          <button key={slug} className="chip" {...categoryChip(slug)}>
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
          title={isFilterActive(filter) ? "No matches" : "No transactions yet"}
          subtitle={
            isFilterActive(filter)
              ? "Nothing matches this filter. Clear it to see the whole ledger again."
              : "Connect your Shortcut in Settings, or add one manually with the + button."
          }
          action={isFilterActive(filter)
            ? <button className="btn" onClick={() => setFilter(EMPTY_FILTER)}>Clear filter</button>
            : undefined}
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
                  <TransactionRow
                    txn={txn}
                    hidden={hidden}
                    onClick={() => setSelected(txn)}
                    onSetIntent={(intent) => void applyIntent(txn, intent)}
                    selectedTags={filter.tags}
                    onToggleTag={toggleTag}
                  />
                  {i < group.rows.length - 1 && (
                    <div className="divider" style={{ marginLeft: 68 }} />
                  )}
                </div>
              ))}
            </section>
          ))}
        </div>
      )}

      {/* Swipe is invisible until someone tries it, so say it once. */}
      {feed.groups.length > 0 && (
        <p className="tiny muted" style={{ textAlign: "center", margin: "var(--sp-md) 0 0" }}>
          Swipe a row right for Need, left for Want — or tap its chip to cycle.
        </p>
      )}

      <div ref={sentinel} style={{ height: 1 }} />
      {feed.loadingMore && (
        <div className="row" style={{ justifyContent: "center", padding: "var(--sp-base)" }}>
          <div className="spinner" />
          <span className="small muted">Loading more…</span>
        </div>
      )}

      {filtering && (
        <FilterSheet
          filter={filter}
          knownTags={knownTags}
          onApply={setFilter}
          onClose={() => setFiltering(false)}
        />
      )}

      {reviewing && (
        <QuickReviewSheet
          transactions={pending}
          hidden={hidden}
          onClose={async () => {
            setReviewing(false);
            await Promise.all([feed.reload(), reloadPending(), onPendingChanged?.()]);
          }}
          onDone={async (message) => {
            await Promise.all([feed.reload(), reloadPending(), onPendingChanged?.()]);
            onToast(message);
          }}
        />
      )}

      {selected && (
        <TransactionSheet
          txn={selected}
          hidden={hidden}
          accounts={accounts}
          knownTags={knownTags}
          onClose={() => setSelected(null)}
          onChanged={async (msg) => {
            await Promise.all([feed.reload(), reloadPending(), onPendingChanged?.()]);
            setSelected(null);
            if (msg) onToast(msg);
          }}
        />
      )}
    </div>
  );
}

/** Category grid, shared by the detail sheet and manual entry. */
function CategoryPicker({
  slug, onPick, creditOnly,
}: { slug: string; onPick: (slug: string) => void; creditOnly: boolean }) {
  const pickable = CATEGORIES.filter((c) => (creditOnly ? c.isIncome || c.isTransfer : !c.isIncome));
  return (
    <div
      style={{
        display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))",
        gap: "var(--sp-sm)", margin: "var(--sp-sm) 0 var(--sp-base)",
      }}
    >
      {pickable.map((c) => (
        <button
          key={c.slug}
          onClick={() => onPick(c.slug)}
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
  );
}

/** Tag editor with autocomplete over every tag already in use. */
function TagEditor({
  tags, knownTags, onChange,
}: { tags: string[]; knownTags: string[]; onChange: (tags: string[]) => void }) {
  const [draft, setDraft] = useState("");
  const suggestions = useMemo(() => {
    const d = draft.trim().toLowerCase();
    const pool = knownTags.filter((t) => !tags.includes(t));
    return (d ? pool.filter((t) => t.toLowerCase().includes(d)) : pool).slice(0, 6);
  }, [knownTags, tags, draft]);

  function add(tag: string) {
    const clean = tag.trim().replace(/^#/, "");
    if (clean && !tags.includes(clean)) onChange([...tags, clean]);
    setDraft("");
  }

  return (
    <>
      {tags.length > 0 && (
        <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap", margin: "var(--sp-sm) 0" }}>
          {tags.map((t) => (
            <button key={t} className="chip" data-selected onClick={() => onChange(tags.filter((x) => x !== t))}>
              {t} ✕
            </button>
          ))}
        </div>
      )}
      <input
        className="field"
        placeholder="Add a tag, press Enter"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); add(draft); } }}
      />
      {suggestions.length > 0 && (
        <div className="hscroll" style={{ marginTop: "var(--sp-sm)" }}>
          {suggestions.map((t) => (
            <button key={t} className="chip" onClick={() => add(t)}>+ {t}</button>
          ))}
        </div>
      )}
    </>
  );
}

/** Needs / Wants / Savings, with the category's own answer as the fourth option. */
function IntentPicker({
  txn, value, onChange,
}: {
  txn: Transaction;
  value: CategoryIntent | undefined;
  onChange: (v: CategoryIntent | undefined) => void;
}) {
  const fallback = intentOf({ ...txn, intentOverride: undefined });
  return (
    <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap", margin: "var(--sp-sm) 0 var(--sp-base)" }}>
      <button
        className="chip"
        data-selected={value === undefined}
        onClick={() => onChange(undefined)}
      >
        Default{fallback ? ` (${INTENT_META[fallback].label.replace(/s$/, "")})` : ""}
      </button>
      {(["need", "want", "saving"] as CategoryIntent[]).map((i) => (
        <button
          key={i}
          className="chip"
          data-selected={value === i}
          onClick={() => onChange(i)}
          style={value === i ? { background: INTENT_META[i].color, color: "#fff" } : undefined}
        >
          {INTENT_META[i].label.replace(/s$/, "")}
        </button>
      ))}
    </div>
  );
}

function TransactionSheet({
  txn, hidden, accounts, knownTags, onClose, onChanged,
}: {
  txn: Transaction;
  hidden: boolean;
  accounts: Array<{ id: string; name: string; last4?: string; colorHex: string }>;
  knownTags: string[];
  onClose: () => void;
  onChanged: (message?: string) => void | Promise<void>;
}) {
  const [name, setName] = useState(txn.merchantName || txn.merchantRaw);
  const [slug, setSlug] = useState(txn.categorySlug);
  const [tags, setTags] = useState<string[]>(txn.tags);
  const [notes, setNotes] = useState(txn.notes ?? "");
  const [accountId, setAccountId] = useState(txn.accountId);
  const [recurring, setRecurring] = useState(txn.isRecurring);
  const [intent, setIntent] = useState<CategoryIntent | undefined>(txn.intentOverride);
  const [rememberName, setRememberName] = useState(true);
  const [rememberCategory, setRememberCategory] = useState(true);
  const [applyToPast, setApplyToPast] = useState(true);
  const [busy, setBusy] = useState(false);

  const review = !txn.isConfirmed && txn.confidence < 0.85;
  const categoryChanged = slug !== txn.categorySlug;
  const nameChanged = name !== (txn.merchantName || txn.merchantRaw);

  async function save() {
    setBusy(true);
    // Everything that isn't the merchant-rule machinery goes in one write, so
    // no field can be silently dropped by a partial update (PF-29).
    const next: Transaction = {
      ...txn,
      tags,
      notes: notes.trim() || undefined,
      accountId,
      isRecurring: recurring,
    };
    if (intent === undefined) delete next.intentOverride;
    else next.intentOverride = intent;
    await updateTransaction(next);

    // The rule side only runs when there's something to learn from.
    const updated = (nameChanged || categoryChanged || review)
      ? await confirmReview({
          transaction: next, newName: name, newSlug: slug, newTags: tags,
          rememberName: rememberName && nameChanged,
          rememberCategory: rememberCategory && categoryChanged,
          applyToPast,
        })
      : 0;

    await onChanged(
      updated > 0
        ? `Updated ${updated} past transaction${updated === 1 ? "" : "s"} too`
        : "Saved",
    );
  }

  return (
    <Sheet
      title={review ? "Review transaction" : "Edit transaction"}
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
        {isOverridden(txn) && (
          <span className="tiny" style={{ color: INTENT_META[intentOf(txn)!].color }}>
            You moved this to {INTENT_META[intentOf(txn)!].label.toLowerCase()}
          </span>
        )}
      </div>

      <label className="section-label">Merchant</label>
      <input
        className="field"
        value={name}
        onChange={(e) => setName(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <label className="section-label">Category</label>
      <CategoryPicker slug={slug} onPick={setSlug} creditOnly={txn.type === "credit"} />

      {supportsIntent({ ...txn, categorySlug: slug }) && (
        <>
          <label className="section-label">Counts as</label>
          <IntentPicker txn={{ ...txn, categorySlug: slug }} value={intent} onChange={setIntent} />
        </>
      )}

      {/* PF-13's account chip row. A row saved before its card existed can be
          re-pointed here rather than staying orphaned forever. */}
      <label className="section-label">Account</label>
      <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap", margin: "var(--sp-sm) 0 var(--sp-base)" }}>
        <button className="chip" data-selected={!accountId} onClick={() => setAccountId(undefined)}>
          None
        </button>
        {accounts.map((a) => (
          <button
            key={a.id}
            className="chip"
            data-selected={accountId === a.id}
            onClick={() => setAccountId(a.id)}
            style={accountId === a.id ? { background: a.colorHex, color: "#fff" } : undefined}
          >
            {a.name}{a.last4 ? ` ••${a.last4}` : ""}
          </button>
        ))}
      </div>

      <label className="section-label">Tags</label>
      <TagEditor tags={tags} knownTags={knownTags} onChange={setTags} />

      <label className="section-label" style={{ display: "block", marginTop: "var(--sp-base)" }}>Notes</label>
      <textarea
        className="field"
        rows={2}
        placeholder="Anything worth remembering about this one"
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)", resize: "vertical" }}
      />

      <div className="col" style={{ gap: "var(--sp-sm)" }}>
        <Toggle
          label="Recurring"
          hint="Marks this as a repeating charge"
          checked={recurring}
          onChange={setRecurring}
        />
        {nameChanged && (
          <Toggle label="Remember this name" checked={rememberName} onChange={setRememberName} />
        )}
        {categoryChanged && (
          <Toggle label="Remember this category" checked={rememberCategory} onChange={setRememberCategory} />
        )}
        {categoryChanged && rememberCategory && (
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
        style={{ width: 20, height: 20, accentColor: "var(--brand-primary)", flexShrink: 0 }}
      />
    </label>
  );
}

/** Manual entry — the web equivalent of AddTransactionView. */
export function AddTransactionSheet({
  onClose, onSaved,
}: { onClose: () => void; onSaved: () => void | Promise<void> }) {
  const { accounts } = useAccounts();
  const knownTags = useKnownTags();
  const [amount, setAmount] = useState("");
  const [type, setType] = useState<"debit" | "credit">("debit");
  const [merchant, setMerchant] = useState("");
  const [slug, setSlug] = useState("others");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [accountId, setAccountId] = useState<string | undefined>(undefined);
  const [tags, setTags] = useState<string[]>([]);
  const [notes, setNotes] = useState("");

  const paise = Math.round(Number(amount) * 100);
  const valid = Number.isFinite(paise) && paise > 0;

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
      tags,
      notes: notes.trim() || undefined,
      accountId,
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
      <CategoryPicker slug={slug} onPick={setSlug} creditOnly={type === "credit"} />

      <label className="section-label">Account</label>
      <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap", margin: "var(--sp-sm) 0 var(--sp-base)" }}>
        <button className="chip" data-selected={!accountId} onClick={() => setAccountId(undefined)}>
          None
        </button>
        {accounts.map((a) => (
          <button
            key={a.id}
            className="chip"
            data-selected={accountId === a.id}
            onClick={() => setAccountId(a.id)}
            style={accountId === a.id ? { background: a.colorHex, color: "#fff" } : undefined}
          >
            {a.name}{a.last4 ? ` ••${a.last4}` : ""}
          </button>
        ))}
      </div>

      <label className="section-label">Tags</label>
      <TagEditor tags={tags} knownTags={knownTags} onChange={setTags} />

      <label className="section-label" style={{ display: "block", marginTop: "var(--sp-base)" }}>Notes</label>
      <textarea
        className="field"
        rows={2}
        placeholder="Optional"
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 0", resize: "vertical" }}
      />
    </Sheet>
  );
}
