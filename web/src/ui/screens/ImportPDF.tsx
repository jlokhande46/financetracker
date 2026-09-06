import { useState } from "react";
import { Sheet, CategoryDot } from "../components";
import { fullDate, money } from "../format";
import { parsePDFFile, type PDFParseResult } from "../../parsing/pdfParser";
import { importParsedStatement } from "../../ingest/pdfIngest";
import { useAccounts } from "../../state/useStore";

type Phase =
  | { kind: "idle" }
  | { kind: "parsing"; fileName: string }
  | { kind: "preview"; fileName: string; parsed: PDFParseResult }
  | { kind: "error"; message: string };

/**
 * Statement import, with a preview step before anything is written.
 *
 * The preview is the point. The iOS build imported straight to the ledger, so a
 * misread row (the ICICI reward-points column booked as a ₹14 credit) only
 * surfaced later as a wrong balance. Showing what was read, and what it thinks
 * the direction is, makes a bad parse visible while it's still cheap to cancel.
 */
export function ImportPDFSheet({
  hidden, onClose, onDone,
}: {
  hidden: boolean;
  onClose: () => void;
  onDone: (message: string) => void | Promise<void>;
}) {
  const [phase, setPhase] = useState<Phase>({ kind: "idle" });
  const [accountId, setAccountId] = useState<string | "auto">("auto");
  const [busy, setBusy] = useState(false);
  const { accounts } = useAccounts();

  async function pick(file: File) {
    setPhase({ kind: "parsing", fileName: file.name });
    try {
      const parsed = await parsePDFFile(file);
      setPhase({ kind: "preview", fileName: file.name, parsed });
    } catch (e) {
      setPhase({
        kind: "error",
        message: e instanceof Error ? e.message : "Could not read that PDF.",
      });
    }
  }

  async function confirmImport() {
    if (phase.kind !== "preview") return;
    setBusy(true);
    const result = await importParsedStatement(phase.parsed, {
      accountId: accountId === "auto" ? undefined : accountId,
    });
    setBusy(false);
    await onDone(
      result.saved === 0
        ? result.duplicates > 0
          ? "Already imported — nothing new"
          : "No transactions found in that statement"
        : `Imported ${result.saved}${result.needsReview > 0 ? ` · ${result.needsReview} to review` : ""}`,
    );
  }

  return (
    <Sheet
      title="Import statement"
      onClose={onClose}
      footer={
        phase.kind === "preview" && phase.parsed.rows.length > 0 ? (
          <button className="btn btn-block" disabled={busy} onClick={() => void confirmImport()}>
            {busy ? "Importing…" : `Import ${phase.parsed.rows.length} transaction${phase.parsed.rows.length === 1 ? "" : "s"}`}
          </button>
        ) : undefined
      }
    >
      {phase.kind === "idle" && (
        <>
          <p className="small muted" style={{ margin: "0 0 var(--sp-base)" }}>
            A credit-card or bank statement PDF. It's read in the browser — the file never
            leaves your device.
          </p>
          <label className="btn btn-block" style={{ cursor: "pointer" }}>
            Choose a PDF
            <input
              type="file"
              accept="application/pdf"
              hidden
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) void pick(f);
              }}
            />
          </label>
          <p className="tiny muted" style={{ marginTop: "var(--sp-base)" }}>
            Password-protected statements need the password removed first — most banks send a
            protected file by email and an unprotected one from net banking.
          </p>
        </>
      )}

      {phase.kind === "parsing" && (
        <div className="row" style={{ justifyContent: "center", padding: "var(--sp-xl)", gap: "var(--sp-md)" }}>
          <div className="spinner" />
          <span className="small muted">Reading {phase.fileName}…</span>
        </div>
      )}

      {phase.kind === "error" && (
        <div className="col" style={{ gap: "var(--sp-md)" }}>
          <span className="small" style={{ color: "var(--expense-red)" }}>{phase.message}</span>
          <button className="btn btn-secondary" onClick={() => setPhase({ kind: "idle" })}>
            Try another file
          </button>
        </div>
      )}

      {phase.kind === "preview" && (
        <Preview
          parsed={phase.parsed}
          hidden={hidden}
          accounts={accounts}
          accountId={accountId}
          onAccountChange={setAccountId}
          onReset={() => setPhase({ kind: "idle" })}
        />
      )}
    </Sheet>
  );
}

