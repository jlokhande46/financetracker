import { serverConfig } from "./config";
import { ingestSMS, recalculateBalances } from "../ingest/ingest";
import { recordAudit } from "../db/db";

export interface SyncResult {
  fetched: number;
  saved: number;
  duplicates: number;
  unparseable: number;
  error?: string;
}

interface InboxItem {
  id: number;
  text: string;
  received_at: number;
}

/**
 * Pull anything the Shortcut captured since our cursor and run each message
 * through the ingest pipeline.
 *
 * This is the web replacement for `AppContainer.processPendingSMS()`. The
 * Swift version drained an App Group queue that the App Intent had written to
 * on-device; here the Shortcut POSTs to the Worker and we drain over HTTP.
 *
 * Parsing deliberately stays client-side: the bank formats live in one place,
 * and a parser change ships with the app rather than needing a redeploy.
 */
export async function syncInbox(): Promise<SyncResult> {
  const empty: SyncResult = { fetched: 0, saved: 0, duplicates: 0, unparseable: 0 };
  if (!serverConfig.isConfigured) {
    return { ...empty, error: "Server not configured" };
  }

  let items: InboxItem[];
  try {
    const res = await fetch(
      `${serverConfig.url}/api/inbox?since=${serverConfig.cursor}`,
      { headers: { authorization: `Bearer ${serverConfig.token}` } },
    );
    if (!res.ok) {
      const detail = res.status === 401 ? "Bad ingest token" : `HTTP ${res.status}`;
      return { ...empty, error: detail };
    }
    const body = (await res.json()) as { items?: InboxItem[] };
    items = body.items ?? [];
  } catch (e) {
    // Offline is normal for a PWA — surface it without treating it as a fault.
    return { ...empty, error: e instanceof Error ? e.message : "Network error" };
  }

  const result: SyncResult = { ...empty, fetched: items.length };
  let highWater = serverConfig.cursor;

  for (const item of items) {
    await recordAudit("receivedFromServer", item.text, `inbox #${item.id}`);
    const outcome = await ingestSMS(item.text, item.received_at);
    if (outcome.status === "saved") result.saved++;
    else if (outcome.status === "duplicate") result.duplicates++;
    else result.unparseable++;
    highWater = Math.max(highWater, item.received_at);
  }

  // Only advance the cursor after the batch is fully written, so a mid-batch
  // failure re-fetches rather than silently skipping messages. The ingest
  // pipeline's own rawContent dedup makes the replay safe.
  serverConfig.cursor = highWater;

  if (result.saved > 0) await recalculateBalances();
  return result;
}

/** One-off connectivity check for the Settings screen. */
export async function testConnection(): Promise<{ ok: boolean; detail: string }> {
  if (!serverConfig.isConfigured) return { ok: false, detail: "Enter a server URL and token first." };
  try {
    const res = await fetch(`${serverConfig.url}/api/health`);
    if (!res.ok) return { ok: false, detail: `Server responded ${res.status}` };
    // Health is unauthenticated; prove the token works by hitting a guarded route.
    const auth = await fetch(`${serverConfig.url}/api/inbox?since=${Date.now()}`, {
      headers: { authorization: `Bearer ${serverConfig.token}` },
    });
    if (auth.status === 401) return { ok: false, detail: "Reached the server, but the token was rejected." };
    if (!auth.ok) return { ok: false, detail: `Inbox check failed (${auth.status}).` };
    return { ok: true, detail: "Connected. Server and token both check out." };
  } catch (e) {
    return { ok: false, detail: e instanceof Error ? e.message : "Could not reach the server." };
  }
}
