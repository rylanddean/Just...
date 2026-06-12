# Brain-Ranked Digest

**Tier:** Free (Apple Intelligence required)  
**Effort:** M  
**Status:** Backlog — Artifact-Inspired

An opt-in setting that reorders articles within each Digest date section by their relevance to your Brain's most recent DNA words. Chronological groupings (TODAY, YESTERDAY, EARLIER) are preserved — but within each, the articles that match what you've been thinking about float to the top. Personalisation through accumulation, not engagement.

---

## Why

Artifact built their recommendation engine on a clear conviction: reading time is a better signal than clicks. A user who reads an article for eight minutes is showing something that a tap never could. Just… has the same signal, in a different form — Brain DNA captures what you actually thought about after reading, not just what you clicked.

The Digest today is purely chronological. On a busy day with 15 active feeds, the first article a user sees is random. Brain-ranked Digest means the first article they see is the one most likely to connect to what they've been reading about — making the daily reading decision easier and making the Brain feel more alive.

This is not a replacement for the topic filter (which hides articles). This reorders what's already there. Every article still appears; the ones that resonate simply rise.

The personalisation is entirely on-device. No server. No cross-user signals. The Brain belongs to the reader, and so does the ranking.

---

## Experience

**Default:** Off. The Digest remains chronological unless the user opts in.

**Settings:** Settings → Feeds → "Rank by Brain relevance" toggle. Caption: "Articles that match your Brain's recent reading rise to the top." On devices without Apple Intelligence, the toggle is disabled with the caption "Requires Apple Intelligence."

**When on:** Within each date section, articles are sorted by relevance score descending. Tied scores retain their original chronological order (stable sort). The section headers (TODAY, YESTERDAY, EARLIER, FROM YOUR BRAIN) and section membership are unchanged.

**"FROM YOUR BRAIN"** is unaffected — it is already curated by Brain relevance and always appears at the top.

**Insufficient Brain:** If the Brain has fewer than 5 entries, the setting is available but produces no visible reordering — there is not enough signal. A muted caption beneath the toggle: "Your Brain needs more entries to influence ranking." No error state, no prompt to read more — just an honest note.

**Reorder timing:** Scores are computed asynchronously when the Digest loads. Articles initially appear in their default order and silently reorder in place as scores arrive. No loading indicator, no flash — the list settles.

**No per-article indicators:** Individual cards show no "ranked for you" badge or explanation. The reordering is silent. Users who notice it can find the toggle; users who don't notice don't need to know.

---

## Technical Approach

### Settings

```swift
// DigestView.swift
@AppStorage("digest.brainRanked") private var brainRanked: Bool = false
```

### Brain DNA source

The ranking uses the top 5 DNA concept words across the 20 most recent Brain entries with a non-nil `dna` field. Computed once per Digest load.

```swift
// BrainViewModel or inline in DigestView
func recentConcepts(entries: [BrainEntry], limit: Int = 5) -> [String] {
    let recent = entries
        .filter { $0.dna != nil }
        .sorted { $0.savedAt > $1.savedAt }
        .prefix(20)
    var frequency: [String: Int] = [:]
    for entry in recent {
        entry.dna?.split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .forEach { frequency[$0, default: 0] += 1 }
    }
    return frequency.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
}
```

### Relevance scoring

```swift
// IntelligenceService (already planned — this uses the existing scoreRelevance method)
@available(iOS 26, *)
static func scoreRelevance(
    title: String,
    concepts: [String]
) async -> Double
```

If `IntelligenceService.scoreRelevance` is not yet implemented, a lightweight fallback: compute keyword overlap between `title.lowercased()` and each concept word, return a normalised 0.0–1.0 match score. This fallback requires no AI and gives a meaningful approximation for common cases.

### Scoring and sort

New `@Observable` class `DigestRelevanceStore` injected at the root level:

```swift
@Observable
final class DigestRelevanceStore {
    var scores: [UUID: Double] = [:]

    func score(for id: UUID) -> Double { scores[id] ?? 0 }

    func computeScores(for articles: [RSSArticle], concepts: [String]) {
        guard !concepts.isEmpty else { return }
        for article in articles where scores[article.id] == nil {
            Task.detached { [weak self] in
                let score = await IntelligenceService.scoreRelevance(
                    title: article.displayTitle,
                    concepts: concepts
                )
                await MainActor.run { self?.scores[article.id] = score }
            }
        }
    }
}
```

`DigestView` calls `relevanceStore.computeScores(for:concepts:)` on appear and after each fetch. Sort is applied to `todayArticles`, `yesterdayArticles`, and `earlierArticles`:

```swift
private func ranked(_ articles: [RSSArticle]) -> [RSSArticle] {
    guard brainRanked else { return articles }
    return articles.sorted { a, b in
        let sa = relevanceStore.score(for: a.id)
        let sb = relevanceStore.score(for: b.id)
        if sa != sb { return sa > sb }
        return a.publishedAt > b.publishedAt   // stable: chronological on tie
    }
}
```

Applied as: `ranked(todayArticles)`, etc.

Scores are in-memory for the session. Not persisted to SwiftData — they are cheap to recompute and would stale quickly as the Brain grows.

---

## Files Changed

| File | Change |
|------|--------|
| `Views/DigestView.swift` | `brainRanked` AppStorage; `ranked()` sort; `computeScores` trigger on appear |
| `Services/IntelligenceService.swift` | Implement `scoreRelevance(title:concepts:)` if not already present |
| `State/DigestRelevanceStore.swift` | New `@Observable` class |
| `App/RootView.swift` | Inject `DigestRelevanceStore` into environment |
| `Views/SettingsView.swift` | "Rank by Brain relevance" toggle in Feeds section |
| `ViewModels/BrainViewModel.swift` | `recentConcepts(entries:limit:)` helper |

---

## Acceptance Criteria

- [ ] "Rank by Brain relevance" toggle in Settings → Feeds, default off
- [ ] Toggle disabled and captioned "Requires Apple Intelligence" on unsupported devices
- [ ] When Brain has fewer than 5 entries with DNA, muted caption beneath the toggle indicates insufficient signal
- [ ] When on, articles in TODAY, YESTERDAY, EARLIER are sorted by descending relevance score
- [ ] Equal-scored articles retain their original chronological order (stable sort)
- [ ] Section headers and membership are unchanged — no articles move between sections
- [ ] "FROM YOUR BRAIN" section is unaffected
- [ ] Scores compute asynchronously and articles reorder silently in place as scores arrive
- [ ] No per-article indicator of ranking — reordering is invisible
- [ ] `DigestRelevanceStore` is injected at root and scores are in-memory only (not persisted)
- [ ] Relevance score uses top 5 DNA concepts from the 20 most recent Brain entries with non-nil `dna`
- [ ] Turning the toggle off immediately reverts to chronological order
- [ ] All colours and fonts use `AppTheme` tokens — no hardcoded values
