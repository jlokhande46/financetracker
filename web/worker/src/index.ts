/**
 * FinanceTracker backend — Cloudflare Worker + D1.
 *
 * This exists for one reason: a PWA cannot expose an App Intent to iOS
 * Shortcuts, so the Swift app's silent locked-phone SMS capture has no direct
 * web equivalent. The replacement is a Shortcuts automation using "Get Contents
 * of URL" to POST the message here. That runs in the background while the phone
 * is locked, exactly like the App Intent did — and it no longer depends on an
 * App Group entitlement that free-team signing strips.
 *
 * Endpoints:
 *   POST /api/sms              Shortcut drops a raw bank SMS here.
 *   GET  /api/inbox            PWA drains anything captured since a cursor.
 *   GET  /api/push/vapid       Public key the browser needs to subscribe.
 *   POST /api/push/subscribe   Register a Web Push subscription.
 *   POST /api/reminders        Replace the pending reminder schedule.
 *   GET  /api/reminders        Read it back (for the Settings diagnostics).
 *
 * Web Push matters because iOS PWAs cannot schedule local notifications — there
 * is no Notification Triggers API on Safari. Bill reminders and the daily tip
 * are therefore pushed from the scheduled() cron handler below.
 *
 * Note what the server does NOT hold: the ledger stays in the browser's
 * IndexedDB. The PWA works out which reminders it wants and uploads only their
 * text and send times, so the cron can fire them without the server ever seeing
 * a transaction.
 */

import { sendPush, type PushSubscription, type VapidKeys } from "./webpush";

export interface Env {
  DB: D1Database;
  /** Shared secret the Shortcut sends; keeps the endpoint from being open. */
  INGEST_TOKEN: string;
  /** VAPID key pair, set with `wrangler secret put`. Push is off without them. */
  VAPID_PUBLIC_KEY?: string;
  VAPID_PRIVATE_KEY?: string;
  VAPID_SUBJECT?: string;
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", ...CORS },
  });

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": "content-type,authorization",
};

