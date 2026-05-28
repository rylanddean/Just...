# Feed Reading Rate

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

The app quietly tracks when the user last read an article from each feed, and when a feed last published anything new. A small card at the top of `FeedDetailView` shows the last read date. Two independent auto-archive settings let users prune their feed list automatically: one for feeds they have stopped reading, one for feeds that have gone silent. Archived feeds live in a collapsed section at the bottom of `FeedsView` and can be restored with a single tap.

---

## Why

Subscribing is easy. The list grows. Reading stays the same. Over time, a user's feed list becomes an obligation — feeds they vaguely intend to read but never actually do. The queue fills with articles from feeds they have already moved on from.

Just… is a reading habit, not a subscription manager. The habit only works when the feed list reflects what the user actually reads. This feature surfaces the signal quietly — a date, a collapsed section, one toggle — and does the pruning automatically if the user opts in. Nothing is destroyed. Everything is recoverable.

---

## Experience

### Last read card in `FeedDetailView`

At the top of every feed's detail view, before the article list, a small metadata card appears. It shows the date the user last marked a queue item from this feed as read. This is the only place reading rate is surfaced — no charts, no percentages.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LAST READ
March 12

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- **"LAST READ"** — `.label` style: DM Mono, 11pt, all-caps, amber, letter-spaced
- Date in `.mono` style, `cream` colour
- If never read: "Never" in `muted`
- Card background: `surface`, 1pt `amberDim` border, no shadow
- Full-width, same horizontal insets as the article list

The card is purely informational. No tap target, no action.

---

### Auto-archive

A background task runs nightly and evaluates two independent conditions. Either can trigger archive on its own.

**Unread auto-archive** — when enabled, archives feeds the user has stopped reading. A feed qualifies if `lastReadAt` is older than the chosen threshold, or is `nil` and `lastFetchedAt` is also older than the threshold (never read, and old enough to not be new).

**Important:** the unread check only runs if the user has opened the app at least once within the threshold window. If the user hasn't opened the app in longer than the threshold (e.g. they were on holiday for 10 days with a 7-day setting), the check is skipped entirely — absence from the app is not the same as disinterest in a feed. The app stamps `lastAppOpenAt` in UserDefaults each time it becomes active.

**Dead feed auto-archive** — when enabled, archives feeds that have gone silent. A feed qualifies if `lastArticleAt` is older than the chosen threshold, or is `nil` and `lastFetchedAt` is older than the threshold (never produced an article despite being polled). This check runs regardless of app-open recency — a feed that hasn't published in 14 days is dead whether or not the user was present.

Both checks skip paused feeds. Either condition archiving a feed is sufficient — a feed does not need to fail both.

Archived feeds:
- Are removed from the active feed list in `FeedsView`
- Stop being fetched in background refresh
- Stop appearing in DigestView
- Retain all existing articles in the SwiftData store
- Can be restored at any time with a single tap

No notification fires when a feed is archived. Silence is the correct signal.

---

### Archived Feeds section in `FeedsView`

At the very bottom of the feed list, below all active feeds, a collapsed disclosure group appears only when archived feeds exist.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▸ ARCHIVED FEEDS  (4)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Expanded:

```
▾ ARCHIVED FEEDS  (4)

  Farnam Street Blog     no new articles · 14d    Restore
  Ribbonfarm             not read · 7d             Restore
  Nautilus Magazine      not read · 30d            Restore
  The Browser            manually archived         Restore
```

- **"ARCHIVED FEEDS"** — `.label` style: DM Mono, 11pt, all-caps, `muted` (not amber — these are dormant)
- Count in the same style, `subtle`
- Feed names in `.mono`, `muted`
- Archive reason in `.mono`, `subtle` — one of: "no new articles · Xd", "not read · Xd", "manually archived"
- "Restore" in amber — the one actionable element
- Section collapsed by default; state persisted in UserDefaults (`archivedFeedsSectionExpanded`)
- Swipe-to-delete on archived feeds permanently removes them (standard confirmation)

Tapping "Restore" moves the feed back to the active list and resumes background fetching. `lastReadAt` and `lastArticleAt` are both preserved — the feed re-enters the list with its history intact.

---

### Settings

Two new entries under the **Feeds** section in `SettingsView`. They are independent — either, both, or neither can be enabled.

```
AUTO-ARCHIVE UNREAD FEEDS
Archive feeds you haven't read in:   7 days ›

AUTO-ARCHIVE DEAD FEEDS
Archive feeds with no new articles in:   14 days ›
```

Each is a toggle + inline picker, not a separate screen. When a toggle is off:

