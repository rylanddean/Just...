# RSS Feeds + AI Daily Picks

**Tier:** Free  
**Effort:** XL  
**Status:** Backlog

Allow users to subscribe to RSS feeds directly in Just…, and use on-device AI to recommend 3 personalised articles from those feeds each morning. The content comes to the user — pre-filtered by their own taste, pre-stripped, and ready to read. No algorithm, no server, no data leaving the device.

---

## Why

The current save loop requires manual link discovery. For power readers, this friction is too high — they want a steady stream of good material without hunting. RSS is the open, private, algorithm-free format for this. On-device AI ensures curation reflects actual interests (inferred from Brain entries) without sending anything to a server. Combined, this feature makes Just… the only reading habit app where the habit is sustained by personalised content, not just willpower.

---

## Experience

**Feeds tab:** A new section in the app (or a dedicated tab) listing subscribed feeds. Each row shows feed name, category, last-fetch time, and unread article count.

**Subscribe:** Add via URL paste OR browse a bundled directory of 150+ quality feeds across 10 categories: Technology, Science, Design, Culture, Finance, Philosophy, Politics, Health, Sport, and Long-form. Directory ships with the app — no network request required to browse.

**Daily Picks:** Each morning at 7 AM, the app fetches fresh articles from all subscribed feeds, scores them against the user's Brain (topic affinity inferred from Brain entry titles and reflections), and adds the top 3 to a "Picked for you" section at the top of the queue. These are visually distinct from manually-added links (a small amber RSS glyph in the card corner).

**Reading:** Tapping a picked article opens the standard Reader. Reflect and Brain work identically. The `QueuedLink` model gains a `source` field: `.manual`, `.rss(feedID:)`, or `.aiPick`.

**Feed management:** Swipe to unsubscribe. Long-press to pause without unsubscribing (feed keeps fetching but contributes no picks). Last-fetch timestamp shown to signal staleness.

---

## RSS Infrastructure

**Parsing:** [FeedKit](https://github.com/nmdias/FeedKit) — open-source SPM package. Handles RSS 2.0, Atom, and JSON Feed. Lightweight (~200kb addition to binary).

**Fetching:** `BGProcessingTask` fetches all subscribed feeds once per day. Parsed items stored as `RSSArticle` (new SwiftData model). Articles older than 7 days are pruned.

**Bundled directory:** `Resources/feeds.json` — a curated JSON file of `{name, url, category, description}` records. Initial catalog of ~150 feeds, hand-curated from [AboutRSS/ALL-about-RSS](https://github.com/AboutRSS/ALL-about-RSS) and [OPML Club](https://opml.club). Updated via app releases; community contributions via the GitHub repo.

---

## AI Recommendations (iOS 26+)

```swift
// RSSRecommendationEngine
// Input:  [RSSArticle] — fresh from subscribed feeds
//         [BrainEntry] — user's last 30 reads
// Output: [RSSArticle] — top 3 picks, diversity-penalised

// Approach:
// 1. Build a reader profile string from the last 30 Brain entry titles + reflections.
// 2. For each fresh article, call IntelligenceService to score semantic relevance (0–10).
// 3. Apply diversity penalty — never pick 2 articles from the same feed.
// 4. Return top 3 with score >= 6.
```

**Fallback** (no Apple Intelligence): pick the 3 most recently published articles from the 3 most active subscribed feeds. Recency-based, no personalisation. Always functional.

**Cold start** (Brain has < 5 entries): show the 3 most popular articles across subscribed feeds (by title sentiment heuristic). Display a quiet nudge: "Read more to improve your picks."

---

## New SwiftData Models

```swift
@Model final class RSSFeed {
    var id: UUID
    var url: String
    var title: String
    var category: String
    var lastFetchedAt: Date?
    var isPaused: Bool
}

@Model final class RSSArticle {
    var id: UUID
    var feedID: UUID
    var url: String
    var title: String
    var publishedAt: Date
    var isQueued: Bool   // promoted to QueuedLink
}
```

---

## Risks

| Risk | Mitigation |
|---|---|
| Feed URLs go stale or sites disappear | Graceful error state in feed row; retry with exponential backoff |
| Paywalled articles surface in picks | ContentFetcher returns an error; show "Open in Safari" fallback in the reader |
| Bundled directory becomes outdated | Plan an optional HTTPS update path for `feeds.json`, cached locally |
| FeedKit adds parsing overhead | Parse in background task; never on main thread |
| AI quality low on small Brains | Cold-start fallback; nudge to read more |
| CloudKit sync of `RSSArticle` creates noise | Exclude `RSSArticle` from iCloud sync — it is ephemeral; feeds themselves sync |

---

## Acceptance Criteria

- [ ] Users can subscribe to a feed by pasting a URL
- [ ] Bundled directory is browsable by category without network
- [ ] Feeds fetch daily in background via `BGProcessingTask`
- [ ] 3 AI-picked articles appear in queue each morning (iOS 26+, AI available)
- [ ] Fallback picks work without AI — recency-based
- [ ] `RSSArticle` records older than 7 days are pruned
- [ ] Feed pause and unsubscribe work via swipe/long-press
- [ ] Paywalled articles show "Open in Safari" fallback
- [ ] Feature available to all users
