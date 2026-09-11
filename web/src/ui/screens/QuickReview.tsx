import { useMemo, useState } from "react";
import { Sheet, CategoryDot, Bar } from "../components";
import { fullDate, moneyPrecise } from "../format";
import { CATEGORIES, findCategory } from "../../domain/categories";
import { INTENT_META } from "../../domain/types";
import { categoryIntent } from "../../domain/categories";
import { confirmReview, deleteTransaction, skipReview, useKnownTags } from "../../state/useStore";
import type { Transaction } from "../../domain/types";

/**
 * Step through everything awaiting review, one transaction at a time.
 *
 * The queue is **snapshotted on mount**. Confirming a transaction removes it
 * from the live pending list, so reading that list each render would shift
 * every index underneath the user and silently skip the next item — the same
 * trap the Swift `QuickReviewSheet` had to work around.
 */
export function QuickReviewSheet({
  transactions, hidden, onClose, onDone,
}: {
  transactions: Transaction[];
  hidden: boolean;
  onClose: () => void;
  onDone: (message: string) => void | Promise<void>;
}) {
  const [queue] = useState(() => [...transactions]);
  const [index, setIndex] = useState(0);
  const [reviewed, setReviewed] = useState(0);
  const [busy, setBusy] = useState(false);

  const current = queue[index];

  if (!current) {
    return (
      <Sheet title="Review" onClose={onClose}>
        <div className="col" style={{ alignItems: "center", gap: "var(--sp-md)", padding: "var(--sp-xl) 0" }}>
          <span style={{ fontSize: 40 }} aria-hidden>✓</span>
          <span className="h2">All caught up</span>
          <span className="small muted" style={{ textAlign: "center", maxWidth: 300 }}>
            {reviewed > 0
              ? `${reviewed} transaction${reviewed === 1 ? "" : "s"} sorted. Anything you taught the app will apply automatically next time.`
              : "Nothing is waiting for review."}
          </span>
          <button className="btn" onClick={onClose}>Done</button>
        </div>
      </Sheet>
    );
  }

  const advance = async (counted: boolean) => {
    if (counted) setReviewed((n) => n + 1);
    setBusy(false);
    if (index + 1 >= queue.length) {
      // Let the last card land on the summary rather than closing abruptly.
      setIndex(index + 1);
      await onDone(
        `${counted ? reviewed + 1 : reviewed} transaction${(counted ? reviewed + 1 : reviewed) === 1 ? "" : "s"} reviewed`,
      );
    } else {
      setIndex(index + 1);
    }
  };

  return (
    <Sheet title={`Review ${index + 1} of ${queue.length}`} onClose={onClose}>
      <Bar fraction={index / queue.length} color="var(--brand-primary)" />
      <ReviewCard
        key={current.id}
        txn={current}
        hidden={hidden}
        busy={busy}
        setBusy={setBusy}
        onConfirmed={() => void advance(true)}
        onSkipped={() => void advance(false)}
        onDeleted={() => void advance(false)}
      />
    </Sheet>
  );
}

/**
 * One transaction's review form. Keyed by transaction id so moving to the next
 * one resets every field — carrying the previous merchant's name forward into
 * the next card is exactly the kind of thing that quietly corrupts a ledger.
 */
