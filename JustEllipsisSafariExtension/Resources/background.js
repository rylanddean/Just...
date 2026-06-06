'use strict';

console.log('[Just…] background.js loaded');

// ── Keyboard shortcut: ⌥⇧J ────────────────────────────────
// Silent save — no popup. Acknowledges via a brief badge on the toolbar icon.

browser.commands.onCommand.addListener(async command => {
  console.log('[Just…] command received:', command);
  if (command !== 'save-link') return;

  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  const tab  = tabs[0];
  if (!tab?.url?.startsWith('http')) return;

  console.log('[Just…] saving via native handler:', tab.url);

  let result;
  try {
    const response = await browser.runtime.sendMessage({
      action: 'save',
      url:    tab.url,
      title:  tab.title || ''
    });
    console.log('[Just…] native response:', JSON.stringify(response));
    result = response?.result ?? 'error';
  } catch (err) {
    console.error('[Just…] native message failed:', err);
    flashBadge('!', '#E05A5A');
    return;
  }

  if (result === 'success') {
    flashBadge('✓', '#E8A83E');
  } else if (result === 'duplicate') {
    flashBadge('—', '#5A5248');
  } else {
    flashBadge('!', '#E05A5A');
  }
});

function flashBadge(text, color) {
  browser.action.setBadgeText({ text });
  browser.action.setBadgeBackgroundColor({ color });
  setTimeout(() => browser.action.setBadgeText({ text: '' }), 1500);
}