function Preview({
  parsed, hidden, accounts, accountId, onAccountChange, onReset,
}: {
  parsed: PDFParseResult;
  hidden: boolean;
  accounts: Array<{ id: string; name: string; last4?: string }>;
  accountId: string | "auto";
  onAccountChange: (id: string | "auto") => void;
  onReset: () => void;
}) {
  const [showRaw, setShowRaw] = useState(false);
  const lowConfidence = parsed.rows.filter((r) => r.directionConfidence < 0.85).length;

  if (parsed.columnScrambled) {
    return (
      <div className="col" style={{ gap: "var(--sp-md)" }}>
        <span className="small" style={{ color: "var(--warning-amber)" }}>
          This PDF's table came out column-first.
        </span>
        <p className="tiny muted" style={{ margin: 0 }}>
          The dates and amounts can't be matched back into rows, so nothing was read rather
          than importing transactions that would be confidently wrong. A statement downloaded
          from net banking usually extracts cleanly; an emailed or scanned one often doesn't.
        </p>
        <button className="btn btn-secondary" onClick={onReset}>Try another file</button>
      </div>
    );
  }

  return (
    <div className="col" style={{ gap: "var(--sp-base)" }}>
      <section className="card col" style={{ gap: "var(--sp-xs)" }}>
        <div className="spread">
          <span className="small muted">Bank</span>
          <span className="small">{parsed.detectedBank ?? "Not recognised"}</span>
        </div>
        {parsed.accountLast4 && (
          <div className="spread">
            <span className="small muted">Card / account</span>
            <span className="small">•••• {parsed.accountLast4}</span>
          </div>
        )}
        {parsed.totalDue !== null && (
          <div className="spread">
            <span className="small muted">Total due</span>
            <span className="small amount">{money(parsed.totalDue, hidden)}</span>
          </div>
        )}
        {parsed.dueDate !== null && (
          <div className="spread">
            <span className="small muted">Due date</span>
            <span className="small">{fullDate(parsed.dueDate)}</span>
          </div>
        )}
      </section>

      <div className="col" style={{ gap: "var(--sp-sm)" }}>
        <span className="section-label">Link to account</span>
        <div className="hscroll">
          <button
            className="chip"
            data-selected={accountId === "auto"}
            onClick={() => onAccountChange("auto")}
          >
            Match automatically
          </button>
          {accounts.map((a) => (
            <button
              key={a.id}
              className="chip"
              data-selected={accountId === a.id}
              onClick={() => onAccountChange(a.id)}
            >
              {a.name}
            </button>
          ))}
        </div>
      </div>

      {parsed.rows.length === 0 ? (
        <div className="col" style={{ gap: "var(--sp-md)" }}>
          <span className="small">No transactions were found in this statement.</span>
          <p className="tiny muted" style={{ margin: 0 }}>
            Either the layout isn't one the parser recognises, or every row was a fee or a
            summary line. Open the extracted text below to see what it actually read.
          </p>
          <button className="btn btn-secondary" onClick={onReset}>Try another file</button>
        </div>
      ) : (
        <>
          <div className="spread">
            <span className="section-label">
              {parsed.rows.length} transaction{parsed.rows.length === 1 ? "" : "s"}
            </span>
            {lowConfidence > 0 && (
              <span className="tiny" style={{ color: "var(--warning-amber)" }}>
                {lowConfidence} to review
              </span>
            )}
          </div>

          <div className="card col" style={{ padding: 0, gap: 0, overflow: "hidden" }}>
            {parsed.rows.map((r, i) => (
              <div key={i}>
                <div className="row" style={{ padding: "var(--sp-md)", gap: "var(--sp-md)" }}>
                  <CategoryDot slug="others" size={32} />
                  <span className="col grow" style={{ gap: 2 }}>
                    <span className="small truncate">{r.merchantRaw}</span>
                    <span className="tiny muted">
                      {fullDate(r.date)}
                      {r.directionConfidence < 0.85 && " · direction uncertain"}
                    </span>
                  </span>
                  <span
                    className="small amount"
                    style={{
                      fontWeight: 600,
                      color: r.type === "credit" ? "var(--income-green)" : "var(--text-primary)",
                    }}
                  >
                    {r.type === "credit" ? "+" : "−"}{money(r.amount, hidden)}
                  </span>
                </div>
                {i < parsed.rows.length - 1 && <div className="divider" style={{ marginLeft: 60 }} />}
              </div>
            ))}
          </div>

          <p className="tiny muted" style={{ margin: 0 }}>
            Rows already imported are skipped, so re-importing the same statement is safe.
          </p>
        </>
      )}

      {/* The raw text is what makes a bad parse diagnosable rather than a mystery. */}
      <button className="small muted" style={{ textAlign: "left" }} onClick={() => setShowRaw(!showRaw)}>
        {showRaw ? "Hide" : "Show"} extracted text
      </button>
      {showRaw && (
        <pre
          className="tiny muted"
          style={{
            whiteSpace: "pre-wrap", background: "var(--bg-card)", padding: "var(--sp-md)",
            borderRadius: "var(--r-md)", maxHeight: 240, overflow: "auto", margin: 0,
          }}
        >
          {parsed.rawText.slice(0, 4000)}
        </pre>
      )}
    </div>
  );
}
