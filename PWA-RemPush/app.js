const COLORS = ['#ff0000','#ff9500','#ffd60a','#34c759','#63e6be','#00d9ff','#007aff','#af52de','#ff2d55'];
const PAGE_COUNT = 9;
const NOTES_KEY = 'rempush.notes.v2';
const CURRENT_KEY = 'rempush.currentPage.v2';
const VAPID_KEY = 'rempush.vapidPublicKey';
const DB_NAME = 'RemPushNotifications';
const DB_VERSION = 1;

const pagesEl = document.getElementById('pages');
const viewportEl = document.getElementById('viewport');
const backdrop = document.getElementById('modalBackdrop');
const modal = document.getElementById('modal');
const toastEl = document.getElementById('toast');

let notes = loadNotes();
let current = clamp(Number(localStorage.getItem(CURRENT_KEY) || 0));
let saveTimer = 0;
let startX = 0;
let startY = 0;
let dragging = false;
let dragX = 0;
let suppressClick = false;

function clamp(index) { return ((index % PAGE_COUNT) + PAGE_COUNT) % PAGE_COUNT; }
function emptyNote() { return { title: '', body: '', createdAt: null }; }
function loadNotes() {
  try {
    const value = JSON.parse(localStorage.getItem(NOTES_KEY) || '[]');
    return Array.from({ length: PAGE_COUNT }, (_, i) => ({ ...emptyNote(), ...(value[i] || {}) }));
  } catch {
    return Array.from({ length: PAGE_COUNT }, emptyNote);
  }
}
function persist() {
  try { localStorage.setItem(NOTES_KEY, JSON.stringify(notes)); } catch { showToast('Could not save notes'); }
}
function schedulePersist() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(persist, 100);
}
function showToast(message) {
  toastEl.textContent = message;
  toastEl.classList.add('show');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => toastEl.classList.remove('show'), 1800);
}
function formatDate(value) {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(date);
}

function render() {
  pagesEl.innerHTML = '';
  const fragment = document.createDocumentFragment();
  notes.forEach((note, i) => {
    const page = document.createElement('section');
    page.className = 'page';
    page.style.backgroundColor = COLORS[i];
    page.dataset.index = String(i);

    const title = document.createElement('input');
    title.className = 'title';
    title.placeholder = 'Title';
    title.setAttribute('aria-label', 'Title');
    title.value = note.title;

    const body = document.createElement('textarea');
    body.className = 'body';
    body.placeholder = 'Your thoughts';
    body.setAttribute('aria-label', 'Your thoughts');
    body.value = note.body;

    const footer = document.createElement('div');
    footer.className = 'footer';
    const badge = document.createElement('span');
    badge.className = 'badge';
    badge.textContent = `Page ${i + 1} of ${PAGE_COUNT}`;
    const created = document.createElement('span');
    created.className = 'muted created';
    created.textContent = formatDate(note.createdAt);
    const empty = document.createElement('span');
    empty.className = 'muted empty';
    empty.textContent = note.title || note.body ? '' : 'is empty';
    footer.append(badge, created, empty);

    title.addEventListener('input', () => savePage(i, title.value, body.value, page));
    body.addEventListener('input', () => savePage(i, title.value, body.value, page));
    page.append(title, body, footer);
    fragment.appendChild(page);
  });
  pagesEl.appendChild(fragment);
  setPosition(false);
}

function savePage(index, title, body, page) {
  const note = notes[index];
  if (!note.createdAt && (title.trim() || body.trim())) note.createdAt = new Date().toISOString();
  notes[index] = { title, body, createdAt: note.createdAt };
  schedulePersist();
  page.querySelector('.created').textContent = formatDate(note.createdAt);
  page.querySelector('.empty').textContent = title.trim() || body.trim() ? '' : 'is empty';
}

function setPosition(animated = true, offset = 0) {
  pagesEl.style.transition = animated ? 'transform .25s cubic-bezier(.22,.61,.36,1)' : 'none';
  pagesEl.style.transform = `translate3d(calc(${-current * 100}% + ${offset}px),0,0)`;
  document.body.style.backgroundColor = COLORS[current];
  try { localStorage.setItem(CURRENT_KEY, String(current)); } catch {}
}
function go(delta) {
  if (dragging) return;
  current = clamp(current + delta);
  setPosition(true);
}

