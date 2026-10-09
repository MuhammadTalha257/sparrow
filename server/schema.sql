-- Zuffi Business server (Cloudflare D1)
CREATE TABLE IF NOT EXISTS leads (
  phone TEXT PRIMARY KEY,            -- WhatsApp id: digits with country code, e.g. 923331234567
  name TEXT DEFAULT '', source TEXT DEFAULT '', interest TEXT DEFAULT '', area TEXT DEFAULT '', budget TEXT DEFAULT '',
  status TEXT DEFAULT 'New', priority TEXT DEFAULT '', assigned TEXT DEFAULT '',
  added TEXT DEFAULT '', last_contact TEXT DEFAULT '', next_follow_up TEXT DEFAULT '',
  last_message TEXT DEFAULT '', last_message_at TEXT DEFAULT '', last_inbound_at TEXT DEFAULT '',
  notes TEXT DEFAULT '', draft TEXT DEFAULT '', voice_text TEXT DEFAULT '', changed_by TEXT DEFAULT '',
  updated_at TEXT DEFAULT ''
);
CREATE INDEX IF NOT EXISTS leads_updated ON leads(updated_at);
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY, phone TEXT, direction TEXT, kind TEXT, body TEXT, staff TEXT DEFAULT '', at TEXT
);
CREATE INDEX IF NOT EXISTS messages_phone ON messages(phone, at);
CREATE TABLE IF NOT EXISTS activity (
  at TEXT, lead TEXT, staff TEXT, kind TEXT, detail TEXT
);
CREATE TABLE IF NOT EXISTS settings (k TEXT PRIMARY KEY, v TEXT);
