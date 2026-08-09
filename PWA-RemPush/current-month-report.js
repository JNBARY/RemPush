const NOTIFICATION_HISTORY_KEY = 'rempush.notificationHistory.v1';
const monthFormatter = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' });
const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });

function currentMonthKey() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

function currentMonthStart() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), 1);
}

function loadCurrentMonthNotifications() {
  try {
    const value = JSON.parse(localStorage.getItem(NOTIFICATION_HISTORY_KEY) || '[]');
    const entries = Array.isArray(value)
      ? value
      : value && Array.isArray(value.entries) ? value.entries : [];
    const key = currentMonthKey();
    return entries
      .filter(entry => entry && typeof entry === 'object' && typeof entry.createdAt === 'string')
      .filter(entry => entry.month === key || (!entry.month && currentMonthKey(new Date(entry.createdAt)) === key));
  } catch {
    return [];
  }
}

function createCurrentMonthReport(entries) {
  const start = currentMonthStart();
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
  link.download = `RemPush-${currentMonthKey()}.txt`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const settingsButton = document.getElementById('settings');
if (settingsButton) {
  settingsButton.addEventListener('click', () => {
    setTimeout(() => {
      const archiveButton = document.getElementById('archive');
      if (!archiveButton) return;
      const count = loadCurrentMonthNotifications().length;
      archiveButton.textContent = `Download current month notifications (${count})`;
      archiveButton.onclick = downloadCurrentMonthReport;
    }, 0);
  });
}
