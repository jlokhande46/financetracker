/// <reference lib="webworker" />
import { cleanupOutdatedCaches, precacheAndRoute } from "workbox-precaching";
import { clientsClaim } from "workbox-core";

/**
 * Service worker.
 *
 * Written by hand rather than generated, because the whole point of the backend
 * is Web Push and a generated worker has no `push` handler. Precaching is still
 * Workbox's — `self.__WB_MANIFEST` is injected at build time.
 */

declare const self: ServiceWorkerGlobalScope & {
  __WB_MANIFEST: Array<{ url: string; revision: string | null }>;
};

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();

// Take over immediately so a push arriving right after an update isn't handled
// by a worker that's already been replaced.
self.skipWaiting();
clientsClaim();

interface PushPayload {
  title: string;
  body: string;
  tag?: string;
  url?: string;
}

/**
 * Where the app is served from — "/" or "/financetracker/" on a GitHub Pages
 * project site. The worker sits at the root of its own scope, so deriving this
 * from its own URL keeps icons and click targets correct without the build
 * having to inject a constant.
 */
const BASE = new URL("./", self.location.href).pathname;

self.addEventListener("push", (event: PushEvent) => {
  let payload: PushPayload = { title: "FinanceTracker", body: "You have a reminder." };
  try {
    if (event.data) payload = { ...payload, ...event.data.json() as PushPayload };
  } catch {
    // A non-JSON payload still deserves a visible notification: the permission
    // is granted on the promise that every push shows one, and browsers will
    // eventually revoke it if we stay silent.
    if (event.data) payload.body = event.data.text();
  }

  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      // Same tag replaces rather than stacks — three nudges about one bill
      // should be one lock-screen row, not three.
      tag: payload.tag ?? "financetracker",
      renotify: true,
      icon: `${BASE}icons/icon-192.png`,
      badge: `${BASE}icons/icon-192.png`,
      data: { url: payload.url ?? BASE },
    } as NotificationOptions),
  );
});

self.addEventListener("notificationclick", (event: NotificationEvent) => {
  event.notification.close();
  const target = (event.notification.data as { url?: string } | undefined)?.url ?? BASE;

  event.waitUntil((async () => {
    const clients = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    // Focus an open window rather than opening a second copy of the app.
    for (const client of clients) {
      if ("focus" in client) {
        await client.focus();
        if ("navigate" in client) await client.navigate(target).catch(() => undefined);
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});
