'use strict';

console.log('[Just…] background.js loaded');

// Log what APIs are available so we can see what Safari exposes
console.log('[Just…] browser.action:', typeof browser?.action);
console.log('[Just…] browser.commands:', typeof browser?.commands);
console.log('[Just…] browser.runtime:', typeof browser?.runtime);

// Log extension info
browser.runtime.getManifest && console.log('[Just…] manifest:', JSON.stringify(browser.runtime.getManifest()));

// ── Keyboard shortcut: ⌥⇧J ────────────────────────────────
// Silent save — no popup. Acknowledges via a brief badge on the toolbar icon.

browser.commands.onCommand.addListener(async command => {
  console.log('[Just…] command received:', command);
  if (command !== 'save-link') return;

  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  const tab  = tabs[0];
  if (!tab?.url?.startsWith('http')) return;

  console.log('[Just…] saving:', tab.url);

  let response;
  try {
    response = await browser.runtime.sendNativeMessage('application', {
      action: 'save',
      url:    tab.url,
      title:  tab.title || ''
    });
    console.log('[Just…] native response:', JSON.stringify(response));
  } catch (err) {
    console.error('[Just…] native message error:', err);
    flashBadge('!', '#E05A5A');
    return;
  }

  const result = response?.result ?? 'error';
  console.log('[Just…] result:', result);

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
