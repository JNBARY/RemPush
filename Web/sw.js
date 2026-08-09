const CACHE = 'rempush-pwa-v1';
const ASSETS = ['./', './index.html', './app.js', './manifest.webmanifest', './icon.svg'];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  event.respondWith(caches.match(event.request).then(cached => cached || fetch(event.request).then(response => {
    const copy = response.clone();
    caches.open(CACHE).then(cache => cache.put(event.request, copy));
    return response;
  }).catch(() => caches.match('./index.html'))));
});

self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { data = { body: event.data?.text() || '' }; }
  const title = data.title || 'RemPush';
  const body = data.body || 'New reminder';
  const notification = {
    body,
    icon: data.icon || 'icon.svg',
    badge: data.badge || 'icon.svg',
    tag: data.tag || `rempush-${Date.now()}`,
    data: { page: data.page || null, url: data.url || './' }
  };
  event.waitUntil(Promise.all([
    self.registration.showNotification(title, notification),
    storeNotification({ title, body, page: data.page || null, createdAt: new Date().toISOString(), source: 'push' })
  ]));
});

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
    const request = indexedDB.open('RemPushNotifications', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('notifications', { keyPath: 'id', autoIncrement: true });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
async function storeNotification(value) {
  try {
    const db = await openDB();
    const tx = db.transaction('notifications', 'readwrite');
    tx.objectStore('notifications').add(value);
  } catch {}
}
