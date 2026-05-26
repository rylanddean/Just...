# Brain Diet

**Tier:** Free  
**Effort:** M  
**Status:** Backlog — Original Feature

The Brain view becomes a quiet nutritional label for your mind. A collapsible panel above the entry list surfaces what you've been feeding it — which topics keep returning, how often you reflect, which domains you reach for, and how your thinking has shifted over time. Not a dashboard. Not a report. A mirror.

---

## Why

Every entry in the Brain is a meal. Over time, patterns emerge — the same three domains, the same blank reflections late on Fridays, a sudden burst of curiosity about one topic then silence. Right now the Brain can't show you any of that. It is a list that grows but never speaks.

The Brain Diet makes the accumulation meaningful beyond the count. It answers the question users start asking once they have 50+ entries: *"What do I actually think about?"*

This also deepens the value of reflecting. When a user can see that their deepest reflections cluster around two topics, reflection stops feeling like a chore and starts feeling like a conversation with themselves. The habit becomes self-reinforcing.

---

## Experience

### Entry point

A section header — **"What you've been reading"** — sits between the BrainOrb and the entry list. It is collapsed by default on first load. A single chevron opens it. Once opened, state persists.

No dedicated tab. No new navigation. The Brain view already owns this.

---

### Panel sections

Each section is a single card. Cards use `surface` background, `amberDim` border, no shadows.

---

#### Your diet this week

Three to five `dna` concept words from the past 7 days, displayed as amber pills. If fewer than 3 entries this week, the section is omitted entirely — silence is more honest than sparse data.

```
READING THIS WEEK
━━━━━━━━━━━━━━━━
 stoicism   memory   attention   solitude
```

No percentages. No counts per word. The words speak for themselves.

---

#### How you've been reflecting

A quiet stat row:

```
REFLECTIONS
━━━━━━━━━━━━━━━━
  Kept     Skipped     Avg. time
   74%       26%          38s
```

"Kept" = entries with a non-empty reflection. "Skipped" = entries where the user skipped or let the timer expire without writing.  
"Avg. time" uses `reflectionSeconds` averaged across all entries with reflections.

No judgment copy. No "you could do better." The numbers are the message.

---

#### Where you've been reading

The top 3 domains by entry count, shown as a minimal ranked list:

```
YOUR SOURCES
━━━━━━━━━━━━━━━━
1   aeon.co          18 entries
2   paulgraham.com    9 entries
3   nautil.us         7 entries
```

Domain only — no favicons, no logos. Typography carries it.

---

#### Your reading rhythm

A 7-column micro-grid — one cell per day of the rolling week. Each cell fills amber based on whether a Brain entry was added that day. Empty days are `surface2`. No labels, no numbers. A visual habit trail.

```
LAST 7 DAYS
━━━━━━━━━━━━━━━━
  ▪  ▪  ●  ▪  ●  ●  ▪
  M  T  W  T  F  S  S
```

This is intentionally minimal. It does not surface streak data — that lives on Home. This is about Brain entry density, not streak continuity.

---

#### Over time (≥ 50 entries only)

A DNA word cloud of all-time dna words, ranked by frequency. The most recurring concept word renders at `title` scale; the least at `mono` scale. Up to 12 words. No percentages, no bar charts.

```
YOUR BRAIN OVER TIME
━━━━━━━━━━━━━━━━
         memory

  identity     attention     solitude

    power   language   meaning   craft

  systems   honesty   beauty
```

This section appears only once the Brain has ≥ 50 entries. Below that threshold, it is silently absent. A half-formed picture is worse than no picture.

---

### Tone & copy rules

- All section labels follow `.label` style: DM Mono, all-caps, amber, letter-spaced.
- No superlatives. "Your most-read domain" → just show the domain first.
- No comparisons to other users. Ever.
- No week-over-week deltas ("up 12% from last week"). Just the present state.
- If a section has insufficient data, it disappears. No empty states, no "nothing yet" messages.
- Copy pattern for future notifications related to Brain Diet: "Your Brain has been reading a lot of [word] lately." — one sentence, no punctuation at end.

---

## Technical Approach

All computation is client-side, on-demand. No background tasks. No new SwiftData models.

### New computed properties on `BrainViewModel`

```swift
// Top DNA words from last 7 days
func weeklyDNA(entries: [BrainEntry]) -> [String]

// Reflection completion rate (0.0–1.0) and average reflection seconds
func reflectionStats(entries: [BrainEntry]) -> (kept: Double, avgSeconds: Double)

// Top 3 domains by entry count
func topDomains(entries: [BrainEntry]) -> [(domain: String, count: Int)]

// Bool per day for rolling 7 days — true if ≥ 1 Brain entry that day
func weeklyActivity(entries: [BrainEntry]) -> [Bool]

// All-time DNA word frequency, sorted descending, capped at 12
func allTimeDNA(entries: [BrainEntry]) -> [(word: String, count: Int)]
```

No new services. No AI required. All derivable from existing `BrainEntry` fields.

### New component: `BrainDietPanel`

A SwiftUI `VStack` of `BrainDietCard` subviews. Each card receives its computed data directly — no view model access inside cards.

```
BrainDietPanel
├── WeeklyDNACard
├── ReflectionStatsCard
├── TopDomainsCard
├── WeeklyActivityCard
└── AllTimeDNACard (conditional on entries.count >= 50)
```

`BrainDietPanel` is inserted between `BrainOrb` and the `List` in `BrainView`, wrapped in a `DisclosureGroup`.

### No new persistence

All stats compute from the existing `@Query` result already in `BrainView`. No caching. Re-computed on each view appearance. Performance is acceptable given SwiftData fetch is already running.

---

## Acceptance Criteria

- [ ] Panel is collapsed by default; expands on tap; state persists across app launches (UserDefaults key: `brainDietExpanded`)
- [ ] `WeeklyDNACard` shows 3–5 dna words from last 7 days; hidden if fewer than 3 entries in window
- [ ] `ReflectionStatsCard` shows kept %, skipped %, and avg. reflection time in seconds
- [ ] `TopDomainsCard` shows top 3 domains ranked by entry count with entry counts
- [ ] `WeeklyActivityCard` shows 7-day activity grid with correct fill based on Brain entries (not ReadingDay)
- [ ] `AllTimeDNACard` only visible when Brain has ≥ 50 entries
- [ ] `AllTimeDNACard` shows up to 12 words scaled by frequency
- [ ] No empty state UI shown in any card — cards are absent when data is insufficient
- [ ] All colours use `AppTheme.Colors` tokens — no hardcoded hex values
- [ ] All labels use `.label` style (DM Mono, all-caps, amber, tracked)
- [ ] Panel does not introduce a new tab or navigation destination
- [ ] No comparisons to other users, no week-over-week deltas
- [ ] All stats compute from existing `BrainEntry` records — no new models or background tasks