viewportEl.addEventListener('touchstart', event => {
  if (event.touches.length !== 1) return;
  const target = event.target;
  if (target.closest('input, textarea, button')) return;
  startX = event.touches[0].clientX;
  startY = event.touches[0].clientY;
  dragX = 0;
  dragging = true;
  pagesEl.style.transition = 'none';
}, { passive: true });

viewportEl.addEventListener('touchmove', event => {
  if (!dragging) return;
  const dx = event.touches[0].clientX - startX;
  const dy = event.touches[0].clientY - startY;
  if (Math.abs(dx) < Math.abs(dy) && Math.abs(dy) > 8) {
    dragging = false;
    setPosition(true);
    return;
  }
  if (Math.abs(dx) > Math.abs(dy)) event.preventDefault();
  dragX = dx;
  setPosition(false, dx);
}, { passive: false });

viewportEl.addEventListener('touchend', event => {
  if (!dragging) return;
  dragging = false;
  const dx = event.changedTouches[0].clientX - startX;
  const dy = event.changedTouches[0].clientY - startY;
  if (Math.abs(dx) > 55 && Math.abs(dx) > Math.abs(dy) * 1.2) {
    suppressClick = true;
    go(dx < 0 ? 1 : -1);
    setTimeout(() => { suppressClick = false; }, 300);
  } else {
    setPosition(true);
  }
});

window.addEventListener('keydown', event => {
  if (event.target.matches('input, textarea')) return;
  if (event.key === 'ArrowRight') { event.preventDefault(); go(1); }
  if (event.key === 'ArrowLeft') { event.preventDefault(); go(-1); }
});

window.addEventListener('beforeunload', () => {
  clearTimeout(saveTimer);
  persist();
});

document.getElementById('delete').onclick = () => {
  if (suppressClick) return;
  const note = notes[current];
  if (!note.title && !note.body) { showToast('Page is already empty'); return; }
  if (confirm(`Delete the note on page ${current + 1}?`)) {
    notes[current] = emptyNote();
    persist();
    render();
    showToast('Page deleted');
  }
};

document.getElementById('notify').onclick = async () => {
  const note = notes[current];
  if (!note.title.trim() && !note.body.trim()) { showToast('Page is empty'); return; }
  const ok = await requestNotificationPermission();
  if (!ok) return;
  const title = note.title.trim() || `RemPush Page ${current + 1}`;
  const body = note.body.trim() || 'RemPush reminder';
  try {
    await showNotification(title, body);
    await logNotification({ title, body, page: current + 1, createdAt: new Date().toISOString(), source: 'local' });
    showToast('Notification displayed');
  } catch (error) {
    showToast(`Notification failed: ${error.message || 'unknown error'}`);
  }
};

document.getElementById('share').onclick = async () => {
  const note = notes[current];
  const text = [note.title, note.body].filter(Boolean).join('\n\n');
  if (!text) { showToast('Page is empty'); return; }
  try {
    if (navigator.share) await navigator.share({ title: note.title || `RemPush Page ${current + 1}`, text });
    else if (navigator.clipboard) { await navigator.clipboard.writeText(text); showToast('Copied to clipboard'); }
  } catch (error) {
    if (error?.name !== 'AbortError') showToast('Share failed');
  }
};
document.getElementById('settings').onclick = openSettings;

