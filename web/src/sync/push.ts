import { serverConfig } from "./config";
import type { ScheduledReminder, ScheduleOptions } from "../domain/reminderSchedule";

/**
 * Web Push registration and reminder upload.
 *
 * iOS is the constraint here, and it's worth being explicit about it:
 *
 *   - Push works only for an **installed** PWA (Add to Home Screen), iOS 16.4+.
 *     In a Safari tab the API is simply absent, so the UI has to say why rather
 *     than showing a button that does nothing.
 *   - Permission must be requested from a user gesture. Asking on load gets
 *     denied permanently on some browsers.
 *   - There is no local scheduling. Everything is server-sent, which is why the
 *     schedule gets uploaded rather than set with a timer.
 */

const KEY_ENABLED = "ft.pushEnabled";
const KEY_OPTIONS = "ft.pushOptions";

const read = (k: string) => {
  try { return localStorage.getItem(k); } catch { return null; }
};
const write = (k: string, v: string) => {
  try { localStorage.setItem(k, v); } catch { /* private mode / quota */ }
};

const DEFAULT_OPTIONS: ScheduleOptions = { bills: true, statements: true, tips: false };

export const pushPrefs = {
  get enabled(): boolean { return read(KEY_ENABLED) === "1"; },
  set enabled(v: boolean) { write(KEY_ENABLED, v ? "1" : "0"); },

  get options(): ScheduleOptions {
    try {
      const raw = read(KEY_OPTIONS);
      return raw ? { ...DEFAULT_OPTIONS, ...JSON.parse(raw) as Partial<ScheduleOptions> } : DEFAULT_OPTIONS;
    } catch {
      return DEFAULT_OPTIONS;
    }
  },
  set options(v: ScheduleOptions) { write(KEY_OPTIONS, JSON.stringify(v)); },
};

export type PushSupport =
  | { supported: true }
  | { supported: false; reason: string };

/**
 * Whether this browser can do Web Push at all, with a reason when it can't —
 * "notifications aren't available" alone leaves the user with nothing to act on.
 */
export function pushSupport(): PushSupport {
  // Feature-detect off globalThis rather than `"X" in window`: the `in` form
  // narrows `window` itself to `never` inside the failing branch, which is
  // where we still need matchMedia to tell "not installed" from "unsupported".
  const g = globalThis as Partial<Window & typeof globalThis>;

  if (typeof navigator === "undefined" || !navigator.serviceWorker) {
    return { supported: false, reason: "This browser has no service worker support." };
  }
  if (!g.PushManager) {
    const iOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
    const installed = g.matchMedia?.("(display-mode: standalone)").matches === true ||
      (navigator as { standalone?: boolean }).standalone === true;
    if (iOS && !installed) {
      return {
        supported: false,
        reason: "On iOS, notifications only work once the app is added to the Home Screen. Tap Share → Add to Home Screen, then open it from there.",
      };
    }
    return { supported: false, reason: "This browser doesn't support Web Push." };
  }
  return { supported: true };
}

/** VAPID public keys travel as base64url; PushManager wants raw bytes. */
function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padded = (base64 + "=".repeat((4 - base64.length % 4) % 4))
    .replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(padded);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

export interface EnableResult {
  ok: boolean;
  detail: string;
}

/**
 * Ask for permission, subscribe, and register with the Worker.
 *
 * Must be called from a click — browsers ignore a permission prompt that isn't
 * tied to a gesture, and some remember the dismissal permanently.
 */
export async function enablePush(): Promise<EnableResult> {
  const support = pushSupport();
  if (!support.supported) return { ok: false, detail: support.reason };
  if (!serverConfig.isConfigured) {
    return { ok: false, detail: "Set your server URL and token first — reminders are sent from there." };
  }

  let vapidPublicKey: string | null = null;
  try {
    const res = await fetch(`${serverConfig.url}/api/push/vapid`);
    vapidPublicKey = ((await res.json()) as { publicKey: string | null }).publicKey;
  } catch {
    return { ok: false, detail: "Couldn't reach the server to fetch its push key." };
  }
  if (!vapidPublicKey) {
    return { ok: false, detail: "The server has no VAPID keys set. Run `npm run vapid` in worker/ and add them as secrets." };
  }

  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    return {
      ok: false,
      detail: permission === "denied"
        ? "Notifications are blocked for this site. Re-allow them in your browser's site settings."
        : "Notification permission wasn't granted.",
    };
  }

  const registration = await navigator.serviceWorker.ready;
  // Reuse an existing subscription; re-subscribing with a different key silently
  // fails on some browsers.
  const subscription =
    await registration.pushManager.getSubscription() ??
    await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(vapidPublicKey) as BufferSource,
    });

  const res = await fetch(`${serverConfig.url}/api/push/subscribe`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${serverConfig.token}`,
    },
    body: JSON.stringify(subscription.toJSON()),
  });
  if (!res.ok) {
    return { ok: false, detail: `The server rejected the subscription (${res.status}).` };
  }

  pushPrefs.enabled = true;
  return { ok: true, detail: "Notifications are on." };
}

export async function disablePush(): Promise<void> {
  pushPrefs.enabled = false;
  try {
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    await subscription?.unsubscribe();
  } catch { /* nothing registered */ }
}

/**
 * Replace the server's pending schedule with the one just computed.
 *
 * Wholesale replacement, not a merge: the client recomputes from its own data,
 * so a reminder for a bill that's now paid must not survive the upload.
 */
export async function uploadSchedule(reminders: ScheduledReminder[]): Promise<boolean> {
  if (!serverConfig.isConfigured || !pushPrefs.enabled) return false;
  try {
    const res = await fetch(`${serverConfig.url}/api/reminders`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${serverConfig.token}`,
      },
      body: JSON.stringify({ reminders }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

/** Fire one push right now, to prove the whole chain works. */
export async function sendTestPush(): Promise<EnableResult> {
  if (!serverConfig.isConfigured) return { ok: false, detail: "Server not configured." };
  try {
    const res = await fetch(`${serverConfig.url}/api/push/test`, {
      method: "POST",
      headers: { authorization: `Bearer ${serverConfig.token}` },
    });
    if (res.status === 503) return { ok: false, detail: "The server has no VAPID keys set." };
    if (!res.ok) return { ok: false, detail: `Server responded ${res.status}.` };
    const body = (await res.json()) as { sent: number };
    return body.sent > 0
      ? { ok: true, detail: "Sent — it should arrive in a few seconds." }
      : { ok: false, detail: "No device is subscribed. Turn notifications on first." };
  } catch (e) {
    return { ok: false, detail: e instanceof Error ? e.message : "Couldn't reach the server." };
  }
}
