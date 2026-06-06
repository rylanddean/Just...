'use strict';

// ── Native-messaging relay ─────────────────────────────────
//
// browser.runtime.sendMessage() from the popup reaches this background page
// first. We forward to SafariWebExtensionHandler via safari.extension
// .dispatchMessage() and relay the native response back to the popup via
// the stored sendResponse callback.
//
// safari.self.addEventListener("message") is how Safari delivers the
// completeRequest() reply from the Swift handler back to the JS page
// that called dispatchMessage().

let pendingSendResponse = null;

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    const { action, url = '', title = '' } = message ?? {};

    if (action === 'save') {
        pendingSendResponse = sendResponse;
        safari.extension.dispatchMessage('save', { url, title });
        return true; // keep channel open — response is async
    }

    if (action === 'check') {
        pendingSendResponse = sendResponse;
        safari.extension.dispatchMessage('check', { url });
        return true;
    }
});

// Safari delivers SafariWebExtensionHandler's completeRequest() reply here.
safari.self.addEventListener('message', event => {
    const result = event.message?.result ?? 'error';
    if (pendingSendResponse) {
        pendingSendResponse({ result });
        pendingSendResponse = null;
    }
});

// ── Keyboard shortcut: ⌥⇧J ────────────────────────────────

browser.commands.onCommand.addListener(async command => {
    if (command !== 'save-link') return;

    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab  = tabs[0];
    if (!tab?.url?.startsWith('http')) return;

    // Use a one-shot Promise so we can await the native response.
    const result = await new Promise(resolve => {
        pendingSendResponse = ({ result }) => resolve(result);
        safari.extension.dispatchMessage('save', {
            url:   tab.url,
            title: tab.title ?? ''
        });
        // Timeout after 15 s — CloudKit can be slow on first launch.
        setTimeout(() => resolve('error'), 15_000);
    });

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
