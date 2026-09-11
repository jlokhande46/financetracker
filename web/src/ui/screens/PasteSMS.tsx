import { useState } from "react";
import { Sheet, CategoryDot } from "../components";
import { money } from "../format";
import { ingestSMS } from "../../ingest/ingest";
import { parseSMS } from "../../parsing/smsParser";
import { findCategory } from "../../domain/categories";
import type { Transaction } from "../../domain/types";

/**
 * Paste bank SMS in by hand.
 *
 * The Shortcut automation is the real capture path, but it needs a deployed
 * Worker. Without this the app is unusable for SMS until that's set up — and
 * it's also the only way to recover a message the automation missed, or to
 * check why one didn't parse.
 *
 * Handles multiple messages at once: a blank line separates them, which is what
 * you get pasting several SMS out of Messages.
 */
export function PasteSMSSheet({
  hidden, onClose, onDone,
}: {
  hidden: boolean;
  onClose: () => void;
  onDone: (message: string) => void | Promise<void>;
}) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState<Transaction[]>([]);
  const [failed, setFailed] = useState<string[]>([]);

  // Split on blank lines so a multi-line SMS stays intact.
  const messages = text.split(/\n\s*\n/).map((m) => m.trim()).filter(Boolean);
  // Preview before saving, so an unparseable message is obvious up front.
  const preview = messages.map((m) => ({ text: m, parsed: parseSMS(m) }));
  const parseable = preview.filter((p) => p.parsed).length;

  async function save() {
    setBusy(true);
    const ok: Transaction[] = [];
    const bad: string[] = [];
    for (const m of messages) {
      const r = await ingestSMS(m);
      if (r.status === "saved" && r.transaction) ok.push(r.transaction);
      else bad.push(m);
    }
    setSaved(ok);
    setFailed(bad);
    setBusy(false);
    setText("");
    await onDone(
      ok.length === 0
        ? "Nothing could be read from that"
        : `Added ${ok.length} transaction${ok.length === 1 ? "" : "s"}`,
    );
  }

  return (
    <Sheet
      title="Paste bank SMS"
      onClose={onClose}
      footer={
        <button className="btn btn-block" disabled={busy || messages.length === 0} onClick={() => void save()}>
          {busy ? "Reading…"
            : messages.length === 0 ? "Paste a message"
            : `Add ${parseable} of ${messages.length}`}
        </button>
      }
    >
      <p className="small muted" style={{ margin: "0 0 var(--sp-base)" }}>
        Copy a bank alert from Messages and paste it here. Several at once is fine —
        leave a blank line between them.
      </p>

      <textarea
        className="field"
        rows={6}
        placeholder={"Rs.450.00 spent on your SBI Credit Card ending 1234 at SWIGGY on 12/05/26"}
        value={text}
        onChange={(e) => setText(e.target.value)}
        style={{ fontFamily: "ui-monospace, monospace", fontSize: 12, resize: "vertical" }}
      />

      {preview.length > 0 && (
        <div className="col" style={{ gap: "var(--sp-sm)", marginTop: "var(--sp-base)" }}>
          <span className="section-label">What this reads as</span>
          {preview.map((p, i) => (
            <div key={i} className="card row" style={{ gap: "var(--sp-md)", padding: "var(--sp-md)" }}>
              {p.parsed ? (
                <>
                  <CategoryDot slug="others" size={32} />
                  <span className="col grow" style={{ gap: 2, minWidth: 0 }}>
                    <span className="small truncate">{p.parsed.merchantRaw || "Unknown merchant"}</span>
                    <span className="tiny muted">matched by {p.parsed.matchedBy}</span>
                  </span>
                  <span
                    className="small amount"
                    style={{
                      fontWeight: 600,
                      color: p.parsed.type === "credit" ? "var(--income-green)" : "var(--text-primary)",
                    }}
                  >
                    {p.parsed.type === "credit" ? "+" : "−"}{money(p.parsed.amount, hidden)}
                  </span>
                </>
              ) : (
                <span className="col grow" style={{ gap: 2, minWidth: 0 }}>
                  <span className="small" style={{ color: "var(--warning-amber)" }}>
                    No bank format matched
                  </span>
                  <span className="tiny muted truncate">{p.text}</span>
                </span>
              )}
            </div>
          ))}
        </div>
      )}

      {saved.length > 0 && (
        <div className="col" style={{ gap: "var(--sp-sm)", marginTop: "var(--sp-base)" }}>
          <span className="section-label">Added</span>
          {saved.map((t) => (
            <div key={t.id} className="row card" style={{ gap: "var(--sp-md)", padding: "var(--sp-md)" }}>
              <CategoryDot slug={t.categorySlug} size={32} />
              <span className="col grow" style={{ gap: 2, minWidth: 0 }}>
                <span className="small truncate">{t.merchantName}</span>
                <span className="tiny muted">{findCategory(t.categorySlug).name}</span>
              </span>
              <span className="small amount" style={{ fontWeight: 600 }}>
                {money(t.amount, hidden)}
              </span>
            </div>
          ))}
        </div>
      )}

      {failed.length > 0 && (
        <p className="tiny muted" style={{ marginTop: "var(--sp-base)" }}>
          {failed.length} message{failed.length === 1 ? "" : "s"} couldn't be read, or were
          duplicates of something already saved. Settings → SMS activity shows exactly which
          and why.
        </p>
      )}
    </Sheet>
  );
}
