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
 *   POST /api/sms       Shortcut drops a raw bank SMS here. Auth via shared token.
 *   GET  /api/inbox     PWA drains anything captured since a cursor.
 *   POST /api/push/subscribe   Register a Web Push subscription.
 *
 * Web Push matters because iOS PWAs cannot schedule local notifications — there
 * is no Notification Triggers API on Safari. Bill reminders and the daily tip
 * are therefore pushed from the scheduled() cron handler below.
 */

export interface Env {
  DB: D1Database;
  /** Shared secret the Shortcut sends; keeps the endpoint from being open. */
  INGEST_TOKEN: string;
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

    // ── Web Push registration ───────────────────────────────────────────────
    if (url.pathname === "/api/push/subscribe" && request.method === "POST") {
      if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);
      const sub = await request.json().catch(() => null);
      if (!sub) return json({ error: "bad subscription" }, 400);
      await env.DB.prepare(
        "INSERT OR REPLACE INTO push_subscriptions (endpoint, payload, created_at) VALUES (?, ?, ?)",
      ).bind((sub as { endpoint: string }).endpoint, JSON.stringify(sub), Date.now()).run();
      return json({ ok: true });
    }

    if (url.pathname === "/api/health") {
      return json({ ok: true, ts: Date.now() });
    }

    return json({ error: "not found" }, 404);
  },

  /**
   * Cron-driven notifications. iOS PWAs can receive Web Push but cannot
   * schedule anything locally, so every reminder the Swift app fired via
   * UNCalendarNotificationTrigger has to originate here instead.
   *
   * Wired up in wrangler.toml; the push send itself lands in the next commit
   * alongside VAPID key handling.
   */
  async scheduled(_event: ScheduledController, _env: Env): Promise<void> {
    // TODO(next): read due bills + daily tip, send Web Push to subscriptions.
  },
};
