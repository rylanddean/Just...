'use strict';

const btn       = document.getElementById('save-btn');
const titleEl   = document.getElementById('page-title');
const domainEl  = document.getElementById('page-domain');
const statusMsg = document.getElementById('status-msg');

let currentURL   = '';
let currentTitle = '';

// ── Populate metadata on load ──────────────────────────────

browser.tabs.query({ active: true, currentWindow: true }).then(tabs => {
  const tab = tabs[0];
  if (!tab) return;

  currentURL   = tab.url   || '';
  currentTitle = tab.title || '';

  titleEl.textContent = currentTitle || currentURL;

  try {
    const host = new URL(currentURL).hostname.replace(/^www\./, '');
    domainEl.textContent = host;
  } catch {
    domainEl.textContent = '';
  }

  // Disable save for non-http pages (new-tab, settings, etc.)
  if (!currentURL.startsWith('http')) {
    btn.disabled = true;
    btn.textContent = 'Nothing to save.';
    btn.classList.add('error');
  }
});

// ── Save on click ──────────────────────────────────────────

btn.addEventListener('click', async () => {
  if (!currentURL || btn.disabled) return;

  setLoading();

  let response;
  try {
    response = await browser.runtime.sendNativeMessage('application', {
      action: 'save',
      url:    currentURL,
      title:  currentTitle
    });
  } catch {
    setError();
    return;
  }

  const result = response?.result ?? 'error';

  if (result === 'success') {
    setSuccess();
    setTimeout(() => window.close(), 800);
  } else if (result === 'duplicate') {
    setDuplicate();
    setTimeout(() => window.close(), 800);
  } else {
    setError();
  }
});

// ── State helpers ──────────────────────────────────────────

function setLoading() {
  btn.disabled = true;
  btn.textContent = 'Add to Just…';
  btn.classList.add('loading');
  btn.classList.remove('success', 'duplicate', 'error');
  statusMsg.textContent = '';
  statusMsg.className = 'status-msg';
}

function setSuccess() {
  btn.disabled = true;
  btn.textContent = '✓';
  btn.classList.remove('loading', 'duplicate', 'error');
  btn.classList.add('success');
  statusMsg.textContent = '';
}

function setDuplicate() {
  btn.disabled = true;
  btn.textContent = '—';
  btn.classList.remove('loading', 'success', 'error');
  btn.classList.add('duplicate');
  statusMsg.textContent = 'Already in your queue.';
}

function setError() {
  btn.disabled = false;
  btn.textContent = 'Couldn\'t save this link.';
  btn.classList.remove('loading', 'success', 'duplicate');
  btn.classList.add('error');
  statusMsg.textContent = '';
}