```
AUTO-ARCHIVE UNREAD FEEDS
Off

AUTO-ARCHIVE DEAD FEEDS
Off
```

Picker options for both: **7 days** / **14 days** / **30 days**. Defaults when first enabled: 7 days (unread), 14 days (dead feed).

No explainer paragraphs. The labels are self-evident.

**Copy rules:**
- Unread toggle label: "Auto-archive unread feeds"
- Unread picker label: "Archive feeds you haven't read in:"
- Dead feed toggle label: "Auto-archive dead feeds"
- Dead feed picker label: "Archive feeds with no new articles in:"
- Off state: no secondary text needed

---

### Manual archive

Users can also archive a feed manually via swipe-to-archive in `FeedsView` (alongside the existing swipe-to-delete). The archive action uses the `archivebox` system icon. No confirmation required — restore is one tap away.

---

### No empty-state messaging

When all feeds are archived, `FeedsView` shows the standard empty state (same as no feeds subscribed). No "your feed list is empty — check your archived feeds" message. The archived section is already visible.

When no feeds have been archived, the "ARCHIVED FEEDS" section is absent entirely. Not collapsed, absent.

---

## Technical Approach

### Model changes — `RSSFeed`

Three new fields:

```swift
var lastReadAt: Date? = nil          // updated when user marks a queued article from this feed as read
var lastArticleAt: Date? = nil       // updated when RSSFetchService stores a new article for this feed
var isArchived: Bool = false         // set true on auto-archive or manual archive
var archiveReason: String? = nil     // "unread" | "dead" | "manual" — shown in archived row
```

`lastReadAt` is updated in the same path that marks a `QueuedLink` as read — wherever `readAt` is stamped on the queued item. Look up the article's `feedID`, find the corresponding `RSSFeed`, and set `lastReadAt = Date()`.

`lastArticleAt` is updated in `RSSFetchService` when new articles are written for a feed. Set it to the `publishedAt` of the most recent article stored in that batch.

`isArchived` gates:
- Exclusion from the active feed query in `FeedsView` (predicate: `!$0.isArchived`)
- Exclusion from `RSSFetchService` background polling
- Exclusion from `DigestView` feed lookup
- Inclusion in the archived section query (`$0.isArchived == true`)

No new model type. No migration beyond adding four optional/defaulted fields.

---

### Auto-archive task

A lightweight nightly check, slotted into the existing `BGAppRefreshTask` handler in `JustEllipsisApp`:

```swift
func runAutoArchive(feeds: [RSSFeed], now: Date = .now) {
    let defaults = UserDefaults.standard
    let unreadEnabled  = defaults.bool(forKey: "autoArchiveUnreadEnabled")
    let deadEnabled    = defaults.bool(forKey: "autoArchiveDeadEnabled")
    let unreadDays     = defaults.integer(forKey: "autoArchiveUnreadDays")   // 7 / 14 / 30
    let deadDays       = defaults.integer(forKey: "autoArchiveDeadDays")     // 7 / 14 / 30

    guard unreadEnabled || deadEnabled else { return }

    let unreadCutoff = Calendar.current.date(byAdding: .day, value: -unreadDays, to: now) ?? now
    let deadCutoff   = Calendar.current.date(byAdding: .day, value: -deadDays,   to: now) ?? now

    for feed in feeds where !feed.isArchived && !feed.isPaused {
        if unreadEnabled {
            let neverRead  = feed.lastReadAt == nil
            let staleRead  = feed.lastReadAt.map { $0 < unreadCutoff } ?? false
            let oldEnough  = feed.lastFetchedAt.map { $0 < unreadCutoff } ?? false
            if staleRead || (neverRead && oldEnough) {
                feed.isArchived = true
                feed.archiveReason = "unread"
                continue
            }
        }
        if deadEnabled {
            let noArticles    = feed.lastArticleAt == nil
            let staleFeed     = feed.lastArticleAt.map { $0 < deadCutoff } ?? false
            let polledLongAgo = feed.lastFetchedAt.map { $0 < deadCutoff } ?? false
            if staleFeed || (noArticles && polledLongAgo) {
                feed.isArchived = true
                feed.archiveReason = "dead"
            }
        }
    }
}
```

No notification. No confirmation. Runs silently.

---

### `FeedsView` changes

- Primary query gains predicate: `!$0.isArchived`
- New secondary `@Query(filter: #Predicate { $0.isArchived })` for the archived section
- `DisclosureGroup` at list bottom, hidden when archived query is empty
- Swipe action: `.archivebox` icon, `archive(feed:)` sets `feed.isArchived = true`
- Restore action in archived section: `feed.isArchived = false`

