# Find Something to Read

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

When the queue is empty and the user hasn't read today, they can type a topic or interest and get 3 high-quality article suggestions to choose from. One-shot, intentional, opt-in. Not a feed. Not an algorithm. More like asking a librarian.

If the queue is empty but the user *has* already read today, the empty state is a success — they showed up. Discovery is not surfaced.

---

## Why

The queue being empty with the day still open is the loneliest moment in Just…. A user who wants to build a reading habit but has nothing saved will bounce. This feature turns that specific empty state into an invitation — without compromising the core position that Just… is not a read-later archive.

An empty queue *after* the user has read today is not a problem — it is the goal. Surfacing discovery there would dilute the satisfaction of having shown up.

---

## Experience

### Entry Point

Empty state in `HomeView` shows: *"Nothing to read. Add a link."*

When `queue.isEmpty && !StreakEngine.hasReadToday(days: readingDays)`, a secondary button appears below: **"Find something to read →"**

When `queue.isEmpty && StreakEngine.hasReadToday(days: readingDays)`, this button is replaced with a quiet line: *"You read today. Come back tomorrow."*

---

### Discovery Flow

Tapping "Find something to read" opens a bottom sheet:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
What do you want to read about?

  ┌─────────────────────────────┐
  │ stoicism, climate, design… │
  └─────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The user types a topic and taps Search (or return). A spinner appears (~1–2s). Up to 3 result cards:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Headline of the first article
  nytimes.com  ·  8 min

  +
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- Headline in `.headline` style, `cream`.
- Domain and estimated read time in `.mono`, `muted`.
- **+** button adds to queue — card dims, + becomes a checkmark. Card does not disappear.
- No "add all" button — each article added independently.
- No pagination, no "load more." 3 results is the result.
- If fewer than 3 strong results exist: gentle empty state: *"Nothing strong came back. Try a broader topic."*

After adding, the sheet dismisses. The user sees the queue with the newly added link(s).

A quiet footer beneath results: *"Search powered by Hacker News."* DM Mono 11pt, `subtle`.

---

## API Strategy

### Primary — HackerNews Algolia

```
GET https://hn.algolia.com/api/v1/search
  ?query={topic}
  &tags=story
  &numericFilters=points>30
  &hitsPerPage=10
```

Free, no API key, no rate limit for small-scale use. Crowd-vetted quality. Strong for technology, science, startups, philosophy, design, culture.

Fields used: `hit.title`, `hit.url` (filter out `nil` — text posts), `hit.points`.

Pick the top 3 hits with a valid `url`. Deduplicate by domain — no two results from the same site.

### Secondary — The Guardian Open Platform

Used when HN returns fewer than 3 valid results, or when the topic clearly skews toward news/culture.

```
GET https://content.guardianapis.com/search
  ?q={topic}
  &show-fields=trailText,wordcount
  &order-by=relevance
  &page-size=5
  &api-key={bundled_key}
```

Free tier, requires a developer API key bundled as a build-time constant in `Secrets.swift` (gitignored). Not user-facing.

Read time estimated from `fields.wordcount / 238`, rounded up.

### Blending

Try HN first. If ≥ 3 usable results → use only HN. If 1–2 → supplement with Guardian to reach 3. Never show source attribution beyond the HN footer.

---

## Read-Time Estimation

HN results don't include word count. Send a `HEAD` request for each HN result URL and check for Open Graph `article:reading_time` or Twitter card metadata. If unavailable, show no estimate rather than a placeholder — no read time is better than a wrong one.

---

## Technical Approach

### New: `DiscoveryService`

```swift
struct DiscoveryService {
    static func search(topic: String) async throws -> [DiscoveryResult]
}

struct DiscoveryResult: Sendable {
    let title: String
    let url: String
    let domain: String
    let estimatedMinutes: Int?
}
```

The service tries HN, supplements with Guardian if needed, deduplicates by domain, and returns up to 3.

Adding a result calls the same `QueuedLink` insert path as `AddLinkView` — no special handling.

### Privacy

The search query string is sent to HackerNews Algolia (and optionally The Guardian). This is the only point in Just… where user-generated text leaves the device, and only because the user explicitly triggered a search. No topic history is stored on-device.

`Secrets.swift` holds the Guardian API key as a build-time constant. It is gitignored. The file is manually added to new environments.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Not a feed | ✅ — One-shot, 3 results, no persistence |
| Not an archive | ✅ — Results are added to the queue individually, immediately |
| Condition-gated | ✅ — Only surfaces when both conditions are true |
| Honest about data | ✅ — "Search powered by Hacker News." disclosed |
| No history stored | ✅ — No past searches saved |
| Calm | ✅ — No ranking theatrics, no "trending" labels |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Empty state CTA | "Find something to read →" |
| Already-read-today state | "You read today. Come back tomorrow." |
| Sheet headline | "What do you want to read about?" |
| Input placeholder | "stoicism, climate, design…" |
| Too-niche empty state | "Nothing strong came back. Try a broader topic." |
| Results footer | "Search powered by Hacker News." |

---

## Acceptance Criteria

- [ ] "Find something to read →" appears in the empty state only when the user has not yet read today
- [ ] When queue is empty and user has read today, copy reads "You read today. Come back tomorrow." — no discovery button
- [ ] Typing a topic and searching returns up to 3 article cards
- [ ] Each card shows headline, domain, and read time when available; omits read time when unavailable
- [ ] + button adds the article to the queue via the standard `QueuedLink` insert path; card dims and shows checkmark
- [ ] No "add all" — each article is added independently
- [ ] HN results with nil URLs (text posts) are filtered out
- [ ] Fewer than 3 HN results are supplemented by Guardian results
- [ ] No two results from the same domain
- [ ] Fewer than 3 total results show "Nothing strong came back. Try a broader topic."
- [ ] "Search powered by Hacker News." footer shown beneath results in `subtle` style
- [ ] No topic search history stored on-device
- [ ] Guardian API key lives in `Secrets.swift`, gitignored
- [ ] Sheet dismisses after adding; queue contains the newly added link(s)
