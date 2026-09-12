import { useCallback, useEffect, useRef, useState } from "react";
import "./theme.css";
import { DashboardScreen } from "./screens/Dashboard";
import { TransactionsScreen, AddTransactionSheet } from "./screens/Transactions";
import { AnalyticsScreen } from "./screens/Analytics";
import { PlanScreen } from "./screens/Plan";
import { SettingsScreen } from "./screens/Settings";
import { LockScreen } from "./screens/LockScreen";
import { Toast } from "./components";
import { lockPrefs, resumePhase, type LockPhase } from "../auth/appLock";
import { prefs, serverConfig } from "../sync/config";
import { syncInbox } from "../sync/sync";
import { syncReminderSchedule } from "../sync/scheduleSync";
import { seedIfEmpty } from "../db/seed";
import { usePendingReview } from "../state/useStore";

type Tab = "home" | "transactions" | "plan" | "analytics" | "settings";

const TABS: Array<{ id: Tab; label: string; glyph: string }> = [
  { id: "home", label: "Home", glyph: "◆" },
  { id: "transactions", label: "Activity", glyph: "≡" },
  { id: "plan", label: "Plan", glyph: "◎" },
  { id: "analytics", label: "Insights", glyph: "▤" },
  { id: "settings", label: "Settings", glyph: "⚙" },
];

export default function App() {
  const [tab, setTab] = useState<Tab>("home");
  const [hidden, setHidden] = useState(prefs.hideAmounts);
  const [toast, setToast] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  // Bumping this remounts the screens so they re-read IndexedDB after a write.
  const [dataVersion, setDataVersion] = useState(0);
  const { pending, reload: reloadPending } = usePendingReview();
  // A cold start is always locked when the lock is on — there's no session to
  // inherit trust from, which is the whole point.
  const [lock, setLock] = useState<LockPhase>(() => (lockPrefs.enabled ? "locked" : "open"));
  const hiddenAt = useRef<number | undefined>(undefined);

  const showToast = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(null), 2600);
  }, []);

  const refreshData = useCallback(async () => {
    await reloadPending();
    setDataVersion((v) => v + 1);
    // Reminders live on the server, so anything that changes what's due has to
    // re-upload the schedule. Failure here is not worth interrupting the user
    // over — the next launch tries again.
    void syncReminderSchedule().catch(() => undefined);
  }, [reloadPending]);

  // Mirrors `lock` for callbacks that must read it without re-subscribing.
  const lockRef = useRef(lock);
  lockRef.current = lock;

  const pull = useCallback(async () => {
    // Nothing syncs while the app is locked. The "N new transactions" toast
    // would otherwise be the one piece of the ledger readable from the lock
    // screen — and it'd fire at the worst possible moment, over someone else's
    // shoulder.
    if (lockRef.current !== "open") return;
    if (!serverConfig.isConfigured) return;
    const r = await syncInbox();
    if (r.saved > 0) {
      await refreshData();
      showToast(`${r.saved} new transaction${r.saved === 1 ? "" : "s"}`);
    }
  }, [refreshData, showToast]);

  const onUnlocked = useCallback(() => {
    hiddenAt.current = undefined;
    lockRef.current = "open";
    setLock("open");
    void pull();
  }, [pull]);

  // Drain the inbox on launch and whenever the app comes back to the
  // foreground. This is the web stand-in for processPendingSMS() firing on
  // scenePhase .active — an installed PWA gets visibilitychange the same way.
  //
  // The same event drives the lock, because it's the only signal a PWA gets
  // that it has been backgrounded.
  useEffect(() => {
    void seedIfEmpty().then(refreshData);
    void pull();

    const onVisibility = () => {
      if (document.visibilityState === "hidden") {
        hiddenAt.current = Date.now();
        // Curtain on the way out, not on the way back: the app switcher takes
        // its screenshot at the moment of hiding.
        setLock((phase) => (lockPrefs.enabled && phase === "open" ? "curtained" : phase));
        return;
      }
      const next = resumePhase({
        enabled: lockPrefs.enabled,
        hiddenAt: hiddenAt.current,
        now: Date.now(),
      });
      hiddenAt.current = undefined;
      // A lock already demanded stays demanded — returning to the app is not
      // an answer to it.
      const resolved = lockRef.current === "locked" ? "locked" : next;
      lockRef.current = resolved;
      setLock(resolved);
      if (resolved === "open") void pull();
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, [refreshData, pull]);

  // Rendered instead of the app, not over it: nothing behind the lock is
  // mounted, so there is no ledger in the DOM to screenshot or scrape.
  if (lock === "locked") return <LockScreen onUnlocked={onUnlocked} />;

  function toggleHidden() {
    const next = !hidden;
    prefs.hideAmounts = next;
    setHidden(next);
  }

  return (
    <>
      <main key={`${tab}-${dataVersion}`}>
        {tab === "home" && (
          <DashboardScreen
            hidden={hidden}
            onGoToTransactions={() => setTab("transactions")}
            onToast={showToast}
          />
        )}
        {tab === "transactions" && (
          <TransactionsScreen hidden={hidden} onToast={showToast} />
        )}
        {tab === "plan" && <PlanScreen hidden={hidden} onToast={showToast} />}
        {tab === "analytics" && <AnalyticsScreen hidden={hidden} onToast={showToast} />}
        {tab === "settings" && (
          <SettingsScreen
            hidden={hidden}
            onToggleHidden={toggleHidden}
            onToast={showToast}
            onDataChanged={refreshData}
          />
        )}
      </main>

      {/* Quick-add, mirroring the iOS FAB. Hidden where it'd be noise: Settings,
          and Plan whose sections carry their own add buttons. */}
      {tab !== "settings" && tab !== "plan" && (
        <button
          onClick={() => setAdding(true)}
          aria-label="Add transaction"
          style={{
            position: "fixed",
            right: "var(--sp-lg)",
            bottom: "calc(var(--tabbar-h) + env(safe-area-inset-bottom) + var(--sp-lg))",
            width: 56, height: 56, borderRadius: "50%",
            background: "var(--brand-primary)", color: "#fff",
            fontSize: 26, lineHeight: 1,
            boxShadow: "0 8px 24px rgba(123,110,246,0.45)",
            zIndex: 40,
          }}
        >
          +
        </button>
      )}

      {adding && (
        <AddTransactionSheet
          onClose={() => setAdding(false)}
          onSaved={async () => {
            setAdding(false);
            await refreshData();
            showToast("Transaction added");
          }}
        />
      )}

      <nav className="tabbar">
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            aria-current={tab === t.id ? "page" : undefined}
          >
            <span style={{ fontSize: 18 }} aria-hidden>{t.glyph}</span>
            <span>{t.label}</span>
            {t.id === "transactions" && pending.length > 0 && (
              <span className="badge">{pending.length}</span>
            )}
          </button>
        ))}
      </nav>

      {/* A short absence blurs rather than re-locks — see resumePhase. Painted
          over the app instead of filtering it, because a CSS filter on an
          ancestor would re-anchor the fixed tab bar and FAB to it. */}
      {lock === "curtained" && <div className="curtain" aria-hidden />}

      {toast && <Toast message={toast} />}
    </>
  );
}
