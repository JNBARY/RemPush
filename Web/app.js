const COLORS = ['#ff0000','#ff9500','#ffd60a','#34c759','#63e6be','#00d9ff','#007aff','#af52de','#ff2d55'];
const PAGE_COUNT = 9;
const NOTES_KEY = 'rempush.notes.v1';
const CURRENT_KEY = 'rempush.currentPage.v1';
const VAPID_KEY = 'rempush.vapidPublicKey';

const pagesEl = document.getElementById('pages');
const backdrop = document.getElementById('modalBackdrop');
const modal = document.getElementById('modal');
const toastEl = document.getElementById('toast');
let notes = loadNotes();
let current = clamp(Number(localStorage.getItem(CURRENT_KEY) || 0));
let saveTimer;
let startX = 0;
let startY = 0;
let dragging = false;

function clamp(index) { return ((index % PAGE_COUNT) + PAGE_COUNT) % PAGE_COUNT; }
function emptyNote() { return { title: '', body: '', createdAt: null }; }
function loadNotes() {
  try {
    const value = JSON.parse(localStorage.getItem(NOTES_KEY) || '[]');
    return Array.from({ length: PAGE_COUNT }, (_, i) => ({ ...emptyNote(), ...(value[i] || {}) }));
  } catch { return Array.from({ length: PAGE_COUNT }, emptyNote); }
}
function persist() { localStorage.setItem(NOTES_KEY, JSON.stringify(notes)); }
function showToast(message) {
  toastEl.textContent = message;
  toastEl.classList.add('show');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => toastEl.classList.remove('show'), 1800);
}
function formatDate(value) {
  if (!value) return '';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
}
function render() {
  pagesEl.innerHTML = '';
  notes.forEach((note, i) => {
    const page = document.createElement('section');
    page.className = 'page';
    page.style.background = COLORS[i];
    page.dataset.index = i;
    page.innerHTML = `<input class="title" placeholder="Title" aria-label="Title"><textarea class="body" placeholder="Your thoughts" aria-label="Your thoughts"></textarea><div class="footer"><span class="badge">Page ${i + 1} of ${PAGE_COUNT}</span><span class="muted created"></span><span class="muted empty"></span></div>`;
    const title = page.querySelector('.title');
    const body = page.querySelector('.body');
    title.value = note.title;
    body.value = note.body;
    page.querySelector('.created').textContent = formatDate(note.createdAt);
    page.querySelector('.empty').textContent = note.title || note.body ? '' : 'is empty';
    title.addEventListener('input', () => savePage(i, title.value, body.value, page));
    body.addEventListener('input', () => savePage(i, title.value, body.value, page));
    pagesEl.appendChild(page);
  });
  setPosition(false);
}
function savePage(index, title, body, page) {
  const note = notes[index];
  if (!note.createdAt && (title.trim() || body.trim())) note.createdAt = new Date().toISOString();
  notes[index] = { title, body, createdAt: note.createdAt };
  clearTimeout(saveTimer);
  saveTimer = setTimeout(persist, 120);
  page.querySelector('.created').textContent = formatDate(note.createdAt);
  page.querySelector('.empty').textContent = title || body ? '' : 'is empty';
}
function setPosition(animated = true) {
  pagesEl.style.transition = animated ? 'transform .25s ease' : 'none';
  pagesEl.style.transform = `translate3d(${-current * 100}%,0,0)`;
  document.body.style.backgroundColor = COLORS[current];
  localStorage.setItem(CURRENT_KEY, current);
}
function go(delta) { current = clamp(current + delta); setPosition(true); }

pagesEl.addEventListener('touchstart', event => {
  if (event.touches.length !== 1) return;
  startX = event.touches[0].clientX; startY = event.touches[0].clientY; dragging = true;
  pagesEl.style.transition = 'none';
}, { passive: true });
pagesEl.addEventListener('touchmove', event => {
  if (!dragging) return;
  const dx = event.touches[0].clientX - startX;
  const dy = event.touches[0].clientY - startY;
  if (Math.abs(dx) > Math.abs(dy)) event.preventDefault();
  pagesEl.style.transform = `translate3d(calc(${-current * 100}% + ${dx}px),0,0)`;
}, { passive: false });
pagesEl.addEventListener('touchend', event => {
  if (!dragging) return;
  dragging = false;
  const dx = event.changedTouches[0].clientX - startX;
  const dy = event.changedTouches[0].clientY - startY;
  if (Math.abs(dx) > 55 && Math.abs(dx) > Math.abs(dy) * 1.2) go(dx < 0 ? 1 : -1);
  else setPosition(true);
});

window.addEventListener('keydown', event => {
  if (event.key === 'ArrowRight') go(1);
  if (event.key === 'ArrowLeft') go(-1);
});

