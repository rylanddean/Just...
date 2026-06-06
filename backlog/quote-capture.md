# Quote Capture

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

While reading, the user long-presses to select a passage. A compact sheet appears with two actions: save the quote to the Brain, or send it via Messages. Saved quotes live in a new QUOTES section in the Brain, distinct from reflections.

---

## Why

Reading produces two kinds of thoughts: the ones that stay after you close the article (reflections) and the ones that live inside the article itself (quotes). Right now there is no way to keep the second kind. A sentence worth keeping either gets copy-pasted out of the app or disappears.

Quotes also make the Brain denser and more personal — a reflection says "this is what I thought," a quote says "this is what stopped me mid-sentence." The two together are more honest about what reading actually produces.

The SMS path is not social. It is the same impulse as reading a sentence aloud to someone in the room. It is private and immediate — closer to conversation than publishing.

---

## Experience

### Text Selection

The user long-presses on any word in the reader. iOS activates its native selection handles. As the selection settles (250ms after the last `selectionchange` event), a compact bottom sheet slides up — `presentationDetents([.height(96)])` — containing two actions and a truncated preview of the selected text.

```
┌──────────────────────────────────────────────┐
│  "…the sentence the user selected, truncated  │
│   to two lines if needed…"                    │
│                                               │
│  [ Keep this ]          [ Send via Messages ] │
└──────────────────────────────────────────────┘
```

- **Keep this** — amber, `.headline` weight. Saves a `QuoteEntry` to SwiftData and dismisses the sheet. A brief amber flash on the reader background confirms the save.
- **Send via Messages** — muted text, `.body` weight. Opens `MFMessageComposeViewController` pre-filled with the quote text and article URL. Dismisses the sheet after the compose screen closes.
- Tapping outside the sheet or clearing the selection dismisses it without action. No "cancelled" feedback.

If `MFMessageComposeViewController.canSendText()` returns false (e.g., iPad without a SIM, simulator), the "Send via Messages" button is hidden. The sheet still appears with only "Keep this."

### Confirmation

After "Keep this" is tapped, the sheet dismisses and a 1-second toast appears at the bottom of the reader:

> Kept. Your Brain grows.

Reuses the same copy and animation pattern as the reflect-save confirmation. No new copy required.

### QUOTES in the Brain

A new QUOTES section appears in `BrainView` between INSIGHTS and REVISIT (when it exists), ordered with the most recent quote first. The section is hidden entirely when the user has no saved quotes.

Each quote card:

```
┌────────────────────────────────────────────────┐
│ "The exact text the user selected from the     │
│  article, in Playfair Display italic. Up to    │
│  four lines, then truncated."                  │
│                                                │
│  nytimes.com · 3 days ago                      │
│  Article title, DM Mono 12pt, muted, 1 line    │
└────────────────────────────────────────────────┘
```

Tap opens a `QuoteEntryDetail` sheet showing the full quote, the article title (tappable — opens the URL in `SafariView`), and a delete option in the menu. No editing — a quote is a captured fragment, not a draft.

Swipe-to-delete on the row (same trailing swipe pattern as `BrainEntryRow`).

---

## Technical Approach

### New Model

```swift
@Model
final class QuoteEntry {
    var id: UUID = UUID()
    var text: String = ""
    var url: String = ""
    var title: String = ""
    var domain: String = ""
    var savedAt: Date = Date()

    init(text: String, url: String, title: String, domain: String) {
        self.text = text
        self.url = url
        self.title = title
        self.domain = domain
    }
}
```

SwiftData lightweight migration — no changes to existing models.

### JS Injection in `ReaderWebView`

Add a new `WKUserScript` alongside `tapLinkJS`:

```javascript
(function(){
  var debounce;
  document.addEventListener('selectionchange', function(){
    clearTimeout(debounce);
    var sel = window.getSelection();
    var text = sel ? sel.toString().trim() : '';
    if (!text) {
      window.webkit.messageHandlers.quoteSelected.postMessage('');
      return;
    }
    debounce = setTimeout(function(){
      window.webkit.messageHandlers.quoteSelected.postMessage(text);
    }, 250);
  });
})();
```

