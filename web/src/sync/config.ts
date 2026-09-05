/**
 * Backend connection settings.
 *
 * Kept in localStorage rather than baked in at build time so the same deployed
 * PWA can point at your own Worker without a rebuild. The token is a shared
 * secret for a single-user API — it authorises the SMS ingest endpoint, it is
 * not a user password.
 */

const KEY_URL = "ft.serverUrl";
const KEY_TOKEN = "ft.ingestToken";
const KEY_CURSOR = "ft.inboxCursor";
const KEY_HIDDEN = "ft.hideAmounts";
const KEY_THEME = "ft.theme";

const read = (k: string) => {
  try { return localStorage.getItem(k); } catch { return null; }
};
const write = (k: string, v: string) => {
  try { localStorage.setItem(k, v); } catch { /* private mode / quota */ }
};

export const serverConfig = {
  get url(): string { return read(KEY_URL) ?? ""; },
  set url(v: string) { write(KEY_URL, v.trim().replace(/\/+$/, "")); },

  get token(): string { return read(KEY_TOKEN) ?? ""; },
  set token(v: string) { write(KEY_TOKEN, v.trim()); },

  /** Highest `received_at` already drained, so we never re-import an SMS. */
  get cursor(): number { return Number(read(KEY_CURSOR) ?? 0); },
  set cursor(v: number) { write(KEY_CURSOR, String(v)); },

  get isConfigured(): boolean { return this.url.length > 0 && this.token.length > 0; },
};

export const prefs = {
  get hideAmounts(): boolean { return read(KEY_HIDDEN) === "1"; },
  set hideAmounts(v: boolean) { write(KEY_HIDDEN, v ? "1" : "0"); },

  get theme(): "dark" | "light" { return read(KEY_THEME) === "light" ? "light" : "dark"; },
  set theme(v: "dark" | "light") {
    write(KEY_THEME, v);
    document.documentElement.dataset.theme = v;
  },
};

export function applyStoredTheme(): void {
  document.documentElement.dataset.theme = prefs.theme;
}