document.getElementById('delete').onclick = () => {
  const note = notes[current];
  if (!note.title && !note.body) return;
  if (confirm(`Delete the note on page ${current + 1}?`)) {
    notes[current] = emptyNote(); persist(); render(); showToast('Page deleted');
  }
};
document.getElementById('notify').onclick = async () => {
  const note = notes[current];
  if (!note.title && !note.body) { showToast('Page is empty'); return; }
  const ok = await requestNotificationPermission();
  if (!ok) return;
  const title = note.title.trim() || `RemPush Page ${current + 1}`;
  const body = note.body.trim();
  await showNotification(title, body);
  await logNotification({ title, body, page: current + 1, createdAt: new Date().toISOString(), source: 'local' });
  showToast('Notification displayed');
};
document.getElementById('share').onclick = async () => {
  const note = notes[current];
  const text = [note.title, note.body].filter(Boolean).join('\n\n');
  if (navigator.share) await navigator.share({ title: note.title || `RemPush Page ${current + 1}`, text }).catch(() => {});
  else await navigator.clipboard?.writeText(text), showToast('Copied to clipboard');
};
document.getElementById('settings').onclick = openSettings;

async function requestNotificationPermission() {
  if (!('Notification' in window)) { showToast('Notifications are not supported'); return false; }
  if (Notification.permission === 'granted') return true;
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') showToast('Notification permission denied');
  return permission === 'granted';
}
async function showNotification(title, body) {
  const registration = await navigator.serviceWorker?.ready;
  if (registration) await registration.showNotification(title, { body, icon: 'icon.svg', badge: 'icon.svg', tag: `rempush-${Date.now()}` });
  else new Notification(title, { body });
}

const DB_NAME = 'RemPushNotifications';
function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => request.result.createObjectStore('notifications', { keyPath: 'id', autoIncrement: true });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
async function logNotification(notification) {
  try { const db = await openDB(); const tx = db.transaction('notifications', 'readwrite'); tx.objectStore('notifications').add(notification); } catch {}
}
async function getNotifications() {
  try {
    const db = await openDB();
    return await new Promise((resolve, reject) => {
      const tx = db.transaction('notifications', 'readonly');
      const request = tx.objectStore('notifications').getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  } catch { return []; }
}
async function downloadLastMonth() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const end = new Date(now.getFullYear(), now.getMonth(), 1);
  const entries = (await getNotifications()).filter(n => new Date(n.createdAt) >= start && new Date(n.createdAt) < end).sort((a,b) => a.createdAt.localeCompare(b.createdAt));
  const month = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' }).format(start);
  const lines = [`RemPush notification archive — ${month}`, '', ...entries.map(n => `${formatDate(n.createdAt)} | Page ${n.page} | ${n.title}\n${n.body}`)];
  if (!entries.length) lines.push('No notifications recorded.');
  const blob = new Blob([lines.join('\n\n')], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a'); a.href = url; a.download = `RemPush-${start.getFullYear()}-${String(start.getMonth()+1).padStart(2,'0')}.txt`; a.click();
  URL.revokeObjectURL(url);
}

function openSettings() {
  modal.innerHTML = `<h2>Settings</h2><button class="action primary" id="archive">Download previous month notifications</button><button class="action" id="enable">Enable notifications</button><button class="action" id="subscribe">Configure Web Push subscription</button><button class="action" id="close">Close</button>`;
  backdrop.classList.add('open');
  document.getElementById('archive').onclick = downloadLastMonth;
  document.getElementById('enable').onclick = async () => { await requestNotificationPermission(); };
  document.getElementById('subscribe').onclick = configurePush;
  document.getElementById('close').onclick = closeModal;
}
function closeModal() { backdrop.classList.remove('open'); }
backdrop.addEventListener('click', event => { if (event.target === backdrop) closeModal(); });

async function configurePush() {
  if (!('PushManager' in window) || !('serviceWorker' in navigator)) { showToast('Web Push is not supported'); return; }
  const currentKey = localStorage.getItem(VAPID_KEY) || '';
  modal.innerHTML = `<h2>Web Push</h2><p>Enter the server's VAPID public key to create a push subscription. The PWA can then receive standard Web Push messages through your backend.</p><input id="vapid" placeholder="VAPID public key" value="${currentKey}"><button class="action primary" id="savePush">Create subscription</button><button class="action" id="close">Cancel</button>`;
  document.getElementById('close').onclick = closeModal;
  document.getElementById('savePush').onclick = async () => {
    const key = document.getElementById('vapid').value.trim();
    if (!key) { showToast('VAPID key required'); return; }
    localStorage.setItem(VAPID_KEY, key);
    try {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(key) });
      await navigator.clipboard?.writeText(JSON.stringify(subscription.toJSON()));
      showToast('Subscription created and copied');
      closeModal();
    } catch (error) { showToast(`Push subscription failed: ${error.message}`); }
  };
}
function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(base64), c => c.charCodeAt(0));
}

if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
render();
