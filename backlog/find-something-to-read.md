# Find Something to Read

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

When the queue is empty and the user hasn't yet read today, they can type a topic or interest and the app returns 3 high-quality article suggestions to choose from. One-shot, intentional, opt-in. Not a feed. Not an algorithm. More like asking a librarian.

If the queue is empty but the user *has* already read today, the empty state is a success — they showed up. Discovery is not surfaced. The feature only appears when the habit is still open.

---

## Why

The queue being empty and the day still open is the loneliest moment in Just…. A user who wants to build a reading habit but doesn't have a link saved will bounce. This feature turns that specific empty state into an invitation — without compromising the core position that Just… is not a read-later archive.

An empty queue after the user has already read today is not a problem — it is the goal. Surfacing discovery there would dilute the satisfaction of having shown up and push the app toward the accumulation behaviour it explicitly rejects. The condition must be: queue empty *and* no reading recorded today.

---

## The Tension

The product proposal says the queue is "for reading now, not someday." A discovery feature risks becoming another way to fill a queue that never gets read.

The design resolves this in two ways. First, it is only surfaced when the queue is empty *and* the user hasn't read today — the one moment where discovery genuinely serves the habit. Second, it is treated as a single deliberate action (search a topic → pick one article) rather than a subscription or browse session. The result set is capped at 3. There is no "add all" button. It is never a persistent tab or home screen fixture.

---

## Experience

**Entry points:**
1. **Empty state (primary)** — shown only when `queue.isEmpty && !StreakEngine.hasReadToday(days: readingDays)`. Below the "Your queue is empty." message, a secondary button: `Find something to read →`. When the queue is empty but the user *has* read today, this button is replaced with a quiet completion message: *"You read today. Come back tomorrow."*
2. **Add Link sheet** — a tab or toggle alongside "Paste a URL": `Discover`. Always accessible regardless of streak state — the user may want to pre-fill tomorrow's queue.

**Flow:**
1. A single text field: *"What do you want to read about?"* with a placeholder like *"stoicism, climate, design systems…"*
2. User types a topic and taps Search (or hits return).
3. A brief loading state (spinner, ~1–2s).
4. Up to 3 result cards appear, each showing: headline, source domain, and an estimated read time.
5. Each card has an `+` button to add it to the queue. Cards can be added independently — there is no "add all."
6. Once an article is added, its card dims and the `+` becomes a checkmark. It does not disappear — the user can still see what they chose.
7. No pagination, no "load more." 3 results is the result. If the topic is too niche, show a gentle empty state: *"Nothing strong came back. Try a broader topic."*

**After adding:** The sheet dismisses. The user sees their queue with the newly added link(s) at the bottom.

---

## API Strategy

### Primary — HackerNews Algolia
**Endpoint:** `https://hn.algolia.com/api/v1/search`  
**Cost:** Free. No API key. No auth. No rate limit for small-scale use.  
**Quality:** Crowd-vetted by the HN community. Exceptional for technology, science, startups, philosophy, design, culture.  
**Query:** `?query={topic}&tags=story&numericFilters=points>30&hitsPerPage=10`  
Filter to `points > 30` to ensure the article has been meaningfully upvoted. Pick the top 3 hits that have a valid `url` field (not Ask HN or Show HN posts).

```
GET https://hn.algolia.com/api/v1/search
  ?query=stoicism
  &tags=story
  &numericFilters=points>30
  &hitsPerPage=10

Response fields used:
  hit.title   → article headline
  hit.url     → article URL (filter out nil — these are text posts)
  hit.points  → quality signal (not shown to user)
```

### Secondary — The Guardian Open Platform
**Endpoint:** `https://content.guardianapis.com/search`  
**Cost:** Free. Requires a free API key (registered in-app bundle — not user-provided).  
**Quality:** Professional journalism. Strong for news, politics, culture, health, sport, science.  
**Use when:** The HN search returns fewer than 3 valid results, or the topic is clearly news/culture oriented (detected by keyword heuristic).

```
GET https://content.guardianapis.com/search
  ?q={topic}
  &show-fields=trailText,wordcount
  &order-by=relevance
  &page-size=5
  &api-key={bundled_key}

Response fields used:
  result.webTitle    → headline
  result.webUrl      → article URL
  result.fields.wordcount → for estimated read time
```

### Source blending
Try HN first. If HN returns ≥ 3 usable results, use only HN. If HN returns 1–2, supplement with Guardian to reach 3. Never show source attribution in the UI — the user is choosing articles, not choosing sources.

---

## Read-Time Estimation

HN results don't include word count. Estimated read time is inferred by fetching only the `<head>` of the article URL (a HEAD request) and checking for Open Graph `article:reading_time` or Twitter card metadata. If unavailable, show no estimate rather than a placeholder. The Guardian results include `wordcount` — use `wordcount / 238` rounded up.

---

## Technical Approach

- New `DiscoveryService` — a pure static struct, no stored state.  
- `DiscoveryService.search(topic: String) async throws -> [DiscoveryResult]`  
- `DiscoveryResult: Sendable { let title: String; let url: String; let domain: String; let estimatedMinutes: Int? }`  
- The service tries HN, supplements with Guardian if needed, deduplicates by domain (avoid showing 2 articles from the same site), and returns up to 3.  
- Adding a result calls the same `QueuedLink` insert path as `AddLinkView` — no special handling.  
- The offline prefetch feature will automatically pick up newly added links and validate them (flagging paywalls). No additional validation needed in `DiscoveryService`.  
- The Guardian API key is bundled in the app as a build-time constant in a `Secrets.swift` file (gitignored). Not a user-facing setting.

```swift
struct DiscoveryService {
    static func search(topic: String) async throws -> [DiscoveryResult] {
        let hnResults = try await fetchHN(topic: topic)
        if hnResults.count >= 3 { return Array(hnResults.prefix(3)) }
        let guardianResults = try await fetchGuardian(topic: topic)
        let combined = (hnResults + guardianResults).deduplicatedByDomain()
        return Array(combined.prefix(3))
    }
}
```

---

## Privacy

The search query string is sent to HackerNews Algolia's servers (and optionally The Guardian's). This is the only point in Just… where any user-generated text leaves the device. The feature is opt-in and only triggered by an explicit search action — not in the background. No topic history is stored on-device.

A one-line disclosure in the UI: *"Search powered by Hacker News."* (shown as a small footer beneath the results). This is accurate, honest, and keeps the feature's mechanism transparent without being alarming.

---

## Acceptance Criteria

- [ ] "Find something to read →" appears in the empty state only when the user has not yet read today
- [ ] When queue is empty and user has read today, empty state shows *"You read today. Come back tomorrow."* — no discovery button
- [ ] Discovery tab in Add Link sheet is always accessible regardless of streak state
- [ ] "Discover" tab/toggle available in the Add Link sheet
- [ ] Typing a topic and searching returns up to 3 article cards
- [ ] Each card shows headline, domain, and read time (when available)
- [ ] `+` button adds the article to the queue; card dims and shows checkmark
- [ ] No "add all" — each article is added independently
- [ ] Fewer than 3 HN results are supplemented by Guardian results
- [ ] Fewer than 3 total results show a gentle empty state message
- [ ] All nil-URL HN hits (text posts) are filtered out
- [ ] Newly added articles flow through the standard `QueuedLink` insert path
- [ ] "Search powered by Hacker News." disclosure shown beneath results
- [ ] No topic search history stored on-device
