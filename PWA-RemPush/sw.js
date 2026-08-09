const CACHE = 'rempush-pwa-v3';
const ASSETS = ['./', './index.html', './app.js', './manifest.webmanifest', './app-icon.svg'];
const DB_NAME = 'RemPushNotifications';
const DB_VERSION = 1;

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) return cached;
      return fetch(event.request).then(response => {
        if (response.ok && new URL(event.request.url).origin === self.location.origin) {
          const copy = response.clone();
          caches.open(CACHE).then(cache => cache.put(event.request, copy));
        }
        return response;
      }).catch(() => caches.match('./index.html'));
    })
  );
});

self.addEventListener('push', event => event.waitUntil(handlePush(event)));

async function handlePush(event) {
  let data = {};
  try { data = event.data ? event.data.json() : {}; }
  catch { data = { body: event.data?.text() || '' }; }
  const title = data.title || 'RemPush';
  const body = data.body || 'New reminder';
  const createdAt = new Date().toISOString();
  await Promise.all([
    self.registration.showNotification(title, {
      body,
      icon: data.icon || './app-icon.svg',
      badge: data.badge || './app-icon.svg',
      tag: data.tag || `rempush-${Date.now()}`,
      data: { page: data.page ?? null, url: data.url || './' }
    }),
    storeNotification({ title, body, page: data.page ?? null, createdAt, source: 'push' })
  ]);
}

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = event.notification.data?.url || './';
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    const existing = list.find(client => 'focus' in client);
    if (existing) return existing.focus();
    return clients.openWindow(url);
  }));
});

function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains('notifications')) request.result.createObjectStore('notifications', { keyPath: 'id', autoIncrement: true });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function storeNotification(value) {
  try {
    const db = await openDB();
    await new Promise((resolve, reject) => {
      const tx = db.transaction('notifications', 'readwrite');
      tx.objectStore('notifications').add(value);
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    db.close();
  } catch {}
}
