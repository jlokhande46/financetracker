import { useState } from "react";
import {
  RECOVERY_AFTER_FAILURES,
  resetAppLock,
  verifyAppLock,
} from "../../auth/appLock";

/**
 * The gate in front of everything, mirroring the Swift LockScreenView.
 *
 * Nothing behind it is rendered — not blurred, not mounted — so the app
 * switcher has no ledger to screenshot.
 *
 * There is no auto-prompt on mount. WebAuthn needs a user gesture on iOS, and a
 * prompt fired without one is either ignored or, worse, remembered as a refusal.
 */
export function LockScreen({ onUnlocked }: { onUnlocked: () => void }) {
  const [busy, setBusy] = useState(false);
  const [detail, setDetail] = useState<string | null>(null);
  const [failures, setFailures] = useState(0);
  const [confirmingReset, setConfirmingReset] = useState(false);

  async function unlock() {
    setBusy(true);
    setDetail(null);
    const result = await verifyAppLock();
    setBusy(false);
    if (result.ok) {
      onUnlocked();
      return;
    }
    setFailures((n) => n + 1);
    setDetail(result.detail);
  }

  return (
    <div
      className="col"
      style={{
        position: "fixed", inset: 0, zIndex: 100,
        background: "var(--bg-primary)",
        alignItems: "center", justifyContent: "center",
        gap: "var(--sp-lg)", padding: "var(--sp-xl)", textAlign: "center",
      }}
      role="dialog"
      aria-modal="true"
      aria-label="App locked"
    >
      <div
        style={{
          width: 72, height: 72, borderRadius: 20,
          background: "var(--brand-primary)", color: "#fff",
          display: "flex", alignItems: "center", justifyContent: "center",
          fontSize: 32,
        }}
        aria-hidden
      >
        ▲
      </div>

      <div className="col" style={{ gap: "var(--sp-xs)" }}>
        <span className="h1" style={{ margin: 0 }}>FinanceTracker</span>
        <span className="small muted">Locked</span>
      </div>

      <button
        className="btn"
        style={{ minWidth: 200 }}
        onClick={() => void unlock()}
        disabled={busy}
        autoFocus
      >
        {busy ? "Waiting…" : "Unlock"}
      </button>

      {detail && (
        <span className="small" style={{ color: "var(--warning-amber)", maxWidth: 300 }}>
          {detail}
        </span>
      )}

      {/* Only after repeated failures, because Safari reports a cancelled prompt
          and a vanished credential identically — offering recovery on the first
          cancel would train the user to tap straight past the lock. */}
      {failures >= RECOVERY_AFTER_FAILURES && !confirmingReset && (
        <button className="tiny muted" onClick={() => setConfirmingReset(true)}>
          Can't unlock?
        </button>
      )}

      {confirmingReset && (
        <div
          className="card col"
          style={{ gap: "var(--sp-sm)", maxWidth: 340, textAlign: "left" }}
        >
          <span className="small" style={{ fontWeight: 600 }}>Turn the lock off?</span>
          <p className="tiny muted" style={{ margin: 0 }}>
            This is here so a cleared passkey or a new phone can't lock you out of your
            own ledger. It removes the lock only — every transaction stays exactly where
            it is. Anyone holding this device could do the same, which is the honest
            limit of a lock with no account behind it.
          </p>
          <div className="row" style={{ gap: "var(--sp-sm)" }}>
            <button
              className="btn btn-secondary grow"
              onClick={() => setConfirmingReset(false)}
            >
              Cancel
            </button>
            <button
              className="btn grow"
              onClick={() => { resetAppLock(); onUnlocked(); }}
            >
              Turn off lock
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