async function requestNotificationPermission() {
  if (!('Notification' in window)) { showToast('Notifications are not supported'); return false; }
  if (Notification.permission === 'granted') return true;
  try {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') showToast('Notification permission denied');
    return permission === 'granted';
  } catch {
    showToast('Could not request notification permission');
    return false;
  }
}
async function showNotification(title, body) {
  if ('serviceWorker' in navigator) {
    const registration = await navigator.serviceWorker.ready;
    await registration.showNotification(title, { body, icon: 'app-icon.png', badge: 'app-icon.png', tag: `rempush-${Date.now()}` });
    return;
  }
  if ('Notification' in window) new Notification(title, { body });
  else throw new Error('Notifications are not supported');
}

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
async function logNotification(notification) {
  try {
    const db = await openDB();
    await new Promise((resolve, reject) => {
      const tx = db.transaction('notifications', 'readwrite');
      tx.objectStore('notifications').add(notification);
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    db.close();
  } catch {}
}
async function getNotifications() {
  try {
    const db = await openDB();
    const result = await new Promise((resolve, reject) => {
      const tx = db.transaction('notifications', 'readonly');
      const request = tx.objectStore('notifications').getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
    db.close();
    return result;
  } catch { return []; }
}
async function downloadLastMonth() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const end = new Date(now.getFullYear(), now.getMonth(), 1);
  const entries = (await getNotifications())
    .filter(n => { const d = new Date(n.createdAt); return !Number.isNaN(d.getTime()) && d >= start && d < end; })
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  const month = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' }).format(start);
  const lines = [`RemPush notification archive — ${month}`, '', ...entries.map(n => `${formatDate(n.createdAt)} | Page ${n.page ?? '-'} | ${n.title}\n${n.body}`)];
  if (!entries.length) lines.push('No notifications recorded.');
  const blob = new Blob([lines.join('\n\n')], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `RemPush-${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}.txt`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function openSettings() {
  modal.innerHTML = '<h2>Settings</h2>' +
    '<button class="action primary" id="archive">Download previous month notifications</button>' +
    '<button class="action" id="enable">Enable notifications</button>' +
    '<button class="action" id="subscribe">Configure Web Push subscription</button>' +
    '<button class="action" id="close">Close</button>';
  backdrop.classList.add('open');
  document.getElementById('archive').onclick = downloadLastMonth;
  document.getElementById('enable').onclick = async () => { await requestNotificationPermission(); };
  document.getElementById('subscribe').onclick = configurePush;
  document.getElementById('close').onclick = closeModal;
}
function closeModal() { backdrop.classList.remove('open'); }
backdrop.addEventListener('click', event => { if (event.target === backdrop) closeModal(); });
window.addEventListener('keydown', event => { if (event.key === 'Escape') closeModal(); });

async function configurePush() {
  if (!('PushManager' in window) || !('serviceWorker' in navigator)) { showToast('Web Push is not supported'); return; }
  if (!window.isSecureContext) { showToast('Web Push requires HTTPS'); return; }
  const currentKey = localStorage.getItem(VAPID_KEY) || '';
  modal.innerHTML = '<h2>Web Push</h2><p>Enter the server VAPID public key. The resulting subscription must be sent to your Web Push backend.</p><input id="vapid" placeholder="VAPID public key" value="">' +
    '<button class="action primary" id="savePush">Create subscription</button><button class="action" id="close">Cancel</button>';
  document.getElementById('vapid').value = currentKey;
  document.getElementById('close').onclick = closeModal;
  document.getElementById('savePush').onclick = async () => {
    const key = document.getElementById('vapid').value.trim();
    if (!key) { showToast('VAPID key required'); return; }
    try {
      const permission = await requestNotificationPermission();
      if (!permission) return;
      const registration = await navigator.serviceWorker.ready;
      const existing = await registration.pushManager.getSubscription();
      if (existing) await existing.unsubscribe();
      const subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(key) });
      localStorage.setItem(VAPID_KEY, key);
      const serialized = JSON.stringify(subscription.toJSON(), null, 2);
      if (navigator.clipboard) await navigator.clipboard.writeText(serialized);
      showToast('Subscription created');
      modal.innerHTML = `<h2>Web Push subscription</h2><p>The subscription JSON has been copied to the clipboard. Send it to your Web Push backend.</p><button class="action" id="close">Close</button>`;
      document.getElementById('close').onclick = closeModal;
    } catch (error) {
      showToast(`Push subscription failed: ${error.message || 'unknown error'}`);
    }
  };
}
function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(base64), c => c.charCodeAt(0));
}

async function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  try { await navigator.serviceWorker.register('./sw.js', { scope: './' }); }
  catch { showToast('Offline support could not be enabled'); }
}

render();
registerServiceWorker();
