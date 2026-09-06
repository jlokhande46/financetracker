-- Raw SMS captured by the Shortcuts automation, before parsing.
-- Parsing happens client-side so the bank formats stay in one place.
CREATE TABLE IF NOT EXISTS sms_inbox (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  text        TEXT    NOT NULL,
  received_at INTEGER NOT NULL,
  consumed    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_sms_inbox_received ON sms_inbox(received_at);

CREATE TABLE IF NOT EXISTS push_subscriptions (
  endpoint   TEXT PRIMARY KEY,
  payload    TEXT    NOT NULL,
  created_at INTEGER NOT NULL
);

-- Queued notifications. The PWA works out what it wants to be reminded about
-- from its own IndexedDB and uploads only the text and the send time, so the
-- cron can fire them without the server ever seeing a transaction.
CREATE TABLE IF NOT EXISTS reminders (
  id      TEXT    PRIMARY KEY,
  send_at INTEGER NOT NULL,
  title   TEXT    NOT NULL,
  body    TEXT    NOT NULL,
  tag     TEXT    NOT NULL DEFAULT '',
  url     TEXT    NOT NULL DEFAULT '/',
  sent    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_reminders_pending ON reminders(sent, send_at);
