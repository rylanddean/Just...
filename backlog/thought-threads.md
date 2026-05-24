# Thought Threads

**Tier:** Free  
**Effort:** M  
**Status:** Backlog — Original Feature

After completing a reflection, on-device AI silently scans the Brain for entries that echo the article just finished. Up to 3 matching past entries surface at the bottom of the Reflect screen — not notifications, not interruptions. A quiet signal: *"You've thought about this before."* The Brain becomes a web, not a list.

---

## Why

Brain entries today are a list — valuable, but flat. Users add entries over months and never feel them compound. Thought Threads makes connections visible at the exact moment they matter most: right after reading and reflecting. The first time a user sees "You wrote something similar about this 6 months ago," the Brain goes from an archive to a living thing. This also deepens the habit loop — reflecting is more motivating when it visibly connects to a growing body of thought.

This is the feature that justifies calling it the *Brain*, not just a reading log.

---

## Experience

**Trigger:** After the user saves a reflection (or the countdown expires), a brief transition moment — 400ms, amber pulse — plays while the AI scores the new entry against the Brain in a background task.

**Display:** Up to 3 thread cards slide in below the save confirmation, each showing:
- Article title (truncated to 1 line)
- Date (relative: "8 months ago")
- First 60 characters of the past reflection, in Georgia italic

A quiet header above the cards: *"You've been here before."*

**Tap:** Opens `BrainEntryDetail` in a sheet.

**None found:** The panel simply doesn't appear. No "no connections found" message. Zero noise on the majority of reads.

**Threshold:** Only surfaces entries with a relevance score ≥ 7 out of 10. No low-confidence false positives.

**Minimum Brain size:** Feature activates only when the Brain has ≥ 10 entries. Below this, there is nothing meaningful to surface.

---

## Technical Approach

- `IntelligenceService.findThreads(for newEntry: BrainEntry, in entries: [BrainEntry]) async -> [BrainEntry]`  
- Scores all entries using a semantic relevance prompt. Returns up to 3 with score ≥ 7, sorted descending.  
- Runs in a detached `Task` immediately after `ReflectViewModel.save()` — never blocks the save.  
- Results held in `@State var threads: [BrainEntry]` on `ReflectView`, populated asynchronously. The card list slides in when threads arrive.  
- If threads arrive after the user has dismissed the reflect screen, they are silently dropped — no lingering state.  
- Requires iOS 26+ / Apple Intelligence. Graceful absence on unsupported devices — the feature simply does not exist.

```swift
// IntelligenceService
static func findThreads(
    for entry: BrainEntry,
    in brain: [BrainEntry]
) async -> [BrainEntry] {
    // Filter to entries with reflection text; limit to 50 candidates for speed
    // Score each against the new entry's title + reflection
    // Return top 3 with score >= 7
}
```

---

## Acceptance Criteria

- [ ] Up to 3 thread cards appear after reflection is saved
- [ ] Each card shows article title, relative date, and reflection excerpt
- [ ] Tap opens BrainEntryDetail sheet
- [ ] No panel shown when no entries score ≥ 7
- [ ] No panel shown when Brain has fewer than 10 entries
- [ ] Thread discovery runs asynchronously and never delays the save
- [ ] Panel does not appear if the user dismisses Reflect before threads arrive
- [ ] Feature entirely absent on non-Apple Intelligence devices
