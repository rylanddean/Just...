# Queue as Read Later

**Tier:** Free  
**Effort:** S  
**Status:** Backlog  
**Depends on:** [Read from the Digest](../read-from-digest.md)

With reading now possible directly from the Digest, the Home tab queue transitions from "the only place to read" to "things I'm saving for later." This story tightens the copy and empty-state language to reflect that mental shift — without changing the queue's mechanics or removing anything.

---

## Why

Before "Read from the Digest," the queue was the only reading surface. Its empty state — *"Nothing to read. Add a link."* — made sense because an empty queue meant you literally had nothing to read.

After that change, the queue means something more specific: links you've deliberately deferred. An empty queue after reading from the Digest is not a failure state — it is the correct outcome of a healthy session. The copy needs to reflect that.

If "Nothing to read. Add a link." is the only empty state, users who just finished reading from the Digest will feel like they did something wrong. The queue needs to know when it's empty because you showed up, not because you haven't.

---

## Experience

### Empty Queue — Not Yet Read Today

No change from current. *"Nothing to read. Add a link."* with the standard add/find entry points.

### Empty Queue — Already Read Today

A second empty state for `queue.isEmpty && hasReadToday`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


  Nothing saved for later.

  You read today.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- "Nothing saved for later." — `.headline`, `cream`
- "You read today." — `.mono`, `muted`
- No CTA. No button. An empty queue after a read is a success state — surfacing a discovery prompt here would undercut that.

This state also replaces the "Find something to read →" secondary CTA when it would otherwise appear — the user has already read; that moment has passed.

### "+" Button Accessibility Label

Update the accessibility label on the "+" in `DigestArticleRow`:

- Current: "Add to queue"
- New: "Read later"

No visual change. This affects VoiceOver users only and aligns the label with the button's actual purpose post-feature.

---

## Technical Approach

Two changes, both small:

**1. HomeView empty state**

Add a conditional branch:

```swift
if queue.isEmpty {
    if streakEngine.hasReadToday(days: readingDays) {
        QueueReadTodayEmptyState()   // "Nothing saved for later. / You read today."
    } else {
        QueueEmptyState()            // existing empty state, unchanged
    }
}
```

`QueueReadTodayEmptyState` is a simple two-line view — no new dependencies.

**2. DigestArticleRow accessibility label**

```swift
Button { onQueue(article) } label: {
    Image(systemName: "plus")
}
.accessibilityLabel("Read later")
```

No model changes. No new services.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Never shame | ✅ — Empty queue after reading is affirmed, not flagged |
| Celebrates showing up | ✅ — "You read today." is a quiet, factual affirmation |
| Honest | ✅ — Accurately reflects what the queue now is |
| Minimal | ✅ — One new empty-state variant; no new UI components |
| Unhurried | ✅ — No urgency injected into the success state |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Empty queue, not yet read today (unchanged) | "Nothing to read. Add a link." |
| Empty queue, already read today | "Nothing saved for later." |
| Second line of read-today state | "You read today." |
| "+" accessibility label | "Read later" |

---

## Acceptance Criteria

- [ ] When `queue.isEmpty && hasReadToday == true`, the empty state shows "Nothing saved for later." with "You read today." below in `.mono muted`
- [ ] When `queue.isEmpty && hasReadToday == false`, the empty state is unchanged: "Nothing to read. Add a link."
- [ ] The "Find something to read →" CTA does not appear in the read-today empty state
- [ ] "+" button in `DigestArticleRow` has `.accessibilityLabel("Read later")`
- [ ] No visual changes to the "+" button
- [ ] Empty state typography matches: "Nothing saved for later." in `.headline cream`, "You read today." in `.mono muted`
- [ ] Shipped after or alongside Read from the Digest
