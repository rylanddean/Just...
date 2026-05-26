# Digest Summary

**Tier:** Free  
**Effort:** XS  
**Status:** Backlog — Polish

Digest cards show a title and a feed name. That is rarely enough to decide whether to queue something. Add the article summary below the title — the same text `FeedDetailView` already displays — so the decision to queue or skip can be made without opening anything.

---

## Why

The Digest exists to surface articles worth reading. Right now a user sees a headline and a source and has to guess. For unfamiliar writers or longer-form pieces, the title alone does not answer the only question that matters: *is this worth my time today?*

The data is already there. `RSSArticle.summary` holds a two-sentence AI précis on iOS 26+. `RSSArticle.feedDescription` holds the RSS-supplied description on every device. `FeedDetailView` already renders exactly this, with the same fallback logic. The Digest simply does not use it.

This is a one-component change. The risk is low; the reading experience is meaningfully better.

---

## Experience

### Card before

```
┌─────────────────────────────────────────────┐
│ ○  The Attention Merchants           [ + ]  │
│    Aeon · 3h ago                            │
└─────────────────────────────────────────────┘
```

### Card after

```
┌─────────────────────────────────────────────┐
│ ○  The Attention Merchants           [ + ]  │
│    How advertisers learned to buy the       │
│    hours of the day, and what it cost us.   │
│    Aeon · 3h ago                            │
└─────────────────────────────────────────────┘
```

- Summary text sits between the title and the metadata row
- `muted` colour — secondary, never competing with the title
- Playfair Display Regular, 14pt — softer than the title, warmer than metadata
- 3-line limit on iPhone (`.compact`), 4-line limit on iPad (`.regular`)
- If neither `summary` nor `feedDescription` is available, the section is absent entirely — card height stays compact, no blank gap

---

### Summary text source — precedence

Follows the same order already used in `FeedDetailView`:

1. `article.summary` — AI-generated on iOS 26+, exactly two sentences. Preferred when available.
2. `article.feedDescription` — RSS-supplied description, stripped HTML, capped at 500 chars at parse time. Shown when no AI summary exists.
3. Neither available — summary section hidden. Card is unchanged from today.

No new fields. No new fetches.

---

### Line limit rationale

The AI summary is two sentences by spec — it will rarely need more than 2 lines on any device. The `feedDescription` varies more; feeds often write verbose descriptions. The 3-line iPhone cap prevents the card from dominating the list while still giving enough signal. Four lines on iPad is comfortable given the wider layout.

The title retains its existing 2-line limit. The metadata row (feed name, time) retains its 1-line limit.

---

## Technical Approach

One change: `DigestArticleRow` in `DigestView.swift`.

Add a `@Environment(\.horizontalSizeClass)` read and a conditional `Text` block below the title:

```swift
let summaryText = article.summary ?? article.feedDescription
if let text = summaryText, !text.isEmpty {
    Text(text)
        .font(AppTheme.Typography.reader.size(14))
        .foregroundStyle(AppTheme.Colors.muted)
        .lineLimit(horizontalSizeClass == .regular ? 4 : 3)
        .lineSpacing(2)
}
```

No new component. No new view model logic. No new service calls.

`FeedDetailView.ArticleRow` already has this pattern at line 149–154 — the implementation is a direct copy with a tighter line limit.

---

## Acceptance Criteria

- [ ] Digest cards show `article.summary` when available (iOS 26+)
- [ ] Digest cards fall back to `article.feedDescription` when no AI summary exists
- [ ] Summary section is absent when neither field is populated — no blank gap
- [ ] Summary text is capped at 3 lines on iPhone (`.compact` horizontal size class)
- [ ] Summary text is capped at 4 lines on iPad (`.regular` horizontal size class)
- [ ] Summary uses `AppTheme.Colors.muted` foreground
- [ ] Summary uses Playfair Display Regular 14pt
- [ ] Title retains its existing 2-line limit; metadata row unchanged
- [ ] Card height is consistent within each section — no layout shifts after summary text loads
- [ ] No new models, services, or network calls introduced
