/**
 * Insight cards the user has waved away.
 *
 * Kept in localStorage rather than IndexedDB deliberately: this is a per-device
 * display preference, not ledger data, and it should not travel in a backup
 * export that someone restores onto a fresh phone expecting their transactions.
 *
 * Ids are stable hashes of kind + month (see `insightId`), so a dismissal
 * survives pull-to-refresh, a month change and a relaunch — which is precisely
 * what PF-19 / PF-30 pin down on the iOS side.
 */

const KEY = "ft.dismissedInsights";

function read(): string[] {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as string[]) : [];
  } catch {
    return [];
  }
}

function write(ids: string[]): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(ids));
  } catch { /* private mode / quota */ }
}

export const dismissedInsights = {
  get ids(): string[] { return read(); },

  has(id: string): boolean { return read().includes(id); },

  dismiss(id: string): void {
    const ids = read();
    if (!ids.includes(id)) write([...ids, id]);
  },

  /** Developer-options escape hatch: bring every hidden card back. */
  restoreAll(): void { write([]); },

  get count(): number { return read().length; },
};
