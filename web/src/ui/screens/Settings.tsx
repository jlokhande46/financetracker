import { useEffect, useState } from "react";
import { prefs, serverConfig } from "../../sync/config";
import {
  disableAppLock, enableAppLock, lockPrefs, lockSupport, type LockSupport,
} from "../../auth/appLock";
import { syncInbox, testConnection } from "../../sync/sync";
import { disablePush, enablePush, pushPrefs, pushSupport, sendTestPush } from "../../sync/push";
import { db } from "../../db/db";
import {
  deleteAllMerchantRules, deleteMerchantRule, relinkOrphanTransactions,
  saveMerchantRule, useMerchantRules,
} from "../../state/useStore";
import { dismissedInsights } from "../../state/dismissedInsights";
import { CATEGORIES, findCategory } from "../../domain/categories";
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
  const [lockOn, setLockOn] = useState(lockPrefs.enabled);
  const [lockBusy, setLockBusy] = useState(false);
  const [lockDetail, setLockDetail] = useState<string | null>(null);
  // Platform-authenticator availability is a promise, unlike push support.
  const [lockAvailable, setLockAvailable] = useState<LockSupport | null>(null);
  const support = pushSupport();

  useEffect(() => { void lockSupport().then(setLockAvailable); }, []);

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

  /**
   * The toggle only moves once the authenticator has actually answered — in
   * both directions. Enabling without verifying is how someone ends up behind
   * a lock they can't satisfy; disabling without verifying means whoever is
   * holding the phone can just switch it off.
   */
  async function toggleLock(next: boolean) {
    setLockBusy(true);
    setLockDetail(null);
    const result = next ? await enableAppLock() : await disableAppLock();
    setLockOn(lockPrefs.enabled);
    setLockDetail(result.detail);
    setLockBusy(false);
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

      {/* ── Privacy ────────────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Privacy</span>
        <p className="tiny muted" style={{ margin: 0 }}>
          Face ID, Touch ID or your device passcode, asked for when you open the app and
          again after it's been in the background a while. It guards the screen, not the
          database — anything that can open devtools on an unlocked device can still read
          it. The iOS app's Face ID lock worked the same way; it's just more obvious here.
        </p>

        {lockAvailable && !lockAvailable.supported ? (
          <span className="small" style={{ color: "var(--warning-amber)" }}>
            {lockAvailable.reason}
          </span>
        ) : (
          <label className="spread" style={{ cursor: lockBusy ? "progress" : "pointer" }}>
            <span className="col" style={{ gap: 2 }}>
              <span className="small">App lock</span>
              <span className="tiny muted">
                {lockBusy ? "Waiting for the authenticator…" : "Unlock with Face ID or your passcode"}
              </span>
            </span>
            <input
              type="checkbox"
              checked={lockOn}
              disabled={lockBusy || lockAvailable === null}
              onChange={(e) => void toggleLock(e.target.checked)}
              style={{ width: 20, height: 20, accentColor: "var(--brand-primary)" }}
            />
          </label>
        )}
        {lockDetail && <p className="tiny" style={{ margin: 0 }}>{lockDetail}</p>}
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

      {/* ── Learned rules ──────────────────────────────────────────── */}
      <MerchantRulesSection onToast={onToast} onDataChanged={onDataChanged} />

      {/* ── Utilities ──────────────────────────────────────────────── */}
      <section className="card col" style={{ gap: "var(--sp-md)" }}>
        <span className="section-label">Utilities</span>
        <button
          className="btn btn-secondary btn-block"
          onClick={async () => {
            const n = await relinkOrphanTransactions();
            await onDataChanged();
            onToast(n > 0
              ? `Linked ${n} transaction${n === 1 ? "" : "s"} to an account`
              : "Nothing left to re-link");
          }}
        >
          Re-link orphan transactions
        </button>
        <p className="tiny muted" style={{ margin: 0 }}>
          Finds rows saved before their card existed and points them at the right account,
          using only a card number that actually matches one of yours.
        </p>
        <button
          className="btn btn-secondary btn-block"
          disabled={dismissedInsights.count === 0}
          onClick={() => {
            const n = dismissedInsights.count;
            dismissedInsights.restoreAll();
            void onDataChanged();
            onToast(`Restored ${n} hidden insight${n === 1 ? "" : "s"}`);
          }}
        >
          Restore dismissed insights{dismissedInsights.count > 0 ? ` (${dismissedInsights.count})` : ""}
        </button>
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

/**
 * Everything the app has learned from "Remember this name / category".
 *
 * Worth surfacing because a single wrong rule keeps re-applying itself
 * invisibly — the merchant just quietly lands in the wrong category forever,
 * and until there's a list you can see, there's no way to work out why.
 */
function MerchantRulesSection({
  onToast, onDataChanged,
}: { onToast: (m: string) => void; onDataChanged: () => void | Promise<void> }) {
  const { rules, reload } = useMerchantRules();
  const [search, setSearch] = useState("");
  const [editing, setEditing] = useState<string | null>(null);
  const [confirmWipe, setConfirmWipe] = useState(false);

  const shown = rules.filter((r) => {
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return r.key.includes(q) || r.displayName.toLowerCase().includes(q) ||
      findCategory(r.categorySlug).name.toLowerCase().includes(q);
  });

  return (
    <section className="card col" style={{ gap: "var(--sp-md)" }}>
      <span className="section-label">Learned rules</span>
      <p className="tiny muted" style={{ margin: 0 }}>
        Saved when you tick "Remember" during review. Each one re-applies to every future
        import of that merchant, so a wrong one is worth fixing here.
      </p>

      {rules.length === 0 ? (
        <span className="tiny muted">
          Nothing learned yet. Confirm a transaction in Review with "Remember" on.
        </span>
      ) : (
        <>
          <input
            className="field"
            placeholder={`Search ${rules.length} rule${rules.length === 1 ? "" : "s"}`}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />

          <div className="col" style={{ gap: "var(--sp-sm)" }}>
            {shown.slice(0, 40).map((rule) => (
              <div key={rule.key} className="col" style={{ gap: "var(--sp-sm)" }}>
                <div className="spread">
                  <span className="col grow" style={{ gap: 2, minWidth: 0 }}>
                    <span className="small truncate">{rule.displayName || rule.key}</span>
                    <span className="tiny muted truncate">
                      {findCategory(rule.categorySlug).name} · matched {rule.matchCount}×
                    </span>
                  </span>
                  <div className="row" style={{ gap: "var(--sp-sm)", flexShrink: 0 }}>
                    <button
                      className="tiny"
                      style={{ color: "var(--brand-primary)" }}
                      onClick={() => setEditing(editing === rule.key ? null : rule.key)}
                    >
                      {editing === rule.key ? "Done" : "Edit"}
                    </button>
                    <button
                      className="tiny"
                      style={{ color: "var(--expense-red)" }}
                      onClick={async () => {
                        await deleteMerchantRule(rule.key);
                        await reload();
                        onToast("Rule deleted");
                      }}
                    >
                      Delete
                    </button>
                  </div>
                </div>

                {editing === rule.key && (
                  <div className="col" style={{ gap: "var(--sp-sm)" }}>
                    <input
                      className="field"
                      value={rule.displayName}
                      placeholder="Display name"
                      onChange={async (e) => {
                        await saveMerchantRule({ ...rule, displayName: e.target.value });
                        await reload();
                      }}
                    />
                    <div className="row" style={{ gap: "var(--sp-sm)", flexWrap: "wrap" }}>
                      {CATEGORIES.filter((c) => !c.isIncome).map((c) => (
                        <button
                          key={c.slug}
                          className="chip"
                          data-selected={rule.categorySlug === c.slug}
                          style={rule.categorySlug === c.slug
                            ? { background: c.colorHex, color: "#fff" }
                            : undefined}
                          onClick={async () => {
                            await saveMerchantRule({ ...rule, categorySlug: c.slug });
                            await reload();
                            await onDataChanged();
                          }}
                        >
                          {c.name}
                        </button>
                      ))}
                    </div>
                  </div>
                )}
                <div className="divider" />
              </div>
            ))}
            {shown.length > 40 && (
              <span className="tiny muted">
                Showing 40 of {shown.length}. Search to narrow it down.
              </span>
            )}
            {shown.length === 0 && <span className="tiny muted">No rule matches that search.</span>}
          </div>

          {confirmWipe ? (
            <div className="row" style={{ gap: "var(--sp-sm)" }}>
              <button className="btn btn-secondary grow" onClick={() => setConfirmWipe(false)}>
                Cancel
              </button>
              <button
                className="btn grow"
                style={{ background: "var(--expense-red)" }}
                onClick={async () => {
                  const n = await deleteAllMerchantRules();
                  setConfirmWipe(false);
                  await reload();
                  onToast(`Deleted ${n} rule${n === 1 ? "" : "s"}`);
                }}
              >
                Delete all rules
              </button>
            </div>
          ) : (
            <button
              className="btn btn-secondary btn-block"
              style={{ color: "var(--expense-red)" }}
              onClick={() => setConfirmWipe(true)}
            >
              Delete all rules
            </button>
          )}
        </>
      )}
    </section>
  );
}
