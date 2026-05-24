# Activity Chart

**Tier:** Free  
**Effort:** S  
**Status:** Backlog

A compact row of daily activity squares shown to the right of the streak counter in `StreakHeader`. The last 7 days, at a glance — each square filled amber if the user read that day, muted if not. Matches the pattern established by Just Reps. Reading history becomes visible without navigating anywhere.

---

## Why

The streak number tells you the current run. The activity chart tells you the *shape* of your habit — whether you read every day last week, whether you've been patchy, whether today is the only gap. This context makes the streak feel earned and the at-risk state feel meaningful rather than arbitrary. It also gives users with a current streak of 1 a reason to keep going: they can see the chart filling in.

---

## Visual Design

```
 14          ░ ░ ░ ▓ ▓ ▓ ▓
 day streak  Mo Tu We Th Fr Sa Su
```

- **7 squares**, one per day, newest on the right (today).
- Square size: **10 × 10pt**, corner radius **3pt**, gap **4pt**.
- **Filled (amber `#E8A83E`, full opacity):** read that day.
- **Empty (`AppTheme.separator`):** no reading that day.
- **Today's square:** if unread and streak > 0 (at-risk), show a subtle amber ring (stroke only) instead of a filled square — the "hollow" signal that today's slot is waiting.
- **Today's square:** if read today, filled amber like any other day.
- **No day labels.** The squares are self-explanatory at this scale; labels would clutter the header.
- The chart sits right-aligned in the `HStack`, replacing the current trailing `Spacer()`.

---

## StreakHeader Redesign

Current layout:
```
[42]  day streak         [Spacer]
      read today to keep it
```

New layout:
```
[42]  day streak   ░ ░ ▓ ▓ ▓ ▓ ▓
      read today…
```

`StreakHeader` gains a new `recentActivity: [Bool]` parameter — a 7-element array where `true` = read, ordered oldest-first (index 0 = 6 days ago, index 6 = today). Computed in `HomeView` from `ReadingDay` records using `StreakEngine`.

Passing a computed `[Bool]` (rather than the raw `[ReadingDay]` array) keeps `StreakHeader` a pure display component with no service dependencies.

---

## Data Shape

```swift
// Computed in HomeView / emptyState from readingDays via StreakEngine
private var recentActivity: [Bool] {
    StreakEngine.recentActivity(days: readingDays, count: 7)
}
```

```swift
// New StreakEngine helper
// Returns an array of `count` booleans, oldest-first, where true = read that day.
static func recentActivity(days: [ReadingDay], count: Int) -> [Bool]
```

`ReadingDay` already stores `linksRead: Int` — future enhancement could show intensity (opacity proportional to `linksRead`) rather than binary filled/empty. That is a V2 refinement; V1 is binary.

---

## Component

```swift
// New component or inline in StreakHeader
struct ActivityChart: View {
    let days: [Bool]   // 7 elements, oldest-first

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, isRead in
                let isToday = index == days.count - 1
                RoundedRectangle(cornerRadius: 3)
                    .fill(isRead ? AppTheme.readerAccent : AppTheme.separator)
                    // Today unread: hollow ring instead of filled
                    .overlay {
                        if isToday && !isRead {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(AppTheme.readerAccent.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 10, height: 10)
            }
        }
    }
}
```

---

## Updated StreakHeader Signature

```swift
struct StreakHeader: View {
    let streak: Int
    let isAtRisk: Bool
    let recentActivity: [Bool]   // new — 7 elements
}
```

`HomeView` passes `recentActivity` to both its list and empty-state instances of `StreakHeader`.

---

## Acceptance Criteria

- [ ] 7 activity squares visible to the right of the streak counter in HomeView
- [ ] Filled amber = read that day; muted separator = no reading
- [ ] Today's square shows a hollow ring when unread (at-risk visual)
- [ ] Today's square fills amber when the user completes a read (real-time update via `@Query`)
- [ ] Squares are oldest-left / newest-right
- [ ] Chart renders correctly at all iPhone sizes — no overflow or clipping
- [ ] `StreakHeader` preview updated to include the new parameter
- [ ] `StreakEngine.recentActivity(days:count:)` unit tested for boundary cases (0 days, partial week, full week, 3AM grace window)
