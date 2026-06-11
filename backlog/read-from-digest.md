# Read from the Digest

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

Tapping any article in the Digest opens the reader immediately. No queuing required. After reading, the standard reflect flow runs and a BrainEntry is created. The "+" button remains for articles the user wants to save for later. This removes the mandatory detour through the queue for users who want to read right now.

---

## Why

The current path from discovery to reading has an unnecessary step: see an article → add to queue → navigate to Home → tap to read. This works fine when you're planning ahead, but it works against the user who opens Just… and wants to read something now. Forcing that user through the queue creates friction that contradicts the app's core position — showing up and reading, not building a save pile.

The queue should be a deliberate choice: *I want to read this, but not right now.* Reading directly from the Digest should be the natural path for *I want to read this now.*

The current UX makes Just… behave like a read-later app even when the user's intent is to read immediately. That's the wrong default.

---

## Experience

### Digest Row Interaction

Current: tapping the row does nothing; "+" adds to queue.  
New: tapping the row opens the reader immediately; "+" queues for later.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Why Solitude Has Become a Lost Art
  psychologytoday.com  ·  6 min
                                   +
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- The row is fully tappable — tap anywhere except "+" opens the reader.
- "+" retains its appearance. Its meaning shifts from "add to queue" to "read later."
- No new UI elements. No "Read Now" label. The affordance is the tap itself.

### Reading Experience

Identical to reading from the queue. The reader strips chrome, renders the article, shows estimated read time. Scrolling to the end triggers the reflect prompt. The user reflects or skips. A BrainEntry is created.

The reader does not surface which path opened it.

### Post-Read State in Digest

After completing a read-from-digest session (reflect shown, regardless of save/skip), the article:

- Is removed from the Digest — `RSSArticle.isSeen = true`
- If it also existed as a `QueuedLink`, that link is marked `isRead = true`
- Does not reappear in any future Digest bucket

No toast, no confirmation. The article disappears from the list as the user navigates back — the same quiet behaviour as completing a queued read.

### Reading a Queued Article from the Digest

If a user previously queued an article and it is still visible in the Digest, tapping the row reads it immediately. The `QueuedLink` is marked `isRead = true`. The article is removed from both surfaces. No duplicate reflect prompt, no double-counting.

---

## Technical Approach

### ReadingSource — accept an article directly

`ReaderView` currently takes a `QueuedLink`. Extend it to accept a `ReadingSource`:

```swift
enum ReadingSource {
    case queued(QueuedLink)
    case digest(url: String, title: String, domain: String, feedID: UUID?)
}
```

`ReaderViewModel` resolves content from either source:

- `.queued` — existing path: use `cachedHTML` if available, otherwise fetch via `ContentFetcher`.
- `.digest` — fetch via `ContentFetcher` directly; no prefetch cache available.

After completion:

- `.queued` — mark `QueuedLink.isRead = true` (existing path).
- `.digest` — mark `RSSArticle.isSeen = true`; if a `QueuedLink` with a matching URL exists, mark it `isRead = true` too.

### BrainEntry creation

No change. `ReflectView` receives `title`, `domain`, and `url` regardless of source. BrainEntry is created identically via the existing path.

### DigestArticleRow

Add a tap gesture on the row that fires `onRead(article)` — a new callback alongside the existing `onQueue(article)`. The "+" button calls `onQueue` unchanged.

```swift
DigestArticleRow(
    article: article,
    onRead: { article in
        openReader(.digest(url: article.url, title: article.title, domain: article.domain, feedID: article.feedID))
    },
    onQueue: { article in
        queueArticle(article)
    }
)
```

### RSSArticle.isSeen

Already exists as a model field. Post-read, the model layer sets `article.isSeen = true`. `buildBuckets()` already filters by this field — no additional change needed to suppress the article from future Digest renders.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Not a read-later app | ✅ — Reading now requires no intermediate step |
| Unhurried | ✅ — No forced queue step; the queue is still there for deliberate saves |
| Honest | ✅ — "+" still present; no patterns removed or obscured |
| Minimal | ✅ — No new UI elements added to the Digest row |
| One thing | ✅ — Tap means read. Plus means save. |

---

## Copy Reference

No new copy strings required. The reading and reflect experience is identical.

| Moment | Copy |
|---|---|
| After finishing (existing, unchanged) | "Read. Now think for a moment." |
| Reflection saved (existing, unchanged) | "Kept. Your Brain grows." |
| Article removed from Digest | (silent — no toast or confirmation) |
| "+" button accessibility label | "Read later" |

---

## Acceptance Criteria

- [ ] Tapping a `DigestArticleRow` (outside the "+" button) opens the reader with the article immediately
- [ ] The reader fetches article content via `ContentFetcher` when no `QueuedLink` exists for that URL
- [ ] After reading (reflect shown, regardless of save/skip), `RSSArticle.isSeen = true`
- [ ] The article does not appear in any Digest bucket on return — neither today, yesterday, nor earlier
- [ ] If a matching `QueuedLink` exists for the same URL, it is marked `isRead = true`
- [ ] BrainEntry is created after reflect/skip — behaviour identical to queue-sourced reads
- [ ] "+" button adds to queue and marks `RSSArticle.isQueued = true` — behaviour and appearance unchanged
- [ ] Tapping a queued article from the Digest reads it immediately and marks both `RSSArticle.isSeen` and `QueuedLink.isRead` true
- [ ] `ReadingSource.digest` case fetches content without requiring a `QueuedLink`
- [ ] No new UI elements or labels added to the Digest row
- [ ] All colours use `AppTheme.Colors` tokens — no hardcoded hex values
