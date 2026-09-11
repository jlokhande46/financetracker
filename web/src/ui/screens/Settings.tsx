import { useEffect, useState } from "react";
import { prefs, serverConfig } from "../../sync/config";
import { syncInbox, testConnection } from "../../sync/sync";
import { disablePush, enablePush, pushPrefs, pushSupport, sendTestPush } from "../../sync/push";
import { db } from "../../db/db";
import { seedDefaultAccounts, seedDefaultBills } from "../../db/seed";
import { ImportPDFSheet } from "./ImportPDF";
import { PasteSMSSheet } from "./PasteSMS";
import type { AuditEvent } from "../../db/db";
import type { ScheduleOptions } from "../../domain/reminderSchedule";

export function SettingsScreen({
  hidden, onToggleHidden, onToast, onDataChanged,
}: {
  hidden: boolean;
  onToggleHidden: () => void;
  onToast: (m: string) => void;
  onDataChanged: () => void | Promise<void>;
}) {
  const [url, setUrl] = useState(serverConfig.url);
  const [token, setToken] = useState(serverConfig.token);
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<string | null>(null);
  const [syncing, setSyncing] = useState(false);
  const [audit, setAudit] = useState<AuditEvent[]>([]);
  const [theme, setTheme] = useState(prefs.theme);
  const [importing, setImporting] = useState(false);
  const [pasting, setPasting] = useState(false);
  const [storage, setStorage] = useState<{ rows: number; usedMB: string; persisted: boolean } | null>(null);
  const [pushOn, setPushOn] = useState(pushPrefs.enabled);
  const [pushOptions, setPushOptions] = useState<ScheduleOptions>(pushPrefs.options);
  const [pushBusy, setPushBusy] = useState(false);
  const [pushDetail, setPushDetail] = useState<string | null>(null);
  const support = pushSupport();

  const loadAudit = async () => {
    const rows = await db.audit.orderBy("timestamp").reverse().limit(30).toArray();
    setAudit(rows);
  };
  useEffect(() => { void loadAudit(); }, []);

  // "Where is my data?" deserves an answer in the app, not just in a README.
  useEffect(() => {
    void (async () => {
      const [rows, estimate] = await Promise.all([
        db.transactions.count(),
        navigator.storage?.estimate?.() ?? Promise.resolve(undefined),
      ]);
      // Persistent storage means the browser won't evict the database under
      // pressure. Worth showing, because the unpersisted case is exactly how
      // someone loses a year of tracking without warning.
      const persisted = (await navigator.storage?.persisted?.()) ?? false;
      setStorage({
        rows,
        usedMB: estimate?.usage ? (estimate.usage / 1_048_576).toFixed(1) : "—",
        persisted,
      });
    })();
  }, []);

  async function requestPersistence() {
    const granted = (await navigator.storage?.persist?.()) ?? false;
    setStorage((s) => (s ? { ...s, persisted: granted } : s));
    onToast(granted
      ? "Storage is now protected from automatic cleanup"
      : "The browser declined — installing the app to your Home Screen usually grants it");
  }

  function saveServer() {
    serverConfig.url = url;
    serverConfig.token = token;
    onToast("Server settings saved");
  }

  async function runTest() {
    saveServer();
    setTesting(true);
    setTestResult(null);
    const r = await testConnection();
    setTestResult(`${r.ok ? "✓" : "✗"} ${r.detail}`);
    setTesting(false);
  }

  async function runSync() {
    setSyncing(true);
    const r = await syncInbox();
    setSyncing(false);
    await loadAudit();
    await onDataChanged();
    if (r.error) { onToast(`Sync failed: ${r.error}`); return; }
    onToast(
      r.fetched === 0
        ? "Nothing new in the inbox"
        : `${r.saved} saved · ${r.duplicates} duplicate · ${r.unparseable} unparsed`,
    );
  }

  async function togglePush(next: boolean) {
    setPushBusy(true);
    setPushDetail(null);
    if (!next) {
      await disablePush();
      setPushOn(false);
      setPushDetail("Notifications turned off.");
    } else {
      const result = await enablePush();
      setPushOn(result.ok);
      setPushDetail(result.detail);
    }
    setPushBusy(false);
    // The schedule is rebuilt and re-uploaded next time the app opens.
    await onDataChanged();
  }

  function setOption(key: keyof ScheduleOptions, value: boolean) {
    const next = { ...pushOptions, [key]: value };
    pushPrefs.options = next;
    setPushOptions(next);
    void onDataChanged();
  }

  return (
    <div className="screen col" style={{ gap: "var(--sp-lg)" }}>
      <h1 className="h1" style={{ margin: 0 }}>Settings</h1>

      {/* ── Connection ─────────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Server</span>
        <p className="tiny muted" style={{ margin: 0 }}>
          Your Cloudflare Worker. The Shortcut posts bank SMS here; this app pulls them down.
        </p>
        <input
          className="field"
          placeholder="https://your-worker.workers.dev"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          autoCapitalize="off"
          autoCorrect="off"
        />
        <input
          className="field"
          type="password"
          placeholder="Ingest token"
          value={token}
          onChange={(e) => setToken(e.target.value)}
          autoCapitalize="off"
          autoCorrect="off"
        />
        <div className="row" style={{ gap: "var(--sp-sm)" }}>
          <button className="btn btn-secondary grow" onClick={saveServer}>Save</button>
          <button className="btn grow" onClick={() => void runTest()} disabled={testing}>
            {testing ? "Testing…" : "Test"}
          </button>
        </div>
        {testResult && <p className="tiny" style={{ margin: 0 }}>{testResult}</p>}
      </section>

      {/* ── Sync ───────────────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Sync</span>
        <button className="btn btn-block" onClick={() => void runSync()} disabled={syncing}>
          {syncing ? "Syncing…" : "Pull new SMS now"}
        </button>
        <p className="tiny muted" style={{ margin: 0 }}>
          Runs automatically when you open the app. Pull here to check immediately.
        </p>
      </section>

      {/* ── Notifications ──────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Notifications</span>
        <p className="tiny muted" style={{ margin: 0 }}>
          A web app can't schedule its own reminders on iOS, so they're sent from your Worker.
          The app works out what's due and uploads only the reminder text — your transactions
          stay on this device.
        </p>

        {!support.supported ? (
          <span className="small" style={{ color: "var(--warning-amber)" }}>{support.reason}</span>
        ) : (
          <>
            <label className="spread" style={{ cursor: "pointer" }}>
              <span className="small">Send me reminders</span>
              <input
                type="checkbox"
                checked={pushOn}
                disabled={pushBusy}
                onChange={(e) => void togglePush(e.target.checked)}
                style={{ width: 20, height: 20, accentColor: "var(--brand-primary)" }}
              />
            </label>

            {pushOn && (
              <>
                <div className="divider" />
                <Check
                  label="Bill reminders"
                  hint="Starts after salary lands, gets more frequent as the due date nears, stops once every bill is marked paid"
                  checked={pushOptions.bills}
                  onChange={(v) => setOption("bills", v)}
                />
                <Check
                  label="Statement ready"
                  hint="On each card's bill-generation date, to import the PDF"
                  checked={pushOptions.statements}
                  onChange={(v) => setOption("statements", v)}
                />
                <Check
                  label="Daily money tip"
                  hint="One short note a day, the same one the dashboard shows"
                  checked={pushOptions.tips}
                  onChange={(v) => setOption("tips", v)}
                />
                <button
                  className="btn btn-secondary btn-block"
                  disabled={pushBusy}
                  onClick={async () => {
                    setPushBusy(true);
                    const r = await sendTestPush();
                    setPushDetail(r.detail);
                    setPushBusy(false);
                  }}
                >
                  Send a test notification
                </button>
              </>
            )}
          </>
        )}
        {pushDetail && <p className="tiny muted" style={{ margin: 0 }}>{pushDetail}</p>}
      </section>

      {/* ── Adding transactions ────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Add transactions</span>
        <button className="btn btn-block" onClick={() => setImporting(true)}>
          Import a statement PDF
        </button>
        <p className="tiny muted" style={{ margin: 0 }}>
          Reads the PDF in your browser and shows what it found before saving anything.
          Rows you've already imported are skipped, so re-importing a statement is safe.
        </p>
        <button className="btn btn-secondary btn-block" onClick={() => setPasting(true)}>
          Paste a bank SMS
        </button>
        <p className="tiny muted" style={{ margin: 0 }}>
          For messages the automation missed — or to use SMS capture before the Worker is
          set up at all. Paste several at once with a blank line between them.
        </p>
      </section>

      {/* ── Where the data lives ───────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Your data</span>
        <p className="tiny muted" style={{ margin: 0 }}>
          Everything is stored in this browser, in IndexedDB — a database on your device.
          It is never uploaded. That also means it is per-browser and per-device: this app
          on your phone and on your laptop are two separate sets of data, and clearing site
          data erases it.
        </p>
        {storage && (
          <>
            <div className="spread">
              <span className="small muted">Transactions stored</span>
              <span className="small amount">{storage.rows}</span>
            </div>
            <div className="spread">
              <span className="small muted">Space used</span>
              <span className="small amount">{storage.usedMB} MB</span>
            </div>
            <div className="spread">
              <span className="small muted">Protected from cleanup</span>
              <span className="small" style={{ color: storage.persisted ? "var(--income-green)" : "var(--warning-amber)" }}>
                {storage.persisted ? "Yes" : "No"}
              </span>
            </div>
            {!storage.persisted && (
              <>
                <button className="btn btn-secondary btn-block" onClick={() => void requestPersistence()}>
                  Protect my data
                </button>
                <p className="tiny muted" style={{ margin: 0 }}>
                  Without this, a browser short on space may delete the database without
                  asking. Adding the app to your Home Screen usually grants it automatically.
                </p>
              </>
            )}
          </>
        )}
      </section>

      {/* ── Shortcut setup ─────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-sm)" }}>
        <span className="section-label">Shortcut setup</span>
        <p className="tiny muted" style={{ margin: 0 }}>
          A web app can't run an App Intent, so the automation posts to your Worker instead.
          It still runs silently with the phone locked.
        </p>
        <ol className="small muted" style={{ margin: 0, paddingLeft: 18, lineHeight: 1.7 }}>
          <li>Shortcuts → Automation → <b>Message Received</b>, from your bank senders</li>
          <li>Action: <b>Get Contents of URL</b></li>
          <li>URL: <code>{url || "https://your-worker.workers.dev"}/api/sms</code></li>
          <li>Method: <b>POST</b></li>
          <li>Headers: <code>Authorization: Bearer {token ? "•".repeat(8) : "<token>"}</code></li>
          <li>Body: <b>JSON</b> → key <code>sms</code> → value <b>Shortcut Input</b></li>
          <li>Turn on <b>Run Immediately</b>, turn off notifications</li>
        </ol>
      </section>

      {/* ── Appearance ─────────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Appearance</span>
        <label className="spread" style={{ cursor: "pointer" }}>
          <span className="col" style={{ gap: 2 }}>
            <span className="small">Hide amounts</span>
            <span className="tiny muted">Masks every figure for a quick shoulder-surf guard</span>
          </span>
          <input
            type="checkbox"
            checked={hidden}
            onChange={onToggleHidden}
            style={{ width: 20, height: 20, accentColor: "var(--brand-primary)" }}
          />
        </label>
        <div className="spread">
          <span className="small">Theme</span>
          <div className="row" style={{ gap: "var(--sp-sm)" }}>
            {(["dark", "light"] as const).map((t) => (
              <button
                key={t}
                className="chip"
                data-selected={theme === t}
                onClick={() => { prefs.theme = t; setTheme(t); }}
              >
                {t === "dark" ? "Dark" : "Light"}
              </button>
            ))}
          </div>
        </div>
      </section>

      {/* ── SMS activity ───────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-sm)" }}>
        <span className="section-label">SMS activity</span>
        <p className="tiny muted" style={{ margin: 0 }}>
          Every step from server pull through parse to save — so a message that never
          became a transaction can be traced rather than guessed at.
        </p>
        {audit.length === 0 ? (
          <span className="small muted">Nothing logged yet.</span>
        ) : (
          <div className="col" style={{ gap: 0 }}>
            {audit.map((e) => (
              <div key={e.id} className="col" style={{ gap: 2, padding: "var(--sp-sm) 0" }}>
                <div className="spread">
                  <span className="small" style={{ color: auditColor(e.kind) }}>{auditLabel(e.kind)}</span>
                  <span className="tiny muted">{new Date(e.timestamp).toLocaleString("en-IN")}</span>
                </div>
                <span className="tiny muted truncate">{e.textPreview}</span>
                {e.detail && <span className="tiny muted">{e.detail}</span>}
              </div>
            ))}
          </div>
        )}
        {audit.length > 0 && (
          <button
            className="btn btn-secondary"
            onClick={async () => { await db.audit.clear(); await loadAudit(); onToast("Activity cleared"); }}
          >
            Clear log
          </button>
        )}
      </section>

      {/* ── Data ───────────────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Data</span>
        <button
          className="btn btn-secondary btn-block"
          onClick={async () => {
            const n = await seedDefaultAccounts();
            await onDataChanged();
            onToast(n > 0 ? `Added ${n} account${n === 1 ? "" : "s"}` : "Accounts already set up");
          }}
        >
          Restore default accounts
        </button>
        <button
          className="btn btn-secondary btn-block"
          onClick={async () => {
            const n = await seedDefaultBills();
            await onDataChanged();
            onToast(n > 0 ? `Added ${n} bill${n === 1 ? "" : "s"}` : "Bills already set up");
          }}
        >
          Restore default bills
        </button>
        <button className="btn btn-secondary btn-block" onClick={() => void exportBackup()}>
          Export backup (JSON)
        </button>
        <label className="btn btn-secondary btn-block" style={{ cursor: "pointer" }}>
          Import backup
          <input
            type="file"
            accept="application/json"
            hidden
            onChange={async (e) => {
              const file = e.target.files?.[0];
              if (!file) return;
              const count = await importBackup(file);
              await onDataChanged();
              onToast(`Imported ${count} transaction${count === 1 ? "" : "s"}`);
            }}
          />
        </label>
        <p className="tiny muted" style={{ margin: 0 }}>
          Export before clearing browser data. Unlike the iOS build, nothing here expires —
          but a backup still protects you from a cleared cache or a lost phone.
        </p>
      </section>

      {pasting && (
        <PasteSMSSheet
          hidden={hidden}
          onClose={() => setPasting(false)}
          onDone={async (message) => {
            await loadAudit();
            await onDataChanged();
            onToast(message);
          }}
        />
      )}

      {importing && (
        <ImportPDFSheet
          hidden={hidden}
          onClose={() => setImporting(false)}
          onDone={async (message) => {
            setImporting(false);
            await loadAudit();
            await onDataChanged();
            onToast(message);
          }}
        />
      )}
    </div>
  );
}

function Check({
  label, hint, checked, onChange,
}: { label: string; hint?: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="spread" style={{ cursor: "pointer" }}>
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

function auditLabel(kind: AuditEvent["kind"]): string {
  switch (kind) {
    case "receivedFromServer": return "Received";
    case "parsed": return "Parsed";
    case "parseFailed": return "Parse failed";
    case "saved": return "Saved";
    case "dedupSkipped": return "Skipped (duplicate)";
  }
}

function auditColor(kind: AuditEvent["kind"]): string {
  switch (kind) {
    case "saved": return "var(--income-green)";
    case "parseFailed": return "var(--expense-red)";
    case "dedupSkipped": return "var(--warning-amber)";
    default: return "var(--brand-primary)";
  }
}

/**
 * Full snapshot — the thing the iOS app's "Export My Data" button only
 * pretended to do. Everything the user typed in by hand is in here: manual
 * transactions, bills and their payment history, budgets, goals, and holdings
 * whose values exist nowhere else.
 */
async function exportBackup(): Promise<void> {
  const [
    transactions, accounts, merchantRules,
    bills, billPayments, budgets, goals, investments, netWorthHistory,
  ] = await Promise.all([
    db.transactions.toArray(),
    db.accounts.toArray(),
    db.merchantRules.toArray(),
    db.bills.toArray(),
    db.billPayments.toArray(),
    db.budgets.toArray(),
    db.goals.toArray(),
    db.investments.toArray(),
    db.netWorthHistory.toArray(),
  ]);
  const payload = {
    version: 2,
    exportedAt: new Date().toISOString(),
    transactions, accounts, merchantRules,
    bills, billPayments, budgets, goals, investments, netWorthHistory,
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `financetracker-${new Date().toISOString().slice(0, 10)}.json`;
  a.click();
  URL.revokeObjectURL(a.href);
}

async function importBackup(file: File): Promise<number> {
  const text = await file.text();
  const data = JSON.parse(text) as Record<string, unknown[] | undefined>;

  // bulkPut is an upsert keyed by id, so re-importing the same backup is
  // idempotent rather than duplicating everything. A v1 backup simply has
  // fewer keys — each restores what it has.
  const restore: Array<[keyof typeof db, string]> = [
    ["accounts", "accounts"],
    ["merchantRules", "merchantRules"],
    ["transactions", "transactions"],
    ["bills", "bills"],
    ["billPayments", "billPayments"],
    ["budgets", "budgets"],
    ["goals", "goals"],
    ["investments", "investments"],
    ["netWorthHistory", "netWorthHistory"],
  ];
  for (const [table, key] of restore) {
    const rows = data[key];
    if (rows?.length) {
      await (db[table] as unknown as { bulkPut(r: unknown[]): Promise<unknown> }).bulkPut(rows);
    }
  }
  return data.transactions?.length ?? 0;
}
