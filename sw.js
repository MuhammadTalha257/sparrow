// Sparrow offline cache: always tries the network first (so updates arrive), falls back to the cache offline.
const VERSION = 'sparrow-v13';
const SHELL = ['./', 'index.html', 'style.css', 'app.js', 'brain.js', 'store.js', 'ai.js', 'i18n.js', 'prayer.js', 'memory.js', 'tools.js', 'sync.js', 'jobs.js', 'live.js', 'mascot.js', 'bird.js', 'maclink.js', 'mascots/sparrow-directions.webp', 'mascots/sparrow-reactions.webp',
  'lib/chrono.js', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;   // AI services, weather: straight to the network
  e.respondWith(
    fetch(e.request).then(res => {
      if (res.ok) { const copy = res.clone(); caches.open(VERSION).then(c => c.put(e.request, copy)); }
      return res;
    }).catch(() => caches.match(e.request).then(hit => hit || caches.match('index.html')))
  );
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window' }).then(cs => cs[0] ? cs[0].focus() : self.clients.openWindow('./')));
});
