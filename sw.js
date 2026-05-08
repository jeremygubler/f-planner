const CACHE = 'photoplanner-v3';
const API_CACHE = 'photoplanner-api-v3';

const STATIC = [
  './',
  './index.html',
  'https://cdnjs.cloudflare.com/ajax/libs/suncalc/1.9.0/suncalc.min.js',
  'https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.js',
  'https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.css',
  'https://cdn.jsdelivr.net/npm/@fontsource/playfair-display@5/400.css',
  'https://cdn.jsdelivr.net/npm/@fontsource/playfair-display@5/700.css',
];

// ── Install: cache static assets ────────────────────────────────────────────
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(STATIC).catch(() => {}))
      .then(() => self.skipWaiting())
  );
});

// ── Activate: clean old caches ───────────────────────────────────────────────
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys.filter(k => k !== CACHE && k !== API_CACHE)
            .map(k => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

// ── Fetch: smart caching strategy ───────────────────────────────────────────
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Weather & Geocoding: Network-first, cache fallback (24h TTL)
  if (url.hostname === 'api.open-meteo.com' ||
      url.hostname === 'nominatim.openstreetmap.org') {
    e.respondWith(networkFirstWithTTL(e.request, API_CACHE, 24 * 60 * 60 * 1000));
    return;
  }

  // Map tiles: Cache-first (tiles don't change)
  if (url.hostname.includes('openstreetmap.org') ||
      url.hostname.includes('lightpollutionmap.info')) {
    e.respondWith(cacheFirst(e.request, CACHE));
    return;
  }

  // Fonts & CDN libraries: Cache-first (versioned, stable)
  if (url.hostname === 'cdnjs.cloudflare.com' ||
      url.hostname === 'cdn.jsdelivr.net' ||
      url.hostname === 'unpkg.com') {
    e.respondWith(cacheFirst(e.request, CACHE));
    return;
  }

  // App shell (index.html): Stale-while-revalidate
  if (url.pathname === '/' || url.pathname.endsWith('.html')) {
    e.respondWith(staleWhileRevalidate(e.request, CACHE));
    return;
  }

  // Default: network with cache fallback
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  );
});

// ── Cache strategies ─────────────────────────────────────────────────────────
async function cacheFirst(req, cacheName) {
  const cached = await caches.match(req);
  if (cached) return cached;
  try {
    const fresh = await fetch(req);
    if (fresh.ok) {
      const cache = await caches.open(cacheName);
      cache.put(req, fresh.clone());
    }
    return fresh;
  } catch {
    return new Response('Offline – cached version not available', { status: 503 });
  }
}

async function staleWhileRevalidate(req, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(req);
  const fetchPromise = fetch(req).then(fresh => {
    if (fresh.ok) cache.put(req, fresh.clone());
    return fresh;
  }).catch(() => null);
  return cached || await fetchPromise || offlinePage();
}

async function networkFirstWithTTL(req, cacheName, ttl) {
  try {
    const fresh = await fetch(req);
    if (fresh.ok) {
      const cache = await caches.open(cacheName);
      const resp = fresh.clone();
      // Store with timestamp header
      const headers = new Headers(resp.headers);
      headers.set('x-cached-at', Date.now().toString());
      const cachedResp = new Response(await resp.blob(), { headers });
      cache.put(req, cachedResp);
      return fresh;
    }
  } catch {}
  // Cache fallback – check TTL
  const cache = await caches.open(cacheName);
  const cached = await cache.match(req);
  if (cached) {
    const cachedAt = parseInt(cached.headers.get('x-cached-at') || '0');
    if (Date.now() - cachedAt < ttl) return cached;
  }
  return cached || new Response(
    JSON.stringify({ error: 'offline', message: 'No network – showing cached data' }),
    { status: 503, headers: { 'Content-Type': 'application/json' } }
  );
}

function offlinePage() {
  return new Response(`
    <!DOCTYPE html><html lang="de"><head><meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>PhotoPlanner – Offline</title>
    <style>body{background:#08080D;color:#EDE8DF;font-family:system-ui;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:2rem;}
    h1{font-size:2rem;margin-bottom:1rem;}p{color:rgba(237,232,223,0.5);margin-bottom:2rem;}
    button{background:#E9A42E;border:none;color:#1A0E00;padding:12px 24px;border-radius:12px;font-size:1rem;cursor:pointer;}
    </style></head><body>
    <div><div style="font-size:4rem;margin-bottom:1rem;">📷</div>
    <h1>PhotoPlanner</h1>
    <p>Keine Internetverbindung.<br>Bitte prüfe dein Netzwerk.</p>
    <button onclick="location.reload()">Erneut versuchen</button></div>
    </body></html>
  `, { headers: { 'Content-Type': 'text/html' } });
}

// ── Background Sync: Wetter-Update ──────────────────────────────────────────
self.addEventListener('sync', e => {
  if (e.tag === 'weather-sync') {
    e.waitUntil(syncWeather());
  }
});

async function syncWeather() {
  // Triggered when back online – clients can request a re-fetch
  const clients = await self.clients.matchAll();
  clients.forEach(client => client.postMessage({ type: 'SYNC_WEATHER' }));
}

// ── Push Notifications ───────────────────────────────────────────────────────
self.addEventListener('push', e => {
  const data = e.data?.json() || {};
  e.waitUntil(
    self.registration.showNotification(data.title || '📸 PhotoPlanner', {
      body: data.body || 'Gute Foto-Bedingungen heute!',
      icon: './icons/icon-192.png',
      badge: './icons/icon-72.png',
      tag: 'photoplanner-alert',
      renotify: true,
      data: { url: data.url || './' }
    })
  );
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(clients.openWindow(e.notification.data?.url || './'));
});
