import { useEffect, useState } from "react";
import { prefs, serverConfig } from "../../sync/config";
import { syncInbox, testConnection } from "../../sync/sync";
import { db } from "../../db/db";
import { seedDefaultAccounts } from "../../db/seed";
import type { AuditEvent } from "../../db/db";

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

  const loadAudit = async () => {
    const rows = await db.audit.orderBy("timestamp").reverse().limit(30).toArray();
    setAudit(rows);
  };
  useEffect(() => { void loadAudit(); }, []);

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
    </div>
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

/** Full snapshot — the thing the iOS app's "Export My Data" button only pretended to do. */
async function exportBackup(): Promise<void> {
  const [transactions, accounts, merchantRules] = await Promise.all([
    db.transactions.toArray(),
    db.accounts.toArray(),
    db.merchantRules.toArray(),
  ]);
  const payload = {
    version: 1,
    exportedAt: new Date().toISOString(),
    transactions, accounts, merchantRules,
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
  const data = JSON.parse(text) as {
    transactions?: unknown[];
    accounts?: unknown[];
    merchantRules?: unknown[];
  };
  // bulkPut is an upsert keyed by id, so re-importing the same backup is
  // idempotent rather than duplicating everything.
  if (data.accounts?.length) await db.accounts.bulkPut(data.accounts as never);
  if (data.merchantRules?.length) await db.merchantRules.bulkPut(data.merchantRules as never);
  if (data.transactions?.length) await db.transactions.bulkPut(data.transactions as never);
  return data.transactions?.length ?? 0;
}
