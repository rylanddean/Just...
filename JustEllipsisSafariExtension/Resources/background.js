'use strict';

// Loud load marker so we can confirm the background script even runs.
console.log('[Just…] background.js loaded');
console.log('[Just…] typeof safari:', typeof safari);
console.log('[Just…] typeof browser.runtime.sendNativeMessage:', typeof browser?.runtime?.sendNativeMessage);

// ── Keyboard shortcut: ⌥⇧J ────────────────────────────────
// browser.runtime.sendNativeMessage() is delivered directly to the native
// SafariWebExtensionHandler; its completeRequest() reply comes back as the
// resolved value here. This API is ONLY exposed when the "nativeMessaging"
// permission is declared in manifest.json — without it the function is
// undefined. browser.runtime.sendMessage() does NOT reach native in Safari.

browser.commands.onCommand.addListener(async command => {
    console.log('[Just…] command received:', command);
    if (command !== 'save-link') return;

    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab  = tabs[0];
    if (!tab?.url?.startsWith('http')) return;

    let result = 'error';
    try {
        const response = await browser.runtime.sendNativeMessage({
            action: 'save',
            url:    tab.url,
            title:  tab.title ?? ''
        });
        console.log('[Just…] native response:', JSON.stringify(response));
        result = response?.result ?? 'error';
    } catch (err) {
        console.error('[Just…] sendMessage failed:', err);
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
    setTimeout(() => browser.action.setBadgeText({ text: '' }), 1_500);
}
