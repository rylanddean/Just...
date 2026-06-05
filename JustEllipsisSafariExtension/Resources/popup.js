'use strict';

console.log('[Just…] popup loaded');

const btn      = document.getElementById('save-btn');
const titleEl  = document.getElementById('page-title');
const domainEl = document.getElementById('page-domain');

let currentURL   = '';
let currentTitle = '';

// ── Populate metadata on load ──────────────────────────────

browser.tabs.query({ active: true, currentWindow: true }).then(tabs => {
  const tab = tabs[0];
  if (!tab) return;

  currentURL   = tab.url   || '';
  currentTitle = tab.title || '';

  titleEl.textContent  = currentTitle || currentURL;

  try {
    const host = new URL(currentURL).hostname.replace(/^www\./, '');
    domainEl.textContent = host;
  } catch {
    domainEl.textContent = '';
  }

  if (!currentURL.startsWith('http')) {
    btn.disabled = true;
    btn.className = 'save-btn error';
    btn.textContent = 'Nothing to save.';
  }
});

// ── Save on click ──────────────────────────────────────────

btn.addEventListener('click', async () => {
  if (!currentURL || btn.disabled) return;

  btn.disabled = true;
  btn.className = 'save-btn loading';
  btn.textContent = 'Saving…';

  let response;
  try {
    console.log('[Just…] POSTing to local server for:', currentURL);
    const res = await fetch('http://localhost:21471/', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ url: currentURL, title: currentTitle })
    });
    response = await res.json();
    console.log('[Just…] server response:', JSON.stringify(response));
  } catch (err) {
    console.error('[Just…] server request failed:', err);
    btn.disabled = false;
    btn.className = 'save-btn error';
    btn.textContent = 'Couldn\'t connect to Just…';
    return;
  }

  const result = response?.result ?? 'error';

  if (result === 'success') {
    btn.className = 'save-btn success';
    btn.textContent = 'Kept. Your Brain grows.';
    setTimeout(() => window.close(), 1200);
  } else if (result === 'duplicate') {
    btn.className = 'save-btn duplicate';
    btn.textContent = 'Already in your queue.';
    setTimeout(() => window.close(), 1200);
  } else {
    btn.disabled = false;
    btn.className = 'save-btn error';
    btn.textContent = 'Couldn\'t save this link.';
  }
});
