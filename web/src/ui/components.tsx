import { useEffect, type ReactNode } from "react";
import { findCategory } from "../domain/categories";
import { money, signedMoney, timeOfDay } from "./format";
import type { Transaction } from "../domain/types";

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

export function TransactionRow({
  txn, hidden, onClick,
}: { txn: Transaction; hidden: boolean; onClick: () => void }) {
  const cat = findCategory(txn.categorySlug);
  const needsReview = !txn.isConfirmed && txn.confidence < 0.85;
  const time = timeOfDay(txn.date);

  return (
    <button
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: "var(--sp-md)",
        width: "100%", padding: "var(--sp-md) var(--sp-base)", textAlign: "left",
        borderLeft: needsReview ? "3px solid var(--warning-amber)" : "3px solid transparent",
      }}
    >
      <CategoryDot slug={txn.categorySlug} />
      <div className="grow col" style={{ gap: 2 }}>
        <div className="row" style={{ gap: 6 }}>
          <span className="truncate" style={{ fontWeight: 600 }}>
            {txn.merchantName || txn.merchantRaw || "Unknown"}
          </span>
          {needsReview && <Pill text="Review" color="var(--warning-amber)" />}
        </div>
        <div className="row tiny muted" style={{ gap: 6 }}>
          <span style={{ color: cat.colorHex }}>{cat.name}</span>
          {time && <span>· {time}</span>}
          {txn.source === "sms" && <span>· SMS</span>}
        </div>
      </div>
      <span
        className="amount"
        style={{
          fontWeight: 600,
          color: txn.type === "credit" ? "var(--income-green)" : "var(--text-primary)",
        }}
      >
        {signedMoney(txn.amount, txn.type, hidden)}
      </span>
    </button>
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
