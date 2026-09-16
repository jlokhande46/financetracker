import { useState } from "react";
import { Sheet } from "../components";
import { CATEGORIES } from "../../domain/categories";
import { EMPTY_FILTER, endOfDay, startOfDay, type TransactionFilter } from "../../domain/filters";
import { SOURCE_LABEL, type TransactionSource, type TransactionType } from "../../domain/types";

const SOURCES: TransactionSource[] = ["sms", "pdf", "manual", "upi", "email", "aa"];

/**
 * The feed's filter sheet, ported from `TransactionFilterSheet.swift`: type,
 * category, source, tags, date range, amount range — plus the review queue,
 * which lives here as well so it stays reachable after the banner is cleared.
 *
 * Edits are held locally and applied on "Show results". A filter that
 * re-queries on every tap makes choosing a second category feel like fighting
 * the list.
 */
export function FilterSheet({
  filter, knownTags, onApply, onClose,
}: {
  filter: TransactionFilter;
  knownTags: string[];
  onApply: (next: TransactionFilter) => void;
  onClose: () => void;
}) {
  const [draft, setDraft] = useState<TransactionFilter>(filter);

  const toggle = <T,>(list: T[], value: T): T[] =>
    list.includes(value) ? list.filter((v) => v !== value) : [...list, value];

  // Functional update, not `{ ...draft, ...patch }`: two taps inside one frame
  // — easy on touch — would otherwise both read the same stale draft and the
  // first selection would silently vanish.
  const set = (patch: Partial<TransactionFilter>) => setDraft((d) => ({ ...d, ...patch }));
  const update = (fn: (d: TransactionFilter) => Partial<TransactionFilter>) =>
    setDraft((d) => ({ ...d, ...fn(d) }));

  const dateValue = (ms: number | undefined) =>
    ms === undefined ? "" : new Date(ms).toISOString().slice(0, 10);
  const rupeeValue = (p: number | undefined) => (p === undefined ? "" : String(p / 100));

  return (
    <Sheet
      title="Filter"
      onClose={onClose}
      footer={
        <div className="row" style={{ gap: "var(--sp-sm)" }}>
          <button
            className="btn btn-secondary grow"
            onClick={() => { onApply(EMPTY_FILTER); onClose(); }}
          >
            Clear all
          </button>
          <button className="btn grow" onClick={() => { onApply(draft); onClose(); }}>
            Show results
          </button>
        </div>
      }
    >
      <div className="col" style={{ gap: "var(--sp-lg)" }}>
        <section className="col" style={{ gap: "var(--sp-sm)" }}>
          <span className="section-label">Status</span>
          <button
            className="chip"
            data-selected={draft.needsReviewOnly}
            onClick={() => update((d) => ({ needsReviewOnly: !d.needsReviewOnly }))}
            style={{ alignSelf: "flex-start" }}
          >
            Needs review
          </button>
        </section>

        <section className="col" style={{ gap: "var(--sp-sm)" }}>
          <span className="section-label">Type</span>
          <div className="row" style={{ gap: "var(--sp-sm)" }}>
            {(["debit", "credit"] as TransactionType[]).map((t) => (
              <button
                key={t}
                className="chip"
                data-selected={draft.types.includes(t)}
                onClick={() => update((d) => ({ types: toggle(d.types, t) }))}
              >
                {t === "debit" ? "Expenses" : "Income"}
              </button>
            ))}
          </div>
        </section>

        <section className="col" style={{ gap: "var(--sp-sm)" }}>
          <span className="section-label">Category</span>
          <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap" }}>
            {CATEGORIES.map((c) => (
              <button
                key={c.slug}
                className="chip"
                data-selected={draft.categories.includes(c.slug)}
                onClick={() => update((d) => ({ categories: toggle(d.categories, c.slug) }))}
                style={draft.categories.includes(c.slug)
                  ? { background: c.colorHex, color: "#fff" }
                  : undefined}
              >
                {c.name}
              </button>
            ))}
          </div>
        </section>

        <section className="col" style={{ gap: "var(--sp-sm)" }}>
          <span className="section-label">Source</span>
          <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap" }}>
            {SOURCES.map((s) => (
              <button
                key={s}
                className="chip"
                data-selected={draft.sources.includes(s)}
                onClick={() => update((d) => ({ sources: toggle(d.sources, s) }))}
              >
                {SOURCE_LABEL[s]}
              </button>
            ))}
          </div>
        </section>

        {/* The chip cloud the Swift sheet had. Tags only exist once the user has
            made some, so an empty state here is normal rather than broken. */}
        <section className="col" style={{ gap: "var(--sp-sm)" }}>
          <span className="section-label">Tags</span>
          {knownTags.length === 0 ? (
            <span className="tiny muted">
              No tags yet. Add them while reviewing a transaction or from its detail sheet.
            </span>
          ) : (
            <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap" }}>
              {knownTags.map((tag) => (
                <button
                  key={tag}
                  className="chip"
                  data-selected={draft.tags.includes(tag)}
                  onClick={() => update((d) => ({ tags: toggle(d.tags, tag) }))}
                >
                  #{tag}
                </button>
              ))}
            </div>
          )}
        </section>

        <section className="col" style={{ gap: "var(--sp-sm)" }}>
          <span className="section-label">Date range</span>
          <div className="row" style={{ gap: "var(--sp-sm)" }}>
            <input
              className="field grow"
              type="date"
              value={dateValue(draft.from)}
              onChange={(e) => set({
                from: e.target.value ? startOfDay(new Date(e.target.value).getTime()) : undefined,
              })}
            />
            <input
              className="field grow"
              type="date"
              value={dateValue(draft.to)}
              onChange={(e) => set({
                // Inclusive of the chosen day, otherwise "to: today" hides today.
                to: e.target.value ? endOfDay(new Date(e.target.value).getTime()) : undefined,
              })}
            />
          </div>
        </section>

        <section className="col" style={{ gap: "var(--sp-sm)" }}>
          <span className="section-label">Amount range (₹)</span>
          <div className="row" style={{ gap: "var(--sp-sm)" }}>
            <input
              className="field grow"
              type="number"
              inputMode="decimal"
              placeholder="Min"
              value={rupeeValue(draft.minAmount)}
              onChange={(e) => set({
                minAmount: e.target.value ? Math.round(Number(e.target.value) * 100) : undefined,
              })}
            />
            <input
              className="field grow"
              type="number"
              inputMode="decimal"
              placeholder="Max"
              value={rupeeValue(draft.maxAmount)}
              onChange={(e) => set({
                maxAmount: e.target.value ? Math.round(Number(e.target.value) * 100) : undefined,
              })}
            />
          </div>
        </section>
      </div>
    </Sheet>
  );
}