function authorized(request: Request, env: Env): boolean {
  const header = request.headers.get("authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  // Constant-ish comparison; these are short shared secrets, not passwords.
  return token.length > 0 && token === env.INGEST_TOKEN;
}

function vapidKeys(env: Env): VapidKeys | null {
  if (!env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY) return null;
  return {
    publicKey: env.VAPID_PUBLIC_KEY,
    privateKey: env.VAPID_PRIVATE_KEY,
    subject: env.VAPID_SUBJECT ?? "mailto:noreply@example.com",
  };
}

/** One queued notification. `tag` collapses repeats of the same bill on the lock screen. */
interface ReminderRow {
  id: string;
  send_at: number;
  title: string;
  body: string;
  tag: string;
  url: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    // ── Shortcut drops a raw SMS here ───────────────────────────────────────
    if (url.pathname === "/api/sms" && request.method === "POST") {
      if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);

      // Accept both JSON and text/plain — Shortcuts is fiddly about content
      // types, and a capture that silently 400s is worse than a lenient parse.
      let text = "";
      const contentType = request.headers.get("content-type") ?? "";
      if (contentType.includes("application/json")) {
        const body = (await request.json().catch(() => ({}))) as { sms?: string; text?: string };
        text = (body.sms ?? body.text ?? "").trim();
      } else {
        text = (await request.text()).trim();
      }
      if (!text) return json({ error: "empty sms" }, 400);

      const receivedAt = Date.now();
      await env.DB.prepare(
        "INSERT INTO sms_inbox (text, received_at, consumed) VALUES (?, ?, 0)",
      ).bind(text, receivedAt).run();

      // Shortcuts shows this; handy for confirming the automation fired.
      return json({ ok: true, receivedAt });
    }

    // ── PWA drains the inbox ────────────────────────────────────────────────
    if (url.pathname === "/api/inbox" && request.method === "GET") {
      if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);
      const since = Number(url.searchParams.get("since") ?? 0);
      const { results } = await env.DB.prepare(
        "SELECT id, text, received_at FROM sms_inbox WHERE received_at > ? ORDER BY received_at ASC LIMIT 200",
      ).bind(since).all();
      return json({ items: results ?? [] });
    }

    // ── Web Push ────────────────────────────────────────────────────────────
    if (url.pathname === "/api/push/vapid" && request.method === "GET") {
      // Deliberately unauthenticated: the public key is public by definition,
      // and the browser needs it before it can subscribe.
      return json({ publicKey: env.VAPID_PUBLIC_KEY ?? null });
    }

    if (url.pathname === "/api/push/subscribe" && request.method === "POST") {
      if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);
      const sub = await request.json().catch(() => null) as PushSubscription | null;
      if (!sub?.endpoint) return json({ error: "bad subscription" }, 400);
      await env.DB.prepare(
        "INSERT OR REPLACE INTO push_subscriptions (endpoint, payload, created_at) VALUES (?, ?, ?)",
      ).bind(sub.endpoint, JSON.stringify(sub), Date.now()).run();
      return json({ ok: true });
    }

    /** A test push, so "did I set this up right?" is answerable in one tap. */
    if (url.pathname === "/api/push/test" && request.method === "POST") {
      if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);
      const keys = vapidKeys(env);
      if (!keys) return json({ error: "push not configured" }, 503);
      const sent = await deliver(env, keys, {
        title: "FinanceTracker",
        body: "Notifications are working.",
        tag: "test",
        url: "/",
      });
      return json({ ok: true, sent });
    }

    // ── Reminder schedule ───────────────────────────────────────────────────
    if (url.pathname === "/api/reminders" && request.method === "POST") {
      if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);
      const body = await request.json().catch(() => null) as { reminders?: ReminderRow[] } | null;
      const reminders = body?.reminders ?? [];

      // The client is the source of truth: it recomputes the whole schedule from
      // its own data, so replacing wholesale is what keeps a cancelled reminder
      // from outliving the bill that produced it.
      const statements = [
        env.DB.prepare("DELETE FROM reminders WHERE sent = 0"),
        ...reminders.slice(0, 200).map((r) =>
          env.DB.prepare(
            "INSERT OR REPLACE INTO reminders (id, send_at, title, body, tag, url, sent) VALUES (?, ?, ?, ?, ?, ?, 0)",
          ).bind(
            String(r.id), Number(r.send_at), String(r.title),
            String(r.body), String(r.tag ?? ""), String(r.url ?? "/"),
          ),
        ),
      ];
      await env.DB.batch(statements);
      return json({ ok: true, scheduled: reminders.length });
    }

    if (url.pathname === "/api/reminders" && request.method === "GET") {
      if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);
      const { results } = await env.DB.prepare(
        "SELECT id, send_at, title, body, tag, sent FROM reminders ORDER BY send_at ASC LIMIT 100",
      ).all();
      return json({ items: results ?? [] });
    }

    if (url.pathname === "/api/health") {
      return json({
        ok: true,
        ts: Date.now(),
        push: env.VAPID_PUBLIC_KEY ? "configured" : "not configured",
      });
    }

    return json({ error: "not found" }, 404);
  },

  /**
   * Cron-driven notifications. iOS PWAs can receive Web Push but cannot
   * schedule anything locally, so every reminder the Swift app fired via
   * UNCalendarNotificationTrigger has to originate here instead.
   *
   * Runs hourly, which is what lets the reminder cadence ramp as a due date
   * approaches rather than being capped at one nudge a day.
   */
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    const keys = vapidKeys(env);
    if (!keys) return;

    const now = Date.now();
    const { results } = await env.DB.prepare(
      "SELECT id, send_at, title, body, tag, url FROM reminders WHERE sent = 0 AND send_at <= ? ORDER BY send_at ASC LIMIT 20",
    ).bind(now).all<ReminderRow>();

    for (const row of results ?? []) {
      await deliver(env, keys, {
        title: row.title, body: row.body, tag: row.tag, url: row.url || "/",
      });
      await env.DB.prepare("UPDATE reminders SET sent = 1 WHERE id = ?").bind(row.id).run();
    }

    // Housekeeping: a week of sent reminders and consumed SMS is plenty of
    // history for diagnosing a missed notification, and keeps D1 small.
    const weekAgo = now - 7 * 86_400_000;
    await env.DB.batch([
      env.DB.prepare("DELETE FROM reminders WHERE sent = 1 AND send_at < ?").bind(weekAgo),
      env.DB.prepare("DELETE FROM sms_inbox WHERE received_at < ?").bind(now - 30 * 86_400_000),
    ]);
  },
};

/** Push one notification to every registered subscription, pruning dead ones. */
async function deliver(
  env: Env,
  keys: VapidKeys,
  payload: { title: string; body: string; tag: string; url: string },
): Promise<number> {
  const { results } = await env.DB.prepare(
    "SELECT payload FROM push_subscriptions",
  ).all<{ payload: string }>();

  let sent = 0;
  for (const row of results ?? []) {
    let sub: PushSubscription;
    try {
      sub = JSON.parse(row.payload) as PushSubscription;
    } catch {
      continue;
    }
    try {
      const result = await sendPush(sub, payload, keys);
      if (result.gone) {
        // The user uninstalled or cleared the site; keeping the row would mean
        // a failing send on every future cron run.
        await env.DB.prepare("DELETE FROM push_subscriptions WHERE endpoint = ?")
          .bind(sub.endpoint).run();
      } else if (result.status >= 200 && result.status < 300) {
        sent++;
      }
    } catch {
      // One unreachable push service must not stop the rest.
    }
  }
  return sent;
}