---

### `FeedDetailView` changes

- New `LastReadCard` component rendered above the article list (and above the newsletter address row if present)
- Reads `feed.lastReadAt` directly — no additional query

```swift
struct LastReadCard: View {
    let lastReadAt: Date?
    // ...
}
```

---

### `SettingsView` changes

Four new `@AppStorage` keys, two per setting:

```swift
@AppStorage("autoArchiveUnreadEnabled") var autoArchiveUnreadEnabled: Bool = false
@AppStorage("autoArchiveUnreadDays")    var autoArchiveUnreadDays: Int = 7
@AppStorage("autoArchiveDeadEnabled")   var autoArchiveDeadEnabled: Bool = false
@AppStorage("autoArchiveDeadDays")      var autoArchiveDeadDays: Int = 14
```

Two toggle + conditional picker rows in the existing Feeds section, rendered sequentially. Picker values for both: `[7, 14, 30]`.

---

### `DigestView` change

DigestView's `feeds` query currently has no predicate. Every article section already filters using `feedLookup[$0.feedID] != nil` — articles whose feed isn't in the lookup are invisible. Adding `!$0.isArchived` to the query is sufficient to drop archived-feed articles from all sections (Today, Yesterday, Earlier, and the Brain recommendations), because archived feeds won't appear in `feedLookup`.

```swift
// Before
@Query private var feeds: [RSSFeed]

// After
@Query(filter: #Predicate<RSSFeed> { !$0.isArchived }) private var feeds: [RSSFeed]
```

No changes to the article query or any of the section filters — the lookup exclusion handles it all.

---

### `RSSFetchService` change

In the method that iterates feeds for background refresh, add guard:

```swift
guard !feed.isArchived else { continue }
```

---

## Acceptance Criteria

- [ ] `RSSFeed` has `lastReadAt: Date?`; set when a queued article from this feed is marked read
- [ ] `RSSFeed` has `lastArticleAt: Date?`; set in `RSSFetchService` to the most recent article's `publishedAt` when new articles are stored
- [ ] `RSSFeed` has `isArchived: Bool = false` and `archiveReason: String?`
- [ ] `FeedDetailView` shows `LastReadCard` at top of list; displays formatted date or "Never" if `lastReadAt == nil`
- [ ] Card is purely informational — no tap target
- [ ] Settings → Feeds has two independent auto-archive controls:
  - Unread: toggle (`autoArchiveUnreadEnabled`) + picker (`autoArchiveUnreadDays`: 7 / 14 / 30, default 7)
  - Dead feed: toggle (`autoArchiveDeadEnabled`) + picker (`autoArchiveDeadDays`: 7 / 14 / 30, default 14)
- [ ] `JustEllipsisApp` stamps `lastAppOpenAt` in UserDefaults each time `scenePhase == .active`
- [ ] Nightly task archives feeds matching either enabled condition; sets `archiveReason` to `"unread:\(days)"` or `"dead:\(days)"` accordingly
- [ ] Unread check is skipped entirely if `lastAppOpenAt` is older than the unread threshold — absence from the app should not trigger archiving
- [ ] A feed failing both conditions is archived with the first matched reason (unread checked before dead)
- [ ] Archived feeds are excluded from the active feed list in `FeedsView`
- [ ] Archived feeds are excluded from `RSSFetchService` background polling
- [ ] `DigestView` `feeds` query gains `!$0.isArchived` predicate; archived-feed articles disappear from all digest sections without changes to section filter logic
- [ ] "ARCHIVED FEEDS" disclosure group appears at bottom of `FeedsView` only when archived feeds exist; absent otherwise
- [ ] Section is collapsed by default; collapsed/expanded state persisted in UserDefaults
- [ ] Each archived row shows the feed name, archive reason ("no new articles · Xd" / "not read · Xd" / "manually archived"), and a "Restore" action
- [ ] Restore sets `isArchived = false`, clears `archiveReason`, resumes fetching; `lastReadAt` and `lastArticleAt` preserved
- [ ] Swipe-to-archive on active feed rows uses `archivebox` icon; sets `archiveReason = "manual"`; no confirmation required
- [ ] Swipe-to-delete on archived feed rows permanently removes the feed (with standard confirmation)
- [ ] No notification fires on auto-archive
- [ ] No empty-state message points user toward archived section
- [ ] All colours use `AppTheme.Colors` tokens; "Restore" uses `amber`; archived feed names and reason use `muted` / `subtle`
- [ ] Paused feeds are excluded from both auto-archive conditions
