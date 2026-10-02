// Everything is saved on this phone only (localStorage).
const KEY = 'sparrow.items.v1';
const SKEY = 'sparrow.settings.v1';
const CKEY = 'sparrow.chat.v1';

const read = (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch { return d; } };
const write = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };

export const store = {
  items: read(KEY, []),
  settings: Object.assign({
    name: '', city: '', gender: 'female', speak: true, model: 'Qwen2.5-0.5B-Instruct',
    aiReady: false, keys: { gemini: '', openai: '', claude: '' }, lastBriefDay: '',
  }, read(SKEY, {})),
  chat: read(CKEY, []),
  listeners: new Set(),

  save() { write(KEY, this.items); write(SKEY, this.settings); write(CKEY, this.chat.slice(-60)); this.listeners.forEach(f => f()); },
  onChange(f) { this.listeners.add(f); },

  add(item) {
    const it = Object.assign({ id: crypto.randomUUID?.() ?? String(Date.now() + Math.random()), done: false,
      created: new Date().toISOString(), when: null, notified: false }, item);
    this.items.push(it); this.save(); return it;
  },
  update(id, patch) { const it = this.items.find(i => i.id === id); if (it) { Object.assign(it, patch); this.save(); } return it; },
  remove(id) { this.items = this.items.filter(i => i.id !== id); this.save(); },
  clearAll() { this.items = []; this.chat = []; localStorage.removeItem(KEY); localStorage.removeItem(CKEY); this.save(); },

  ofType(t) { return this.items.filter(i => i.type === t); },
  /** Meetings, reminders and dated tasks happening on a given day, sorted by time. */
  onDay(date) {
    const d0 = new Date(date); d0.setHours(0, 0, 0, 0);
    const d1 = new Date(d0); d1.setDate(d1.getDate() + 1);
    return this.items.filter(i => i.when && i.type !== 'note' && new Date(i.when) >= d0 && new Date(i.when) < d1)
      .sort((a, b) => new Date(a.when) - new Date(b.when));
  },
  openTasks() { return this.items.filter(i => i.type === 'task' && !i.done); },
};
