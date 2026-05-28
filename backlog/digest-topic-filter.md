# Digest Topic Filter

**Tier:** Free  
**Effort:** S  
**Status:** Done

Horizontally-scrolling chiplets beneath the Digest navigation bar let users filter visible articles by topic. Topics are derived from existing AI-generated feed category data — no new on-device inference required. Only the topics present in the current 7-day window are shown, capped at the 20 most common.

---

## The Problem

The Digest surfaces up to seven days of articles from every active feed simultaneously. A user with 20+ subscriptions across Technology, Design, Politics, and Science sees a dense, undifferentiated wall of content. There is no way to narrow to "just science today" without scrolling past everything else.

The filter is not a search. It is a narrowing lens — a way to read in context, one topic at a time, without leaving the Digest view.

---

## Experience

### The Filter Bar

A single horizontally-scrollable row of capsule chips appears between the navigation bar and the article list whenever two or more distinct topic categories are represented in the current Digest window.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [All]  [Technology]  [Science]  [Design]  [Politics]  …
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FROM YOUR BRAIN
  …
  TODAY
  …
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- **"All"** is always the first chip. It is selected by default. Tapping it clears any active filter.
- Remaining chips are sorted by descending article count in the current window.
- At most 20 topic chips are shown (after "All"). Topics with zero articles in the window never appear.
- The bar is hidden entirely when all articles share a single topic or when there are no articles.

### Chip Appearance

| State | Background | Text |
|-------|-----------|------|
| Selected | `accent` (`#E8A83E`) | `background` (`#0C0A08`) |
| Unselected | `surface` (`#141210`) | `textFaint` |

Font: DM Sans 13pt, semibold when selected, regular otherwise. Shape: capsule. Padding: 14pt horizontal, 7pt vertical. Gap between chips: 8pt. Leading and trailing padding matches `AppTheme.pagePadding`.

### Filtering Behaviour

- Selecting a chip hides all articles whose feed category does not match.
- Section headers (TODAY, YESTERDAY, EARLIER, FROM YOUR BRAIN) are suppressed when their section would be empty under the active filter.
- "FROM YOUR BRAIN" recommendations are filtered the same way as date sections — Brain picks outside the selected topic are hidden.
- If the active filter yields no articles, a calm inline message replaces the list: "Nothing here." in `.textFaint`.
- The selected topic resets to "All" whenever the Digest refreshes.

### Article-Level AI Topics

Topics are extracted per article by Apple Intelligence via a new `IntelligenceService.extractTopics(title:description:)` method. This produces 2–4 specific, recognizable labels per article — e.g. "iOS", "Nintendo", "OpenAI", "Climate Policy", "Rust" — at the level of a Wikipedia article title.

Topics are stored as `[String]` on `RSSArticle.topics` and generated during the fetch pipeline (after summarization, before grading) via `RSSFetchActor.tagPendingArticles()`. On devices without Apple Intelligence, `topics` stays empty and those articles appear only under "All".

---

## Technical Approach

### DigestView Changes

Add one `@State` property:

```swift
@State private var selectedTopic: String = "All"
```

Add a computed `availableTopics` property that counts feed categories across all current digest articles and returns "All" plus the top 20 by article count:

```swift
private var availableTopics: [String] {
    let all = todayArticles + yesterdayArticles + earlierArticles
    var counts: [String: Int] = [:]
    for article in all {
        if let cat = feedLookup[article.feedID]?.category, !cat.isEmpty {
            counts[cat, default: 0] += 1
        }
    }
    let top = counts.sorted { $0.value > $1.value }.prefix(20).map(\.key)
    return ["All"] + top
}
```

Add a `topicFilterBar` view:

```swift
private var topicFilterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            ForEach(availableTopics, id: \.self) { topic in
                Button { selectedTopic = topic } label: {
                    Text(topic)
                        .font(AppTheme.sansSerif(13, weight: selectedTopic == topic ? .semibold : .regular))
                        .foregroundStyle(selectedTopic == topic ? appTheme.background : appTheme.textFaint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(selectedTopic == topic ? appTheme.accent : appTheme.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
    }
    .padding(.vertical, 10)
    .background(appTheme.background)
}
```

Modify `digestItems` to apply the topic filter:

```swift
let topicMatch: (RSSArticle) -> Bool = { article in
    guard selectedTopic != "All" else { return true }
    return article.topics.contains(selectedTopic)
}
```

Integrate `topicFilterBar` into `body`:

```swift
VStack(spacing: 0) {
    if availableTopics.count > 1 {
        topicFilterBar
    }
    if articles.isEmpty {
        emptyState
    } else if digestItems.isEmpty {
        filteredEmptyState
    } else {
        digestList
    }
}
```

### Model Change — `RSSArticle`

Add one field with a safe default:

```swift
var topics: [String] = []
```

SwiftData handles this as a lightweight migration. Existing articles default to `[]` and are tagged on the next fetch.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Calm, no pressure | ✅ — Filter is a passive lens, no urgency |
| AI is on-device, opt-in, silent | ✅ — Tags articles in background, same as summarization and grading |
| Amber for active only | ✅ — Selected chip uses `accent`; inactive uses `surface` |
| No hardcoded hex | ✅ — All colours via `appTheme` tokens |
| No extra navigation | ✅ — Lives entirely within `DigestView` |
| Consistent with existing patterns | ✅ — Chip style matches `FeedDirectoryView.categoryPicker` |
| Handles missing data gracefully | ✅ — Articles without a feed category appear under "All" only |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Default chip | "All" |
| Topic chip | Feed category label (e.g. "Technology", "Design") |
| Filtered empty state | "Nothing here." |

---

## Acceptance Criteria

- [x] Topic filter bar appears in `DigestView` above the article list when two or more distinct categories are present
- [x] "All" chip is always first and selected by default
- [x] Selecting a chip filters TODAY, YESTERDAY, EARLIER, and FROM YOUR BRAIN sections
- [x] Section headers are hidden when their section is empty under the active filter
- [x] At most 20 topic chips are shown (not counting "All"), ordered by article count descending
- [x] Filter bar is hidden when all articles share one category or when there are no articles
- [x] Filtered empty state shows "Nothing here." when no articles match the active topic
- [x] Selected topic resets to "All" on digest refresh
- [x] All chip colours use `appTheme` tokens — no hardcoded hex
- [x] `RSSArticle` has `topics: [String] = []`; existing articles unaffected until next fetch
- [x] `IntelligenceService.extractTopics()` generates 2–4 specific, recognizable topic labels per article
- [x] `RSSFetchActor.tagPendingArticles()` tags untagged articles after summarization, before grading
- [x] On devices without Apple Intelligence, articles with empty `topics` appear only under "All"
- [x] No new navigation destinations
