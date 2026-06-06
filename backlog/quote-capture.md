# Quote Capture

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

While reading, the user long-presses to select a passage. A compact bottom sheet appears with two actions: save the quote to the Brain, or send it via Messages. Saved quotes live in a new QUOTES section in the Brain, distinct from reflections.

---

## Why

Reading produces two kinds of thoughts: the ones that stay after you close the article (reflections) and the ones that live inside the article itself (quotes). Right now there is no way to keep the second kind. A sentence worth keeping either gets copy-pasted out of the app or disappears.

Quotes also make the Brain denser and more personal — a reflection says "this is what I thought," a quote says "this is what stopped me mid-sentence." The two together are more honest about what reading actually produces.

The Messages path is not social. It is the same impulse as reading a sentence aloud to someone in the room. Private and immediate.

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
- **Send via Messages** — `muted` text, `.body` weight. Opens `MFMessageComposeViewController` pre-filled with the quote text and article URL. Dismisses the sheet after compose closes.
- Tapping outside the sheet or clearing the selection dismisses it without action. No feedback.

If `MFMessageComposeViewController.canSendText()` returns false (iPad without a SIM, simulator), the Send button is hidden. The sheet still appears with "Keep this" only.

### Confirmation

After "Keep this", a 1-second toast appears at the bottom of the reader:

> Kept. Your Brain grows.

Reuses the same copy and animation pattern as the reflect-save confirmation.

---

### QUOTES in the Brain

A new QUOTES section appears in `BrainView`, below INSIGHTS (if present), ordered most recent first. Hidden entirely when the user has no saved quotes.

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

Tapping opens a `QuoteEntryDetail` sheet: full quote text, article title (tappable — opens URL in `SafariView`), and a delete option in the menu. No editing — a quote is a captured fragment.

Swipe-to-delete matches the existing `BrainEntryRow` pattern.

---

## Technical Approach

### New Model — `QuoteEntry`

```swift
@Model
final class QuoteEntry {
    var id: UUID = UUID()
    var text: String = ""
    var url: String = ""
    var title: String = ""
    var domain: String = ""
    var savedAt: Date = Date()

    init(text: String, url: String, title: String, domain: String) { ... }
}
```

Lightweight SwiftData migration — no changes to existing models.

### JS Injection in `ReaderWebView`

New `WKUserScript` alongside `tapLinkJS`:

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

Register `quoteSelected` as a message handler in `WKWebViewConfiguration`. The coordinator receives the selected text — empty string clears the pending selection.

### `ReaderWebView` Changes

Add one callback:
```swift
var onQuoteSelected: (String) -> Void = { _ in }
```

Wire through `makeCoordinator` and `updateUIView`. Handle `quoteSelected` in `userContentController(_:didReceive:)` alongside `tapLink`.

### `ReaderView` Changes

```swift
@State private var pendingQuote: String?
```

Set from `onQuoteSelected` — non-empty string triggers the sheet, empty string clears `pendingQuote`.

`.sheet(item:)` driven by a `Binding<String?>` wrapping `pendingQuote` presents `QuoteActionSheet`.

### `QuoteActionSheet`

A new non-full-screen view with the preview text, "Keep this", and conditional "Send via Messages". On "Keep this": inserts a `QuoteEntry`. On send: presents `MFMessageComposeViewController` via `UIViewControllerRepresentable`.

Message body:
```
"\(quoteText)"

\(articleTitle)
\(articleURL)
```

### `BrainView` Changes

```swift
@Query(sort: \QuoteEntry.savedAt, order: .reverse) private var quotes: [QuoteEntry]
```

New QUOTES section below INSIGHTS, guarded by `!quotes.isEmpty`. Renders `BrainQuoteRow` per entry, swipe-to-delete matching the existing pattern.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Reader disappears — no chrome | ✅ — Sheet appears only on deliberate selection |
| Not social | ✅ — Messages is private, one-to-one |
| Celebrate accumulation | ✅ — QUOTES section grows the Brain |
| Calm confirmation | ✅ — Reuses "Kept. Your Brain grows." |
| Amber for active only | ✅ — "Keep this" uses `accent`; Send is `muted` |
| No hardcoded hex | ✅ — All colours via `appTheme` tokens |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Save button | "Keep this" |
| SMS button | "Send via Messages" |
| Save confirmation | "Kept. Your Brain grows." |
| Brain section header | "QUOTES" |
| Quote detail menu | "Delete" |

---

## Acceptance Criteria

- [ ] Long-pressing text activates iOS selection handles; bottom sheet appears within 250ms of selection settling
- [ ] Sheet shows a 2-line truncated preview of the selected text
- [ ] "Keep this" saves a `QuoteEntry` to SwiftData and dismisses the sheet
- [ ] "Kept. Your Brain grows." toast appears, dismisses after 1 second
- [ ] "Send via Messages" opens `MFMessageComposeViewController` pre-filled with quote text, article title, and URL
- [ ] "Send via Messages" button is hidden when `canSendText()` returns false
- [ ] Tapping outside the sheet or clearing the selection dismisses without saving
- [ ] `QuoteEntry` is a new SwiftData model; existing `BrainEntry` model is unchanged
- [ ] QUOTES section appears in `BrainView` only when at least one `QuoteEntry` exists
- [ ] Each quote card shows the full quote text (Playfair italic), domain, relative date, and article title
- [ ] Tapping a card opens `QuoteEntryDetail` sheet with full quote and tappable article title
- [ ] Swipe-to-delete removes the `QuoteEntry` from SwiftData
- [ ] Zero-length selections do not trigger the sheet
- [ ] All colours via `appTheme` tokens — no hardcoded hex
