import { useEffect, useRef, useState, type ReactNode } from "react";
import { findCategory } from "../domain/categories";
import { money, signedMoney, timeOfDay } from "./format";
import { INTENT_META, needsReview, type CategoryIntent, type Transaction } from "../domain/types";
import { intentOf, isOverridden, nextIntent, supportsIntent } from "../domain/intent";

/** Coloured category dot with the category's initial — cheap stand-in for icons. */
export function CategoryDot({ slug, size = 40 }: { slug: string; size?: number }) {
  const cat = findCategory(slug);
  return (
    <div
      style={{
        width: size, height: size, borderRadius: "50%",
        background: `${cat.colorHex}2E`,
        color: cat.colorHex,
        display: "flex", alignItems: "center", justifyContent: "center",
        fontSize: size * 0.4, fontWeight: 700, flexShrink: 0,
      }}
      aria-hidden
    >
      {cat.name.charAt(0)}
    </div>
  );
}

export function Pill({ text, color }: { text: string; color: string }) {
  return (
    <span className="pill" style={{ background: `${color}26`, color }}>
      {text}
    </span>
  );
}

/**
 * One row in the feed.
 *
 * Three things are layered onto it, all ported from `TransactionRowView.swift`:
 * a horizontal drag that assigns the 50/30/20 intent, a chip that cycles the
 * same thing by tap, and tag chips that drive the feed's filter.
 *
 * The drag is hand-rolled on pointer events rather than borrowing a library:
 * it has to coexist with vertical scrolling (`touch-action: pan-y` hands the
 * vertical axis back to the browser) and it has to be cancellable, which a
 * generic swipe-to-delete component is not.
 */
export function TransactionRow({
  txn, hidden, onClick, onSetIntent, selectedTags = [], onToggleTag,
}: {
  txn: Transaction;
  hidden: boolean;
  onClick: () => void;
  onSetIntent?: (intent: CategoryIntent | undefined) => void;
  selectedTags?: string[];
  onToggleTag?: (tag: string) => void;
}) {
  const cat = findCategory(txn.categorySlug);
  const review = needsReview(txn);
  const time = timeOfDay(txn.date);
  const canSetIntent = supportsIntent(txn) && onSetIntent !== undefined;
  const intent = intentOf(txn);
  const overridden = isOverridden(txn);

  const [dx, setDx] = useState(0);
  const drag = useRef<{ x: number; y: number; active: boolean; buzzed: boolean } | null>(null);
  // The click that follows a drag arrives AFTER pointerup, by which point the
  // gesture state is already gone — so the decision to swallow it has to be
  // recorded separately or every swipe also opens the detail sheet.
  const swallowClick = useRef(false);

  const COMMIT = 80;   // past here, releasing assigns the intent
  const RESIST = 140;  // past here the row slows down so it never flies off-screen

  function onPointerDown(e: React.PointerEvent) {
    if (!canSetIntent) return;
    drag.current = { x: e.clientX, y: e.clientY, active: false, buzzed: false };
  }

  function onPointerMove(e: React.PointerEvent) {
    const d = drag.current;
    if (!d) return;
    const deltaX = e.clientX - d.x;
    const deltaY = e.clientY - d.y;

    // Decide once whether this gesture is a horizontal drag or the start of a
    // vertical scroll. Getting this wrong makes the feed feel stuck.
    if (!d.active) {
      if (Math.abs(deltaX) < 10 || Math.abs(deltaX) <= Math.abs(deltaY)) return;
      d.active = true;
      swallowClick.current = true;
      e.currentTarget.setPointerCapture(e.pointerId);
    }

    const magnitude = Math.abs(deltaX);
    const eased = magnitude > RESIST ? RESIST + (magnitude - RESIST) * 0.3 : magnitude;
    const next = Math.sign(deltaX) * eased;

    // A tick at the commit point, so the threshold is felt rather than guessed.
    if (!d.buzzed && magnitude >= COMMIT) {
      d.buzzed = true;
      navigator.vibrate?.(8);
    } else if (d.buzzed && magnitude < COMMIT) {
      d.buzzed = false;
    }
    setDx(next);
  }

  function onPointerUp() {
    const d = drag.current;
    drag.current = null;
    if (!d?.active) { setDx(0); return; }
    if (dx >= COMMIT) onSetIntent?.("need");
    else if (dx <= -COMMIT) onSetIntent?.("want");
    setDx(0);
  }

  const committing = Math.abs(dx) >= COMMIT;
  const revealed = dx > 0 ? INTENT_META.need : INTENT_META.want;

  return (
    <div style={{ position: "relative", overflow: "hidden" }}>
      {/* What the drag uncovers: Need from the left, Want from the right. */}
      {dx !== 0 && (
        <div
          className="row"
          style={{
            position: "absolute", inset: 0,
            justifyContent: dx > 0 ? "flex-start" : "flex-end",
            padding: "0 var(--sp-lg)",
            background: `${revealed.color}${committing ? "33" : "1A"}`,
            color: revealed.color, fontWeight: 700, fontSize: 13,
          }}
          aria-hidden
        >
          {revealed.label.replace(/s$/, "")}
        </div>
      )}

      <div
        role="button"
        tabIndex={0}
        onClick={() => {
          if (swallowClick.current) { swallowClick.current = false; return; }
          onClick();
        }}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onClick(); } }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        style={{
          display: "flex", alignItems: "center", gap: "var(--sp-md)",
          width: "100%", padding: "var(--sp-md) var(--sp-base)", textAlign: "left",
          borderLeft: review ? "3px solid var(--warning-amber)" : "3px solid transparent",
          background: "var(--bg-card)",
          transform: `translateX(${dx}px)`,
          transition: dx === 0 ? "transform 0.18s ease" : "none",
          touchAction: canSetIntent ? "pan-y" : undefined,
          cursor: "pointer",
        }}
      >
        <CategoryDot slug={txn.categorySlug} />
        <div className="grow col" style={{ gap: 2, minWidth: 0 }}>
          <div className="row" style={{ gap: 6 }}>
            <span className="truncate" style={{ fontWeight: 600 }}>
              {txn.merchantName || txn.merchantRaw || "Unknown"}
            </span>
            {review && <Pill text="Review" color="var(--warning-amber)" />}
          </div>
          <div className="row tiny muted" style={{ gap: 6, flexWrap: "wrap" }}>
            <span style={{ color: cat.colorHex }}>{cat.name}</span>
            {time && <span>· {time}</span>}
            {txn.source === "sms" && <span>· SMS</span>}
            {canSetIntent && (
              <button
                onClick={(e) => { e.stopPropagation(); onSetIntent?.(nextIntent(txn.intentOverride)); }}
                title="Cycle need / want / saving"
                style={{
                  fontSize: 10, fontWeight: 700, letterSpacing: 0.3,
                  padding: "1px 6px", borderRadius: "var(--r-full)",
                  border: `1px solid ${intent ? INTENT_META[intent].color : "var(--divider)"}`,
                  color: intent ? INTENT_META[intent].color : "var(--text-tertiary)",
                  background: overridden && intent ? `${INTENT_META[intent].color}1F` : "transparent",
                }}
              >
                {intent ? INTENT_META[intent].label.replace(/s$/, "") : "Set"}
                {overridden ? " •" : ""}
              </button>
            )}
          </div>
          {txn.tags.length > 0 && (
            <div className="row" style={{ gap: 4, flexWrap: "wrap", marginTop: 2 }}>
              {txn.tags.map((tag) => (
                <button
                  key={tag}
                  onClick={(e) => { e.stopPropagation(); onToggleTag?.(tag); }}
                  style={{
                    fontSize: 10, padding: "1px 6px", borderRadius: "var(--r-full)",
                    background: selectedTags.includes(tag)
                      ? "var(--brand-primary)" : "var(--bg-elevated)",
                    color: selectedTags.includes(tag) ? "#fff" : "var(--text-secondary)",
                  }}
                >
                  #{tag}
                </button>
              ))}
            </div>
          )}
        </div>
        <span
          className="amount"
          style={{
            fontWeight: 600, flexShrink: 0,
            color: txn.type === "credit" ? "var(--income-green)" : "var(--text-primary)",
          }}
        >
          {signedMoney(txn.amount, txn.type, hidden)}
        </span>
      </div>
    </div>
  );
}

