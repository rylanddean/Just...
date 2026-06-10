# Reading Depth

**Tier:** Free  
**Effort:** S  
**Status:** Done

Artifact measured reading time rather than clicks because time is honest — it reflects actual engagement. Just… applies the same principle personally: when the scroll-to-reflect trigger fires, the app records how many seconds have passed since the article was opened. This reading time lives quietly on each Brain entry. It surfaces in Brain Diet as an average reading time stat, adapts the reflect prompt for unusually fast reads, and weights Thought Thread scoring so deeply-read entries connect more strongly.

---

## Why

Scroll-to-reflect already ensures you've seen the whole article. But there's a difference between blazing to the bottom in 8 seconds and spending 6 minutes with a 3,000-word essay. Both trigger the reflect window; only one reflects genuine engagement.

Reading time captures that distinction without any friction. It is a clock that starts when you open an article and stops when you reach the end — no buttons, no input, no UI.

The data is personal and private. Unlike Artifact, which used reading time to rank a global feed, Just… uses it purely for self-knowledge: surfacing patterns in your own reading behaviour and giving Thought Threads a better signal for what genuinely resonated.

---

## Experience

**During reading:** Completely invisible. No timer display, no progress bar. The reader is unchanged.

**Reflect prompt adaptation:** When the reflect window opens with `readingSeconds < estimatedSeconds * 0.2` — meaning the user moved through the article in under a fifth of the expected time — the prompt shifts from the standard rotation to: `"Anything catch your eye?"` This fits the pace without naming it. No nudge to go back and read more slowly.

The estimated read time is derived from the parsed article's word count at 238 wpm (4 words/second). For articles where word count is unavailable, the adapted prompt never fires — the standard rotation applies.

**Brain entry detail:** In `BrainEntryDetail`, the metadata row gains one quiet stat: `· 4 min` in `AppTheme.Colors.muted`, `DM Mono 11pt`. For very short reading times (< 60s), shows `· {n}s`. This is the only place `readingSeconds` is directly visible to the user.

**Brain Diet — Reflections card:** The existing stat row gains a fourth column:

```
REFLECTIONS
━━━━━━━━━━━━━━━━
  Kept    Skipped   Avg. reflect   Avg. read
   74%      26%          38s         4 min
```

"Avg. reflect" is the existing reflection writing time; "Avg. read" is the new article reading time. Both are averages across all Brain entries with non-zero values.

**Thought Threads weighting:** When `findThreads` scores candidate Brain entries, each score is multiplied by `min(1.0, readingSeconds / max(estimatedSeconds, 60))` — an entry where the user spent double the expected time gets full weight; one read in a fraction of that time is down-weighted. The ≥ 7 threshold applies to the weighted score.

---

## Technical Approach

### Model change

```swift
// BrainEntry.swift
var readingSeconds: Int = 0        // 0 for entries predating this feature
var estimatedReadSeconds: Int = 0  // derived from word count at save time; 0 if unavailable
```

Both default to 0 for existing entries — no migration complexity.

### Tracking in ReaderViewModel

```swift
// ReaderViewModel.swift
private var articleOpenedAt: Date?

func articleDidAppear() {
    articleOpenedAt = Date()
}

var elapsedReadingSeconds: Int {
    guard let opened = articleOpenedAt else { return 0 }
    return Int(Date().timeIntervalSince(opened))
}
```

`articleDidAppear()` is called from `ReaderView.onAppear`. `elapsedReadingSeconds` is read when the scroll-to-reflect trigger fires.

Word count is computed from the parsed article body already available in `ReaderViewModel`:

```swift
var estimatedReadSeconds: Int {
    let words = articleBody.split(separator: " ").count
    return words == 0 ? 0 : max(1, words / 4)   // 238 wpm ≈ 4 words/sec
}
```

### Handoff to ReflectViewModel

When the scroll-to-reflect trigger fires, both values are passed alongside the existing reflect trigger:

```swift
// ReflectViewModel.swift
func prepareReflect(readingSeconds: Int, estimatedReadSeconds: Int) {
    self.readingSeconds = readingSeconds
    self.estimatedReadSeconds = estimatedReadSeconds
}

func save(reflection: String) {
    entry.readingSeconds = readingSeconds
    entry.estimatedReadSeconds = estimatedReadSeconds
    // ...existing save logic
}
```

### Reflect prompt adaptation

```swift
// ReflectView.swift
private var promptText: String {
    let isRush = estimatedReadSeconds > 0
        && readingSeconds < Int(Double(estimatedReadSeconds) * 0.2)
    if isRush { return "Anything catch your eye?" }
    return staticPrompts[promptIndex]   // existing rotation
}
```

### Brain Diet stat

```swift
// BrainViewModel.swift — extend reflectionStats
func reflectionStats(entries: [BrainEntry]) -> (
    kept: Double,
    avgReflectSeconds: Double,
    avgReadSeconds: Double
) {
    let withReflections = entries.filter { !($0.reflection?.isEmpty ?? true) }
    let withReadTime    = entries.filter { $0.readingSeconds > 0 }
    let kept            = Double(withReflections.count) / Double(max(entries.count, 1))
    let avgReflect      = withReflections.map { Double($0.reflectionSeconds) }.average()
    let avgRead         = withReadTime.map { Double($0.readingSeconds) }.average()
    return (kept, avgReflect, avgRead)
}
```

`ReflectionStatsCard` formats `avgReadSeconds` as minutes/seconds using the same helper already used for `reflectionSeconds`.

### Thought Threads weighting

```swift
// IntelligenceService.findThreads
let weight = candidate.estimatedReadSeconds > 0
    ? min(1.0, Double(candidate.readingSeconds) / Double(max(candidate.estimatedReadSeconds, 60)))
    : 1.0   // no estimated time — don't penalise
let weightedScore = rawScore * weight
```

---

## Files Changed

| File | Change |
|------|--------|
| `Models/BrainEntry.swift` | Add `readingSeconds: Int = 0`, `estimatedReadSeconds: Int = 0` |
| `ViewModels/ReaderViewModel.swift` | Add `articleOpenedAt`, `articleDidAppear()`, `elapsedReadingSeconds`, `estimatedReadSeconds` |
| `Views/ReaderView.swift` | Call `viewModel.articleDidAppear()` on appear; pass values to reflect trigger |
| `ViewModels/ReflectViewModel.swift` | `prepareReflect(readingSeconds:estimatedReadSeconds:)`; store on `BrainEntry` at save |
| `Views/ReflectView.swift` | Adapt prompt when read time < 20% of estimated |
| `Views/BrainEntryDetail.swift` | Show `readingSeconds` in metadata row |
| `ViewModels/BrainViewModel.swift` | Extend `reflectionStats` to include `avgReadSeconds` |
| `Components/BrainDiet/ReflectionStatsCard.swift` | Add "Avg. read" stat column |
| `Services/IntelligenceService.swift` | Apply `readingSeconds` weight in `findThreads` scoring |

---

## Acceptance Criteria

- [ ] `readingSeconds` and `estimatedReadSeconds` stored on every new `BrainEntry`; existing entries default to 0 — no data loss
- [ ] Timer starts in `ReaderViewModel` when the article view appears
- [ ] Timer value and word-count estimate are passed to `ReflectViewModel` when the scroll-to-reflect trigger fires
- [ ] Both values are stored on `BrainEntry` at save time
- [ ] No timer or progress bar is visible in the reader during reading
- [ ] Reflect prompt changes to `"Anything catch your eye?"` when `readingSeconds < estimatedReadSeconds * 0.2` and `estimatedReadSeconds > 0`
- [ ] Standard prompt rotation applies when estimated read time is unavailable or pace is normal
- [ ] `BrainEntryDetail` shows reading time in muted metadata style (`· 4 min` or `· {n}s`)
- [ ] `ReflectionStatsCard` in Brain Diet shows "Avg. read" as a fourth stat
- [ ] "Avg. read" stat only averages entries where `readingSeconds > 0`
- [ ] `findThreads` weights candidates by reading time ratio; entries with no estimated time are unpenalised
- [ ] All colours and fonts use `AppTheme` tokens — no hardcoded values
