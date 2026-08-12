const NOTES_PERSISTENCE_KEY = 'rempush.currentNotes.v1';
const NOTES_PAGE_COUNT = 9;

function readPersistedNotes() {
  try {
    const value = JSON.parse(localStorage.getItem(NOTES_PERSISTENCE_KEY) || 'null');
    if (!Array.isArray(value)) return null;
    return Array.from({ length: NOTES_PAGE_COUNT }, (_, index) => {
      const note = value[index];
      return {
        title: typeof note?.title === 'string' ? note.title : '',
        body: typeof note?.body === 'string' ? note.body : ''
      };
    });
  } catch {
    return null;
  }
}

function snapshotNotes() {
  const notes = Array.from({ length: NOTES_PAGE_COUNT }, () => ({ title: '', body: '' }));

  document.querySelectorAll('.page').forEach(page => {
    const index = Number(page.dataset.index);
    if (!Number.isInteger(index) || index < 0 || index >= NOTES_PAGE_COUNT) return;
    const title = page.querySelector('.title');
    const body = page.querySelector('.body');
    notes[index] = {
      title: title?.value || '',
      body: body?.value || ''
    };
  });

  return notes;
}

function persistNotes() {
  try {
    localStorage.setItem(NOTES_PERSISTENCE_KEY, JSON.stringify(snapshotNotes()));
  } catch {
    // The main application reports storage failures through its own persistence path.
  }
}

function restoreNotes() {
  const stored = readPersistedNotes();
  const pages = document.querySelectorAll('.page');

  if (!stored || pages.length === 0) {
    persistNotes();
    return;
  }

  pages.forEach(page => {
    const index = Number(page.dataset.index);
    if (!Number.isInteger(index) || index < 0 || index >= NOTES_PAGE_COUNT) return;

    const title = page.querySelector('.title');
    const body = page.querySelector('.body');
    if (!title || !body) return;

    title.value = stored[index].title;
    body.value = stored[index].body;
  });

  // Synchronize the restored values with the application's normal note store.
  document.querySelectorAll('.title, .body').forEach(field => {
    field.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

document.addEventListener('input', event => {
  if (event.target.matches('.title, .body')) persistNotes();
}, true);

document.getElementById('delete')?.addEventListener('click', () => {
  // The application's delete handler re-renders the pages synchronously.
  setTimeout(persistNotes, 0);
});

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') persistNotes();
});
window.addEventListener('pagehide', persistNotes);
window.addEventListener('beforeunload', persistNotes);

restoreNotes();
