// Everything is saved on this device only (localStorage). Big things (files, memory) live in memory.js (IndexedDB).
const KEY = 'sparrow.items.v1';
const SKEY = 'sparrow.settings.v1';
const CKEY = 'sparrow.chat.v1';

const read = (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch { return d; } };
const write = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };
const uid = () => (crypto.randomUUID?.() ?? (Date.now().toString(36) + Math.random().toString(36).slice(2)));

export const DEFAULT_SETTINGS = {
  name: '', city: '', gender: 'female', speak: true, model: 'Qwen2.5-0.5B-Instruct',
  aiReady: false, provider: 'auto', ollamaModel: '',
  keys: { gemini: '', openai: '', claude: '', grok: '', deepseek: '', mistral: '', groq: '', openrouter: '', perplexity: '' },
  models: {},
  lastBriefDay: '', morningOn: true, morningTime: '08:30', nightOn: true, nightTime: '21:30', lead: 5, lastMorning: '', lastNight: '',
  theme: 'sunset', lang: 'en', simple: false,
  wake: true, micButton: true, conversation: true, musicApp: 'spotify',
  prayer: { on: false, method: 'Karachi', asr: 'Hanafi', before: 10, speak: true },
  business: { name: '', address: '', currency: '£', invoiceNo: 1, quoteNo: 1 },
  memory: { on: true, keepCopies: false, days: 0, recentFiles: false },
  snippets: [],
  quick: null,
};

function mergeSettings(saved) {
  const s = Object.assign({}, DEFAULT_SETTINGS, saved || {});
  if (!s.lookV3) { s.theme = 'sunset'; s.lookV3 = true; }   // back to the warm glass look
  for (const k of ['keys', 'prayer', 'business', 'memory']) s[k] = Object.assign({}, DEFAULT_SETTINGS[k], (saved || {})[k] || {});
  return s;
}

export const store = {
  items: read(KEY, []),
  settings: mergeSettings(read(SKEY, {})),
  chat: read(CKEY, []),
  listeners: new Set(),

  save() { write(KEY, this.items); write(SKEY, this.settings); write(CKEY, this.chat.slice(-80)); this.listeners.forEach(f => { try { f(); } catch (e) { console.error(e); } }); },
  onChange(f) { this.listeners.add(f); },

  add(item) {
    const now = new Date().toISOString();
    const it = Object.assign({ id: uid(), done: false, created: now, updated: now, when: null, notified: false }, item);
    this.items.push(it); this.save(); return it;
  },
  update(id, patch) {
    const it = this.items.find(i => i.id === id);
    if (it) { Object.assign(it, patch, { updated: new Date().toISOString() }); this.save(); }
    return it;
  },
  remove(id) { this.items = this.items.filter(i => i.id !== id); this.save(); },
  clearAll() { this.items = []; this.chat = []; localStorage.removeItem(KEY); localStorage.removeItem(CKEY); this.save(); },

  ofType(t) { return this.items.filter(i => i.type === t); },
  /** Meetings, reminders and dated tasks happening on a given day, sorted by time. */
  onDay(date) {
    const d0 = new Date(date); d0.setHours(0, 0, 0, 0);
    const d1 = new Date(d0); d1.setDate(d1.getDate() + 1);
    return this.items.filter(i => i.when && ['task', 'meeting', 'reminder'].includes(i.type) && new Date(i.when) >= d0 && new Date(i.when) < d1)
      .sort((a, b) => new Date(a.when) - new Date(b.when));
  },
  openTasks() { return this.items.filter(i => i.type === 'task' && !i.done); },
  /** Merge items from another device: the newest version of each item wins. */
  merge(incoming) {
    let added = 0, changed = 0;
    for (const it of incoming || []) {
      const mine = this.items.find(i => i.id === it.id);
      if (!mine) { this.items.push(it); added++; }
      else if ((it.updated || it.created || '') > (mine.updated || mine.created || '')) { Object.assign(mine, it); changed++; }
    }
    this.save();
    return { added, changed };
  },
};
export { uid };
