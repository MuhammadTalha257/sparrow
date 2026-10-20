// Every Zuffi feature in one place, for the dashboard. Each plan sees only its own features:
//   Pro → everyday, create, documents, devices      Business (and the trial) → the business features first, then Pro's
// Business features also follow the country: Pakistan → estate agents (property stock, listing posts);
// UK → small businesses (clients, bookings, offers). "Just me" hides business everywhere.

/** Simple line icons (24×24, drawn with currentColor). */
export const ICONS = {
  briefcase: '<rect x="3" y="7" width="18" height="13" rx="2.5"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12.5h18"/>',
  chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>',
  whatsapp: '<path d="M20.5 11.6a8.5 8.5 0 0 1-12.6 7.4L3.5 20.5l1.5-4.3a8.5 8.5 0 1 1 15.5-4.6z"/><path d="M9 8.5c0 3.5 2.5 6.5 6.5 6.5l1-1.6-2-1-1 .8a4 4 0 0 1-2.2-2.2l.8-1-1-2z"/>',
  bot: '<rect x="4" y="8" width="16" height="11" rx="3"/><path d="M12 4v4M9 13h.01M15 13h.01M9.5 16.5h5"/><circle cx="12" cy="3.5" r="1"/>',
  megaphone: '<path d="M3 10v4a1 1 0 0 0 1 1h2l5 4V5L6 9H4a1 1 0 0 0-1 1zM15 8.5a5 5 0 0 1 0 7M18 6a8.5 8.5 0 0 1 0 12"/>',
  home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14a6.5 6.5 0 0 1 3.5 6"/>',
  wallet: '<rect x="3" y="6" width="18" height="14" rx="2.5"/><path d="M3 10h18M16 15h2"/><path d="M6 6l9-3 1 3"/>',
  team: '<circle cx="12" cy="7" r="3.2"/><path d="M5.5 20a6.5 6.5 0 0 1 13 0"/><circle cx="4.5" cy="10" r="2"/><circle cx="19.5" cy="10" r="2"/>',
  receipt: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
  coins: '<ellipse cx="9" cy="7" rx="6" ry="3"/><path d="M3 7v5c0 1.7 2.7 3 6 3s6-1.3 6-3V7"/><path d="M9 15v2c0 1.7 2.7 3 6 3s6-1.3 6-3v-5c0-1.6-2.4-2.9-5.5-3"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
  history: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 2"/>',
  brain: '<path d="M9 4a3 3 0 0 0-3 3v.5A3 3 0 0 0 4 10.5 3 3 0 0 0 5 15a3 3 0 0 0 4 4.5V4zM15 4a3 3 0 0 1 3 3v.5a3 3 0 0 1 2 3 3 3 0 0 1-1 4.5 3 3 0 0 1-4 4.5V4z"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
  target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
  clipboard: '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V3h6v1M9 10h6M9 14h6"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  job: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5h6v2M12 12v3"/>',
  doc: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h5"/>',
  image: '<rect x="3" y="4" width="18" height="16" rx="2.5"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-9 9"/>',
  sparkle: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>',
  camera: '<path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"/><circle cx="12" cy="13.5" r="3.5"/>',
  film: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
  convert: '<path d="M4 7h13l-3-3M20 17H7l3 3"/>',
  pen: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M14 6l4 4"/>',
  layers: '<path d="m12 3 9 5-9 5-9-5z"/><path d="m3 13 9 5 9-5"/>',
  pages: '<rect x="4" y="3" width="12" height="16" rx="2"/><path d="M8 21h10a2 2 0 0 0 2-2V7"/>',
  rotate: '<path d="M20 12a8 8 0 1 1-2.3-5.7L20 8"/><path d="M20 3v5h-5"/>',
  send: '<path d="M4 12 20 4l-4 16-4-7z"/><path d="m12 13 8-9"/>',
  sync: '<path d="M20 11a8 8 0 0 0-14.3-4.3L4 8M4 13a8 8 0 0 0 14.3 4.3L20 16"/><path d="M4 3v5h5M20 21v-5h-5"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  broom: '<path d="M14 4l6 6M4 20l7-7M9 11l4 4-4 5H4v-5z"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  bell: '<path d="M6 16V11a6 6 0 1 1 12 0v5l2 2H4z"/><path d="M10 20a2 2 0 0 0 4 0"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m4 7 8 6 8-6"/>',
  calendar: '<rect x="3" y="4" width="18" height="17" rx="2.5"/><path d="M3 9h18M8 2v4M16 2v4"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
  phone: '<rect x="7" y="2" width="10" height="20" rx="2.5"/><path d="M11 18h2"/>',
  check: '<path d="m5 12 5 5L20 7"/>',
  upload: '<path d="M12 16V4M7 9l5-5 5 5M4 20h16"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
};
export const icon = (name, size = 20) => `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ICONS.grid}</svg>`;

