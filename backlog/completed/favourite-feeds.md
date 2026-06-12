# Favourite Feeds

**Tier:** Free  
**Effort:** S  
**Status:** Done

Mark any feed as a favourite in `FeedsView`. New articles from that feed are auto-queued the moment they arrive — no manual curation required. The reading habit runs itself for the feeds you trust most.

---

## The Problem

Most feeds produce more than one good article per day. Just… asks the user to choose which articles to queue — a deliberate friction that keeps the reading list short and personal. But some feeds earn unconditional trust. A user who has read every Stratechery edition for two years should not have to manually queue each new one. The current model treats every feed the same: articles sit in `FeedDetailView` until the user acts on them. For high-trust feeds, that step is wasted motion.

Favouriting a feed signals: "I always want to read this." New editions arrive in the queue automatically, exactly as if the user had tapped queue on each one.

---

## Experience

### Marking a Feed as Favourite

The user long-presses a feed row in `FeedsView` to open the context menu. A new option appears:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Rename
  Copy URL                         (or Copy reading address for newsletters)
  Pause / Resume
  ─────────────────────────────
  Auto-queue new articles          ← new
  ─────────────────────────────
  Unsubscribe
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Tapping **Auto-queue new articles** toggles the feed's favourite state. No confirmation sheet. The menu dismisses and the feed row updates immediately.

When a feed is already favourited, the menu option reads **Stop auto-queuing** in the same muted style — no red, no alarm. Turning it off is as quiet as turning it on.

---

### The Favourited Feed Row

A favourited feed row gains a small amber indicator pill:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [favicon]  Stratechery          AUTO ◆
             Technology · 2 hours ago
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- **"AUTO"** — `.label` style: DM Mono, all-caps, amber `#E8A83E`, letter-spaced. Appears in place of the unread article count badge when `isFavourite == true`.
- The diamond glyph (◆) is omitted if space is tight — the label alone is sufficient.
- Unread count badge is hidden for favourited feeds: articles from these feeds go directly to the queue and never accumulate as unread.

Favourited feeds sort to the top of the active feed list, above non-favourited feeds. Within each group, alphabetical order is preserved.

---

### What Auto-Queue Means

When `RSSFetchService` stores new articles for a favourited feed, those articles are inserted into SwiftData with `isQueued = true` immediately — the same flag set when the user manually taps queue. They appear in the reading queue on the next app open, attributed to their feed exactly like any queued article.

Articles already stored before the feed was favourited are not retroactively queued. Only new arrivals after the toggle are affected.

If the feed is paused, no fetch occurs, so no auto-queue occurs. Pausing always wins.

---

### Onboarding Hint

The first time a user marks a feed as favourite, a one-time hint appears inline below the feed row:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  New articles will arrive in your queue automatically.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- `.mono` style, `muted` colour
- Disappears after 3 seconds — no dismiss button
- Never shown again (UserDefaults flag: `hasSeenAutoQueueHint`)

---

## Technical Approach

### Model Change — `RSSFeed`

Add one field:

```swift
var isFavourite: Bool = false
```

No other migration required. Existing feeds default to `false` — behaviour is unchanged.

---

### Sorting

`FeedsView` currently sorts with `sort: \RSSFeed.title`. Change to a two-key sort: favourites first, then alphabetical within each group.

SwiftData's `@Query` does not support multi-key sort with custom comparators in a single pass. The simplest approach: split into two `@Query` results — one for favourites, one for non-favourites — and render them in order:

```swift
@Query(
    filter: #Predicate<RSSFeed> { !$0.isArchived && $0.isFavourite },
    sort: \RSSFeed.title
) private var favouriteFeeds: [RSSFeed]

@Query(
    filter: #Predicate<RSSFeed> { !$0.isArchived && !$0.isFavourite },
    sort: \RSSFeed.title
) private var regularFeeds: [RSSFeed]
```

The existing single `@Query` for `feeds` is replaced by these two. The `feedList` renders `favouriteFeeds` first, then `regularFeeds` — no section header between them unless there is at least one favourite (see below).

---

### Section Label (conditional)

When one or more favourites exist, a minimal section label appears above the regular feed list:

```
OTHERS
```

- `.label` style: DM Mono, all-caps, `textFaint`, letter-spaced
- Present only when `favouriteFeeds.count > 0 && regularFeeds.count > 0`
- Absent when the user has no favourites (the default state) — zero visual clutter

No "FAVOURITES" label above the top group. The amber `AUTO` pill on each row is sufficient.

---

### Auto-Queue in `RSSFetchService`

When storing new articles for a feed, check `feed.isFavourite`:

```swift
for item in newItems {
    let article = RSSArticle(from: item, feedID: feed.id)
    article.isQueued = feed.isFavourite   // auto-queue if favourited
    context.insert(article)
}
```

This is a single-line change in the article insertion path. No new service or background task required.

---

### Context Menu Change — `FeedsView`

Add a toggle action to the existing context menu block in `feedList`:

```swift
Button {
    feed.isFavourite.toggle()
    try? context.save()
} label: {
    Label(
        feed.isFavourite ? "Stop auto-queuing" : "Auto-queue new articles",
        systemImage: feed.isFavourite ? "star.slash" : "star"
    )
}
```

Placed above the `Divider()` that precedes Unsubscribe — grouped with the non-destructive feed management actions.

---

### `FeedRow` Changes

- Show `AUTO` pill in amber when `feed.isFavourite == true`, in place of the unread count badge.
- The unread count badge (`articles.count > 0`) is suppressed for favourited feeds — their articles don't accumulate unread.

```swift
if feed.isFavourite {
    Text("AUTO")
        .font(AppTheme.sansSerif(10, weight: .medium))
        .foregroundStyle(appTheme.accent)
        .kerning(1.5)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(appTheme.accentFaint)
        .clipShape(Capsule())
} else if articles.count > 0 {
    Text("\(articles.count)")
        .font(AppTheme.sansSerif(12, weight: .medium))
        .foregroundStyle(appTheme.background)
        .frame(minWidth: 22, minHeight: 22)
        .background(appTheme.accent)
        .clipShape(Circle())
}
```

The `@Query` in `FeedRow` that filters `!$0.isQueued` is unchanged — it simply returns 0 results for favourited feeds because all articles are queued on arrival.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Calm, no pressure | ✅ — Toggle is quiet; hint disappears automatically |
| Accumulation, not performance | ✅ — Auto-queue grows the reading habit, no stats surfaced |
| User controls what enters the queue | ✅ — Opt-in per feed; default is unchanged |
| No social language | ✅ — "Auto-queue" not "follow", "subscribe", or "favourite" in UI copy |
| No exclamation points | ✅ |
| Amber for active states only | ✅ — `AUTO` pill uses `accent` + `accentFaint` |
| No new tab or navigation | ✅ — Lives entirely within existing `FeedsView` |
| Consistent with existing model | ✅ — One `Bool` field, no schema redesign |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Context menu — enable | "Auto-queue new articles" |
| Context menu — disable | "Stop auto-queuing" |
| Feed row indicator | "AUTO" (DM Mono, all-caps, amber) |
| One-time hint | "New articles will arrive in your queue automatically." |

---

## Acceptance Criteria

- [x] `RSSFeed` has `isFavourite: Bool = false`; existing feeds unaffected
- [x] Context menu in `FeedsView` includes "Auto-queue new articles" / "Stop auto-queuing" toggle
- [x] `feed.isFavourite.toggle()` persists immediately via `context.save()`
- [x] Favourited feeds appear above non-favourited feeds in `FeedsView`, both groups sorted alphabetically
- [x] "OTHERS" section label appears only when at least one favourite and at least one non-favourite exist
- [x] `FeedRow` shows amber "AUTO" pill for favourited feeds; unread count badge is hidden
- [x] New articles fetched for a favourited feed are inserted with `isQueued = true`
- [x] Articles stored before a feed was favourited are not retroactively queued
- [x] Paused feeds are not fetched; auto-queue does not trigger for paused feeds
- [x] One-time hint appears below the feed row on first favourite; dismissed automatically after 3s; never shown again
- [x] All colours use `AppTheme.Colors` tokens — no hardcoded hex
- [x] No new tab, sheet, or navigation destination introduced