Register `quoteSelected` as a message handler name in `WKWebViewConfiguration`. The coordinator receives the selected text — empty string means selection was cleared.

### `ReaderWebView` Changes

Add one new callback:

```swift
var onQuoteSelected: (String) -> Void = { _ in }
```

Wire through `makeCoordinator` and `updateUIView`. Handle `quoteSelected` in `userContentController(_:didReceive:)` alongside `tapLink`.

### `ReaderView` Changes

Add to state:

```swift
@State private var pendingQuote: String?
```

Set `pendingQuote` from the `onQuoteSelected` callback — non-empty string opens the sheet, empty string clears `pendingQuote`.

Add a `.sheet(item:)` driven by a `Binding<String?>` wrapping `pendingQuote` that presents `QuoteActionSheet`.

### `QuoteActionSheet`

A new view (not a full screen) with the preview text, "Keep this" button, and conditional "Send via Messages" button. On "Keep this", inserts a `QuoteEntry` into the model context. On "Send via Messages", presents `MFMessageComposeViewController` via a `UIViewControllerRepresentable` wrapper.

Message body pre-fill:

```
"\(quoteText)"

\(articleTitle)
\(articleURL)
```

### `BrainView` Changes

Add a `@Query` for `QuoteEntry`:

```swift
@Query(sort: \QuoteEntry.savedAt, order: .reverse) private var quotes: [QuoteEntry]
```

Add a new QUOTES section block below INSIGHTS, guarded by `!quotes.isEmpty`. Renders `BrainQuoteRow` for each entry, with swipe-to-delete matching the existing pattern.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Reader disappears — no chrome | ✅ Sheet only appears on deliberate selection; no persistent UI added to reader |
| Not social | ✅ SMS is private, one-to-one — not a share button on a feed or public post |
| Celebrate accumulation | ✅ QUOTES section grows the Brain; rank system could count quotes toward entry total (see AC) |
| Calm confirmation | ✅ Reuses "Kept. Your Brain grows." — no new celebration copy |
| Amber for active only | ✅ "Keep this" button uses `accent`; "Send via Messages" is muted |
| No hardcoded hex | ✅ All colours via `appTheme` tokens |
| "Send" not "Share" | ✅ No "share" language anywhere in this flow |
| Handles missing capability gracefully | ✅ SMS button hidden when `canSendText()` is false |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Save button | "Keep this" |
| SMS button | "Send via Messages" |
| Save confirmation toast | "Kept. Your Brain grows." |
| Brain section header | "QUOTES" |
| Quote detail menu | "Delete" |
| Brain empty quotes state | (section hidden — no empty state needed) |

---

## Acceptance Criteria

- [ ] Long-pressing text in the reader activates iOS selection handles; a bottom sheet appears within 250ms of the selection settling
- [ ] Sheet shows a 2-line truncated preview of the selected text
- [ ] "Keep this" saves a `QuoteEntry` to SwiftData and dismisses the sheet
- [ ] "Kept. Your Brain grows." toast appears after saving, dismisses after 1 second
- [ ] "Send via Messages" opens `MFMessageComposeViewController` pre-filled with quote text, article title, and URL
- [ ] "Send via Messages" button is hidden when `MFMessageComposeViewController.canSendText()` returns false
- [ ] Tapping outside the sheet or clearing the selection dismisses without saving
- [ ] QUOTES section appears in `BrainView` only when at least one `QuoteEntry` exists
- [ ] QUOTES section is positioned after INSIGHTS and before REVISIT
- [ ] Each quote card shows the full quote text (Playfair Display italic), domain, relative date, and article title
- [ ] Tapping a quote card opens `QuoteEntryDetail` sheet
- [ ] `QuoteEntryDetail` shows the full quote text and a tappable article title (opens `SafariView`)
- [ ] Swipe-to-delete removes the quote from SwiftData
- [ ] `QuoteEntry` is a new SwiftData model; existing `BrainEntry` model is unchanged
- [ ] No hardcoded hex values — all colours via `appTheme` tokens
- [ ] Selection sheet does not appear for zero-length selections