function ReviewCard({
  txn, hidden, busy, setBusy, onConfirmed, onSkipped, onDeleted,
}: {
  txn: Transaction;
  hidden: boolean;
  busy: boolean;
  setBusy: (v: boolean) => void;
  onConfirmed: () => void;
  onSkipped: () => void;
  onDeleted: () => void;
}) {
  const [name, setName] = useState(txn.merchantName || txn.merchantRaw);
  const [slug, setSlug] = useState(txn.categorySlug);
  const [tags, setTags] = useState<string[]>(txn.tags);
  const [tagDraft, setTagDraft] = useState("");
  const [rememberName, setRememberName] = useState(true);
  const [rememberCategory, setRememberCategory] = useState(true);
  const [applyToPast, setApplyToPast] = useState(true);
  const knownTags = useKnownTags();

  const pickable = CATEGORIES.filter((c) =>
    txn.type === "credit" ? c.isIncome || c.isTransfer : !c.isIncome,
  );
  const intent = categoryIntent(slug);

  const suggestions = useMemo(() => {
    const draft = tagDraft.trim().toLowerCase();
    const pool = knownTags.filter((t) => !tags.includes(t));
    return (draft ? pool.filter((t) => t.toLowerCase().includes(draft)) : pool).slice(0, 6);
  }, [knownTags, tags, tagDraft]);

  function addTag(tag: string) {
    const clean = tag.trim();
    if (clean && !tags.includes(clean)) setTags([...tags, clean]);
    setTagDraft("");
  }

  return (
    <>
      <div className="col" style={{ alignItems: "center", gap: 6, margin: "var(--sp-lg) 0" }}>
        <CategoryDot slug={slug} size={48} />
        <span
          className="amount"
          style={{
            fontSize: 32, fontWeight: 700,
            color: txn.type === "credit" ? "var(--income-green)" : "var(--text-primary)",
          }}
        >
          {txn.type === "credit" ? "+" : "−"}{moneyPrecise(txn.amount, hidden)}
        </span>
        <span className="tiny muted">
          {fullDate(txn.date)} · {txn.source.toUpperCase()}
        </span>
        <span className="tiny muted">
          Guessed {findCategory(txn.categorySlug).name} · {Math.round(txn.confidence * 100)}% sure
        </span>
      </div>

      <label className="section-label">Merchant</label>
      <input
        className="field"
        value={name}
        onChange={(e) => setName(e.target.value)}
        style={{ margin: "var(--sp-xs) 0 var(--sp-base)" }}
      />

      <div className="spread">
        <span className="section-label">Category</span>
        {/* Showing the 50/30/20 bucket here is the point of categorising at
            all — it makes the consequence of the choice visible. */}
        {intent && (
          <span className="tiny" style={{ color: INTENT_META[intent].color }}>
            counts as {INTENT_META[intent].label.toLowerCase()}
          </span>
        )}
      </div>
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

      <label className="section-label">Tags</label>
      <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap", margin: "var(--sp-sm) 0" }}>
        {tags.map((t) => (
          <button key={t} className="chip" data-selected onClick={() => setTags(tags.filter((x) => x !== t))}>
            {t} ✕
          </button>
        ))}
      </div>
      <input
        className="field"
        placeholder="Add a tag, press Enter"
        value={tagDraft}
        onChange={(e) => setTagDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter") { e.preventDefault(); addTag(tagDraft); }
        }}
      />
      {suggestions.length > 0 && (
        <div className="hscroll" style={{ marginTop: "var(--sp-sm)" }}>
          {suggestions.map((t) => (
            <button key={t} className="chip" onClick={() => addTag(t)}>+ {t}</button>
          ))}
        </div>
      )}

      <div className="col" style={{ gap: "var(--sp-sm)", marginTop: "var(--sp-base)" }}>
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

      <div className="col" style={{ gap: "var(--sp-sm)", marginTop: "var(--sp-lg)" }}>
        <button
          className="btn btn-block"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            await confirmReview({
              transaction: txn, newName: name, newSlug: slug, newTags: tags,
              rememberName, rememberCategory, applyToPast,
            });
            onConfirmed();
          }}
        >
          Save and next
        </button>
        <div className="row" style={{ gap: "var(--sp-sm)" }}>
          <button
            className="btn btn-secondary grow"
            disabled={busy}
            onClick={async () => {
              setBusy(true);
              // Skipping still confirms: "the guess was fine" is a real answer,
              // and leaving it pending forever makes the queue meaningless.
              await skipReview(txn);
              onSkipped();
            }}
          >
            Looks right
          </button>
          <button
            className="btn btn-secondary grow"
            style={{ color: "var(--expense-red)" }}
            disabled={busy}
            onClick={async () => {
              setBusy(true);
              await deleteTransaction(txn.id);
              onDeleted();
            }}
          >
            Delete
          </button>
        </div>
      </div>
    </>
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
