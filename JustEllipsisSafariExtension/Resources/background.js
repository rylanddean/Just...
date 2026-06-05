'use strict';

// ── Keyboard shortcut: ⌥⇧J ────────────────────────────────
// Silent save — no popup. Acknowledges via a brief badge on the toolbar icon.

browser.commands.onCommand.addListener(async command => {
  if (command !== 'save-link') return;

  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  const tab  = tabs[0];
  if (!tab?.url?.startsWith('http')) return;

  let response;
  try {
    response = await browser.runtime.sendNativeMessage('application', {
      action: 'save',
      url:    tab.url,
      title:  tab.title || ''
    });
  } catch {
    flashBadge('!', '#E05A5A');
    return;
  }

  const result = response?.result ?? 'error';

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