export const CATS = [
  ['business', 'For your business'], ['everyday', 'Every day'], ['create', 'Create'], ['documents', 'Documents & PDF'], ['devices', 'Your devices'],
];

// open: { tool } opens a tool panel · { biz } opens a Business tab · { go } opens a page
// plan: 'pro' (Pro, Business, trial) · 'business' (Business and trial) · 'proOnly' (hidden for Business: a business doesn't need it)
// when(ctx): extra rule — country, business type, computer only…
export const FEATURES = [
  // ---- Business ----
  { id: 'bizToday', short: 'Today', cat: 'business', plan: 'business', icon: 'briefcase', tint: '#4C8DFF', name: 'Business today', sub: 'Who needs a reply, follow-ups and money', open: { biz: 'today' } },
  { id: 'bizLeads', short: 'Leads', cat: 'business', plan: 'business', icon: 'whatsapp', tint: '#25B868', name: 'WhatsApp leads', sub: 'Every new chat becomes a lead', open: { biz: 'leads' } },
  { id: 'agent', short: 'WhatsApp agent', cat: 'business', plan: 'business', icon: 'bot', tint: '#8B7CF6', name: 'WhatsApp agent', sub: 'Teach Zuffi your business — replies in the customer’s language', open: { tool: 'agent' } },
  { id: 'promo', short: 'Posts & reels', cat: 'business', plan: 'business', icon: 'megaphone', tint: '#F2994A', name: 'Posts & reels', sub: 'Ready-made posts, flyers and reels for your business', open: { tool: 'promo' } },
  { id: 'bizStock', short: 'Properties', cat: 'business', plan: 'business', icon: 'home', tint: '#E0A23B', name: 'Property stock', sub: 'Plots, houses and rentals you’re selling', open: { biz: 'stock' }, when: c => c.estate },
  { id: 'bizClients', short: 'Clients', cat: 'business', plan: 'business', icon: 'users', tint: '#E0A23B', name: 'Clients', sub: 'Regulars, bookings and history', open: { biz: 'clients' }, when: c => !c.estate },
  { id: 'bizMoney', short: 'Money', cat: 'business', plan: 'business', icon: 'wallet', tint: '#2EAD7A', name: 'Money & late payers', sub: 'In, out and who owes you', open: { biz: 'money' } },
  { id: 'bizTeam', short: 'Team', cat: 'business', plan: 'business', icon: 'team', tint: '#5B8DEF', name: 'Team & staff', sub: 'Staff, pay and who does what', open: { biz: 'team' }, when: c => !c.freelance },
  { id: 'quote', short: 'Invoices', cat: 'business', plan: 'business', icon: 'receipt', tint: '#3B82F6', name: 'Quotes & invoices', sub: 'Say it, get a PDF', open: { tool: 'quote' } },
  { id: 'expenses', short: 'Expenses', cat: 'business', plan: 'business', icon: 'coins', tint: '#22A06B', name: 'Expenses', sub: 'Track what the business spends', open: { tool: 'expenses' } },
  { id: 'timer', short: 'Time tracker', cat: 'business', plan: 'business', icon: 'clock', tint: '#0EA5B7', name: 'Time tracker', sub: 'Hours per client', open: { tool: 'timer' }, when: c => !c.estate },
  { id: 'report', short: 'Report', cat: 'business', plan: 'business', icon: 'chart', tint: '#6366F1', name: 'Daily report', sub: 'What got done today', open: { tool: 'report' } },
  { id: 'bizMore', short: 'Business settings', cat: 'business', plan: 'business', icon: 'settings', tint: '#7A8496', name: 'Business settings', sub: 'Details, devices, automations', open: { biz: 'more' } },
  // ---- Every day ----
  { id: 'planday', short: 'Plan my day', cat: 'everyday', plan: 'pro', icon: 'calendar', tint: '#4F6BFF', name: 'Plan my day', sub: 'Fits your tasks around meetings and your calendar', open: { tool: 'planday' } },
  { id: 'activity', short: 'Undo', cat: 'everyday', plan: 'pro', icon: 'history', tint: '#7A8496', name: 'Activity & undo', sub: 'What Zuffi did — undo anything', open: { tool: 'activity' } },
  { id: 'memory', short: 'Memory', cat: 'everyday', plan: 'pro', icon: 'brain', tint: '#8B7CF6', name: 'Memory', sub: 'Notes, chats and files Zuffi remembers', open: { go: 'memory' } },
  { id: 'meeting', short: 'Meeting notes', cat: 'everyday', plan: 'pro', icon: 'mic', tint: '#E5577E', name: 'Meeting notes', sub: 'Record, get a clean summary', open: { tool: 'meeting' } },
  { id: 'focus', short: 'Focus', cat: 'everyday', plan: 'pro', icon: 'target', tint: '#E0A23B', name: 'Focus timer', sub: '25 minutes of deep work', open: { tool: 'focus' } },
  { id: 'snippets', short: 'Snippets', cat: 'everyday', plan: 'pro', icon: 'clipboard', tint: '#14A39A', name: 'Snippets', sub: 'Text you paste often', open: { tool: 'snippets' } },
  { id: 'jobs', short: 'Jobs', cat: 'everyday', plan: 'proOnly', icon: 'job', tint: '#A161E8', name: 'Job agent', sub: 'Find jobs, tailor your CV', open: { tool: 'jobs' } },
  // ---- Create ----
  { id: 'picture', short: 'Make a picture', cat: 'create', plan: 'pro', icon: 'sparkle', tint: '#A161E8', name: 'Make a picture', sub: 'Images and posters from words', open: { tool: 'picture' } },
  { id: 'studio', short: 'Photo studio', cat: 'create', plan: 'pro', icon: 'camera', tint: '#E5577E', name: 'Photo studio', sub: 'Brighten, resize, add your logo', open: { tool: 'studio' } },
  { id: 'blur', short: 'Blur private info', cat: 'create', plan: 'pro', icon: 'eye', tint: '#475569', name: 'Blur faces & private info', sub: 'Hide faces, emails, phone numbers and names in a picture', open: { tool: 'blur' } },
  { id: 'reels', short: 'Reels', cat: 'create', plan: 'pro', icon: 'film', tint: '#EF5A5A', name: 'Quick reels', sub: 'Trim, caption, ready for Reels & Status', open: { tool: 'reels' } },
  // ---- Documents ----
  { id: 'office', short: 'Word & Excel', cat: 'documents', plan: 'pro', icon: 'doc', tint: '#2B6CD8', name: 'Word, Excel & PowerPoint', sub: 'Describe it — get the file', open: { tool: 'office' } },
  { id: 'convert', short: 'Convert', cat: 'documents', plan: 'pro', icon: 'convert', tint: '#0EA5E9', name: 'Convert files', sub: 'JPG, PNG, WebP, PDF, text', open: { tool: 'convert' } },
  { id: 'sign', short: 'Sign PDF', cat: 'documents', plan: 'pro', icon: 'pen', tint: '#22A06B', name: 'Sign a PDF', sub: 'Draw your signature, done', open: { tool: 'sign' } },
  { id: 'merge', short: 'Merge PDFs', cat: 'documents', plan: 'pro', icon: 'layers', tint: '#E25A5A', name: 'Merge PDFs', sub: 'Join several into one', open: { tool: 'merge' } },
  { id: 'images', short: 'Photos → PDF', cat: 'documents', plan: 'pro', icon: 'image', tint: '#F08A3E', name: 'Photos → PDF', sub: 'Pictures into one PDF', open: { tool: 'images' } },
  { id: 'pages', short: 'Keep pages', cat: 'documents', plan: 'pro', icon: 'pages', tint: '#D9A21B', name: 'Keep pages', sub: 'Pick the pages you need', open: { tool: 'pages' } },
  { id: 'rotate', short: 'Rotate PDF', cat: 'documents', plan: 'pro', icon: 'rotate', tint: '#0EA5E9', name: 'Rotate PDF', sub: 'Turn pages the right way', open: { tool: 'rotate' } },
  // ---- Devices ----
  { id: 'screenrec', short: 'Record screen', cat: 'devices', plan: 'pro', icon: 'film', tint: '#E5484D', name: 'Screen recorder', sub: 'Record your screen with sound — saved as a video', open: { tool: 'screenrec' }, when: c => c.desktop || c.mac },
  { id: 'send', short: 'Send files', cat: 'devices', plan: 'pro', icon: 'send', tint: '#2F6FEB', name: 'Send to my devices', sub: 'Files and links between phone and computer', open: { tool: 'send' } },
  { id: 'sync', short: 'Sync', cat: 'devices', plan: 'pro', icon: 'sync', tint: '#14A37F', name: 'Sync devices', sub: 'Same Zuffi everywhere', open: { tool: 'sync' } },
  { id: 'find', short: 'Find files', cat: 'devices', plan: 'pro', icon: 'folder', tint: '#7A8496', name: 'Find files', sub: 'Search by what you remember', open: { tool: 'find' }, when: c => c.desktop },
  { id: 'tidy', short: 'Tidy up', cat: 'devices', plan: 'pro', icon: 'broom', tint: '#D9628F', name: 'Tidy Downloads', sub: 'Sort the mess in one tap', open: { tool: 'tidy' }, when: c => c.desktop },
  { id: 'clipboard', short: 'Clipboard', cat: 'devices', plan: 'pro', icon: 'clipboard', tint: '#8B6CF0', name: 'Clipboard', sub: 'Everything you copied', open: { tool: 'clipboard' }, when: c => c.desktop },
  { id: 'watch', short: 'Watch folder', cat: 'devices', plan: 'pro', icon: 'eye', tint: '#0891B2', name: 'Watch a folder', sub: 'Act when new files arrive', open: { tool: 'watch' }, when: c => c.desktop },
];

/**
 * The features this person sees.
 * ctx: { business: on the Business plan or trial, personal: chose "Just me", estate, freelance, desktop }
 */
export function visible(ctx) {
  const bizOn = ctx.business && !ctx.personal;
  return FEATURES.filter(f => {
    if (f.plan === 'business' && !bizOn) return false;
    if (f.plan === 'proOnly' && bizOn) return false;
    if (f.when && !f.when(ctx)) return false;
    return true;
  });
}

/** Search across names and descriptions ("pdf", "invoice", "whatsapp"…). */
export function search(list, q) {
  const words = String(q || '').toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return list;
  return list.filter(f => { const hay = (f.name + ' ' + f.sub + ' ' + f.cat).toLowerCase(); return words.every(w => hay.includes(w)); });
}
