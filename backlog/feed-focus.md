# Feed Focus

**Tier:** Free  
**Effort:** S  
**Status:** Backlog — Original Feature

Once a week, the Feeds view surfaces which feeds haven't made it into your queue lately. One quiet card. No alarm. The suggestion is simple: a smaller feed list reads better. Remove the noise. Keep the signal.

---

## Why

Subscribing to a feed is easy. Unsubscribing requires remembering you should. Over time, a user's feed list drifts — 30 feeds subscribed, 6 actually producing articles they queue. The other 24 add friction without adding value: they dilute AI picks, they make FeedsView feel cluttered, and they create a vague sense of obligation to a reading list that never shrinks.

Just… is not a feed aggregator. It is a reading habit. The habit only works if the queue feels curated and personal. Feed Focus does the quiet work of asking: is this feed earning its place?

The feature is not a report. It is a prompt. It shows the user what they have ignored, offers one action — remove — and gets out of the way.

---

## Experience

### Trigger

Every Sunday at 9AM local time, a background task evaluates each subscribed feed. A feed is considered **quiet** if it has been subscribed for ≥ 30 days and no article from it has been added to the queue in the past 30 days.

If one or more quiet feeds are found, a local notification fires:

> "Some of your feeds have been quiet."

No body copy. One line. Tapping it opens the Feeds tab.

If no quiet feeds exist, no notification fires. The audit runs silently.

---

### In-app card

When quiet feeds exist, a card appears pinned above the feed list in `FeedsView`. It does not interrupt the user — it is passive, always dismissible.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
QUIET FEEDS
These haven't made your queue in 30 days.

  Farnam Street Blog         ╱ Remove
  Ribbonfarm                 ╱ Remove
  Nautilus Magazine          ╱ Remove

                            Dismiss ›
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- **"QUIET FEEDS"** — `.label` style: DM Mono, all-caps, amber, letter-spaced
- Feed names in `.mono` style, `cream` colour
- "Remove" in `streakDanger` — a soft red, no button chrome, tap-target sized
- "Dismiss" in `muted` — not emphasised. Dismissal is always available.
- Card background: `surface`, `amberDim` border, no shadow

Tapping **Remove** on a feed triggers the standard unsubscribe flow — same confirmation as swipe-to-delete. The feed name disappears from the card immediately. When the last quiet feed is removed or dismissed, the card disappears.

Tapping **Dismiss** hides the card for 14 days. No snooze UI — it just reappears at the next Sunday audit if quiet feeds still exist.

---

### No empty-state lecturing

If all feeds are active (each has queued at least one article in the past 30 days), the card is absent. No "great job, all feeds are active!" message. Silence is the correct signal for a healthy feed list.

If the user has fewer than 3 feeds subscribed total, the audit does not run. Below this threshold, focus is not the problem.

---

### Threshold logic

A feed is quiet if **all three** are true:

1. Subscribed for ≥ 30 days (new subscriptions get a grace period)
2. No article from this feed has been queued (manually or via AI pick) in the past 30 days
3. Feed is not currently paused (paused feeds are intentionally dormant — no audit)

---

## Technical Approach

### Model change — `RSSFeed`

Add one field:

```swift
var lastQueuedAt: Date? = nil
```

Updated in two places:
- `RSSFetchService` when an AI pick from this feed is promoted to the queue
- `FeedDetailView` (or the `QueuedLink` creation path) when the user manually queues an article from this feed

This is the only model migration required.

---

### New service method — `FeedAuditService`

```swift
struct FeedAuditService {
    static func quietFeeds(
        from feeds: [RSSFeed],
        now: Date = .now
    ) -> [RSSFeed]
}
```

Filters feeds where:
- `subscribedAt` (from `id` creation date, or a new `subscribedAt: Date` field — see note below) is > 30 days ago
- `lastQueuedAt == nil || lastQueuedAt < now - 30 days`
- `isPaused == false`

**Note on `subscribedAt`**: `RSSFeed` does not currently store a subscription date. The grace period can be approximated conservatively — run the audit only on feeds where `lastFetchedAt` is > 30 days old. If `lastFetchedAt` is recent, the feed is either new or recently re-activated. This avoids a second migration.

---

### Weekly background task

Slot the audit into the existing Sunday morning local notification schedule (already used for weekly digest in V1.1 premium). A lightweight `BGAppRefreshTask` or `UNUserNotificationCenter`-scheduled evaluation — no persistent actor, no network required.

```swift
// Fires Sunday 9AM
func runWeeklyFeedAudit(feeds: [RSSFeed]) {
    let quiet = FeedAuditService.quietFeeds(from: feeds)
    guard quiet.count > 0 else { return }
    scheduleQuietFeedsNotification()
}
```

---

### `FeedsView` changes

- Inject `quietFeeds: [RSSFeed]` as a computed property from the existing `@Query` feeds result
- Conditionally render `FeedFocusCard(feeds: quietFeeds, onRemove:, onDismiss:)` above the list
- `onDismiss` writes `lastDismissedAuditAt = Date.now` to UserDefaults; card hidden until next Sunday
- `onRemove(feed)` calls the existing unsubscribe handler — no new deletion logic

---

### Notification permission

No new permission request. Audit notification reuses the existing local notification permission granted for streak reminders. If the user has denied notifications, the audit runs silently — the in-app card is still shown on next Feeds view open.

---

## Acceptance Criteria

- [ ] `RSSFeed` has `lastQueuedAt: Date?` field; updated on manual queue and AI pick
- [ ] `FeedAuditService.quietFeeds()` returns feeds subscribed >30 days with no queue activity in past 30 days, excluding paused feeds
- [ ] Audit does not run if fewer than 3 feeds are subscribed
- [ ] Sunday 9AM notification fires only when quiet feeds exist; silent otherwise
- [ ] Notification copy: "Some of your feeds have been quiet." — no body, no emoji
- [ ] `FeedFocusCard` appears above feed list in `FeedsView` when quiet feeds exist
- [ ] Card shows each quiet feed name with an individual "Remove" action
- [ ] Remove triggers standard unsubscribe flow with confirmation; feed disappears from card immediately
- [ ] Dismiss hides card for 14 days (UserDefaults: `lastDismissedFeedAuditAt`)
- [ ] Card is absent when no quiet feeds exist — no empty state message
- [ ] Paused feeds are excluded from the audit
- [ ] New feeds subscribed within 30 days are excluded from the audit
- [ ] All colours use `AppTheme.Colors` tokens; "Remove" uses `streakDanger`
- [ ] No new tab, sheet, or navigation destination introduced