export function DayHeader({
  label, debitTotal, creditTotal, hidden,
}: { label: string; debitTotal: number; creditTotal: number; hidden: boolean }) {
  return (
    <div
      className="spread"
      style={{
        position: "sticky", top: 0, zIndex: 2,
        background: "var(--bg-primary)",
        padding: "var(--sp-sm) var(--sp-base)",
      }}
    >
      <span className="small muted">{label}</span>
      <span className="row tiny amount" style={{ gap: 8 }}>
        {creditTotal > 0 && (
          <span style={{ color: "var(--income-green)" }}>+{money(creditTotal, hidden)}</span>
        )}
        {debitTotal > 0 && <span className="muted">−{money(debitTotal, hidden)}</span>}
      </span>
    </div>
  );
}

export function Sheet({
  title, onClose, children, footer,
}: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode }) {
  // Escape to dismiss, and lock the page behind the sheet so it doesn't scroll.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose]);

  return (
    <div className="sheet-backdrop" onClick={onClose} role="presentation">
      <div
        className="sheet"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className="spread" style={{ marginBottom: "var(--sp-base)" }}>
          <span className="h2">{title}</span>
          <button onClick={onClose} className="muted" aria-label="Close">Done</button>
        </div>
        {children}
        {footer && <div style={{ marginTop: "var(--sp-lg)" }}>{footer}</div>}
      </div>
    </div>
  );
}

export function EmptyState({
  title, subtitle, action,
}: { title: string; subtitle: string; action?: ReactNode }) {
  return (
    <div
      className="col"
      style={{ alignItems: "center", gap: "var(--sp-md)", padding: "var(--sp-xxl) var(--sp-base)", textAlign: "center" }}
    >
      <span className="h2">{title}</span>
      <span className="small muted" style={{ maxWidth: 320 }}>{subtitle}</span>
      {action}
    </div>
  );
}

/** Horizontal proportion bar — used for category breakdown and the 50/30/20 card. */
export function Bar({ fraction, color }: { fraction: number; color: string }) {
  return (
    <div style={{ height: 6, borderRadius: 3, background: "var(--chart-grid)", overflow: "hidden" }}>
      <div
        style={{
          width: `${Math.max(0, Math.min(1, fraction)) * 100}%`,
          height: "100%",
          background: color,
          borderRadius: 3,
          transition: "width 0.4s ease",
        }}
      />
    </div>
  );
}

export function Toast({ message }: { message: string }) {
  return <div className="toast">{message}</div>;
}
