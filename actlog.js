// Activity log + undo: everything Zuffi adds, changes or deletes on your list is written down with a way back.
// Background housekeeping (reminder "already rang" flags, snoozes) is not logged.
import { store } from './store.js';

const LS = 'zuffiActivity';
let log = (() => { try { return JSON.parse(localStorage.getItem(LS) || '[]'); } catch { return []; } })();
const save = () => { try { localStorage.setItem(LS, JSON.stringify(log.slice(0, 150))); } catch {} };
const listeners = new Set();
export const onChange = f => listeners.add(f);
const emit = () => listeners.forEach(f => { try { f(); } catch {} });

const LABEL = { reminder: 'reminder', task: 'task', meeting: 'meeting', note: 'note', expense: 'expense', habit: 'habit', contact: 'contact', timer: 'timer' };
const QUIET = new Set(['notified', 'soonDone', 'snoozed', 'snoozeUntil', 'lastNudge', 'updated', 'log', 'counts']);
const what = it => `${LABEL[it.type] || it.type || 'item'} “${String(it.title || it.text || '').slice(0, 60)}”`;
let muted = 0;

export function add(kind, text, undo = null) {
  log.unshift({ id: Math.random().toString(36).slice(2, 10), at: Date.now(), kind, text, undo });
  if (log.length > 150) log.length = 150;
  save(); emit();
}
export const list = () => log.slice();
export function clear() { log = []; save(); emit(); }

/** Watch the store: adds, meaningful edits and deletes become undoable entries. */
export function watch() {
  const a = store.add.bind(store), u = store.update.bind(store), r = store.remove.bind(store);
  store.add = item => { const it = a(item); if (!muted && it.type !== 'timer' && it.type !== 'chatlog') add('add', `Added ${what(it)}`, { t: 'add', id: it.id }); return it; };
  store.update = (id, patch) => {
    const before = store.items.find(i => i.id === id);
    const keys = Object.keys(patch || {}).filter(k => !QUIET.has(k));
    const prev = before && keys.length ? Object.fromEntries(keys.map(k => [k, before[k] ?? null])) : null;
    const it = u(id, patch);
    if (!muted && it && prev && keys.some(k => JSON.stringify(prev[k]) !== JSON.stringify(patch[k]))) {
      const txt = 'done' in patch && keys.length <= 2 ? (patch.done ? `Ticked off ${what(it)}` : `Re-opened ${what(it)}`) : `Changed ${what(it)}`;
      add('edit', txt, { t: 'update', id, prev });
    }
    return it;
  };
  store.remove = id => { const it = store.items.find(i => i.id === id); r(id); if (!muted && it) add('remove', `Deleted ${what(it)}`, { t: 'remove', item: JSON.parse(JSON.stringify(it)) }); };
}

/** Undo one entry (the newest undoable one when id is omitted). Returns a sentence, or '' if nothing to undo. */
export function undo(id) {
  const e = id ? log.find(x => x.id === id) : log.find(x => x.undo && !x.undone);
  if (!e || !e.undo || e.undone) return '';
  muted++;
  try {
    const u = e.undo;
    if (u.t === 'add') store.remove(u.id);
    else if (u.t === 'update') store.update(u.id, u.prev);
    else if (u.t === 'remove') { store.items.push(u.item); store.save(); }
    else return '';
  } finally { muted--; }
  e.undone = true; save(); emit();
  return 'Undone: ' + e.text.charAt(0).toLowerCase() + e.text.slice(1) + '.';
}
