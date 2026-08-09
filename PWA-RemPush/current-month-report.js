const NOTIFICATION_HISTORY_KEY = 'rempush.notificationHistory.v1';
const monthFormatter = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' });
const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });

function getCurrentMonthKey() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

function getMonthKeyFromDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

function loadCurrentMonthNotifications() {
  try {
    const value = JSON.parse(localStorage.getItem(NOTIFICATION_HISTORY_KEY) || '[]');
    const entries = Array.isArray(value)
      ? value
      : value && Array.isArray(value.entries) ? value.entries : [];
    const currentMonth = getCurrentMonthKey();

    return entries
      .filter(entry => entry && typeof entry === 'object' && typeof entry.createdAt === 'string')
      .filter(entry => (entry.month || getMonthKeyFromDate(entry.createdAt)) === currentMonth);
  } catch {
    return [];
  }
}

function createCurrentMonthReport(entries) {
  const [year, month] = getCurrentMonthKey().split('-').map(Number);
  const start = new Date(year, month - 1, 1);
  const lines = [
    `RemPush notification archive — ${monthFormatter.format(start)}`,
    `Notifications: ${entries.length}`,
    '',
    ...entries
      .slice()
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
      .map(entry => `${dateFormatter.format(new Date(entry.createdAt))} | Page ${entry.page ?? '-'} | ${entry.title || '-'}\n${entry.body || ''}`)
  ];

  if (!entries.length) lines.push('No notifications recorded.');
  return new Blob([lines.join('\n\n')], { type: 'text/plain;charset=utf-8' });
}

function downloadCurrentMonthReport() {
  const entries = loadCurrentMonthNotifications();
  const blob = createCurrentMonthReport(entries);
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `RemPush-${getCurrentMonthKey()}.txt`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const settingsButton = document.getElementById('settings');
const settingsBackdrop = document.getElementById('modalBackdrop');
const settingsModal = document.getElementById('modal');

if (settingsButton && settingsBackdrop && settingsModal) {
  settingsButton.onclick = () => {
    const count = loadCurrentMonthNotifications().length;
    const month = monthFormatter.format(new Date());

    settingsModal.innerHTML = `
      <h2>Settings</h2>
      <button class="action primary" id="archive">Download ${month} notifications (${count})</button>
      <button class="action" id="enable">Enable notifications</button>
      <button class="action" id="close">Close</button>
    `;
    settingsBackdrop.classList.add('open');

    document.getElementById('archive').onclick = downloadCurrentMonthReport;
    document.getElementById('enable').onclick = async () => {
      if ('Notification' in window && Notification.permission !== 'granted') {
        await Notification.requestPermission();
      }
    };
    document.getElementById('close').onclick = () => settingsBackdrop.classList.remove('open');
  };
}
