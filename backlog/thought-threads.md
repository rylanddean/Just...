# Thought Threads

**Tier:** Free  
**Effort:** M  
**Status:** Backlog

After saving a reflection, on-device AI silently scans the Brain for entries that echo the article just finished. Up to 3 matching past entries surface at the bottom of the Reflect screen — not a notification, not an interruption. A quiet signal: *"You've thought about this before."*

---

## Why

Brain entries today are a list — valuable, but flat. Users add entries over months and never feel them compound. Thought Threads makes connections visible at the exact moment they matter most: right after reading and reflecting, when the idea is still warm.

The first time a user sees an entry from six months ago surface in response to something they just read, the Brain stops feeling like a reading log and starts feeling like memory. This is the feature that makes the Brain worth keeping.

---

## Experience

### Trigger

After `ReflectViewModel.save()` completes, a brief amber pulse (400ms) plays on the reflect screen background. Simultaneously, a detached `Task` begins scoring Brain entries. The save is never delayed.

### Display

Up to 3 thread cards slide in below the save confirmation, each showing:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You've been here before.

  Article title, 1 line               8 months ago
  "First 80 characters of their reflection,
   in Playfair Display italic."

  Article title, 1 line               2 months ago
  "Another reflection excerpt."
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- **"You've been here before."** — `.mono` style, `muted`. Not a celebration — a quiet observation.
- Article titles in `.headline` weight, `cream`.
- Reflection excerpts in Playfair Display italic, `muted`, 80 characters max.
- Relative date (e.g. "8 months ago") in `.label` style, `subtle`.

Tapping any card opens `BrainEntryDetail` in a sheet.

### None Found

The panel simply does not appear. No "no connections found" message. Silence is the correct response when nothing resonates.

### Threshold Logic

- Feature activates only when the Brain has ≥ 10 entries — below this there is not enough signal.
- Only entries with a relevance score ≥ 7/10 surface.
- The entry just saved is excluded from scoring.
- If threads arrive after the user has already dismissed the reflect screen, they are silently dropped.

---

## Technical Approach

### IntelligenceService

```swift
extension IntelligenceService {

    static func findThreads(
        for newEntry: BrainEntry,
        in brain: [BrainEntry]
    ) async -> [BrainEntry]
}
```

- Filters the Brain to entries with non-empty `reflection` text.
- Limits candidates to 50 (for latency — the on-device model has a bounded context window).
- Scores each candidate using a Foundation Models prompt; returns the top 3 with score ≥ 7, sorted descending.
- Runs on the default actor (no UI dependency).
- Requires `IntelligenceService.isAvailable` — feature is absent on non-Apple Intelligence devices.

### ReflectView Changes

```swift
@State private var threads: [BrainEntry] = []
```

Set from a `.task` that fires immediately after `viewModel.isSaved == true`:

```swift
.task(id: viewModel.isSaved) {
    guard viewModel.isSaved,
          IntelligenceService.isAvailable,
          entries.count >= 10 else { return }
    threads = await IntelligenceService.findThreads(for: savedEntry, in: entries)
}
```

The `@Query` for `BrainEntry` already lives in the parent view chain; pass the array in to avoid a redundant fetch.

Thread cards slide in with a `withAnimation(.easeOut(duration: 0.35))` transition when `threads` is set.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Calm, no pressure | ✅ — Cards are passive; no action required |
| Celebrates accumulation | ✅ — Surfaces the value of a growing Brain |
| AI is invisible | ✅ — No "AI found this" label; no model name |
| No false positives | ✅ — Score threshold of 7/10 keeps noise out |
| Graceful absence | ✅ — Feature entirely absent on non-AI devices |
| Never delays the save | ✅ — Detached task; save completes first |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Section header | "You've been here before." |
| No threads found | (no copy — panel absent) |

---

## Acceptance Criteria

- [ ] Thread cards appear after reflection is saved, below the save confirmation
- [ ] Each card shows article title, relative date, and reflection excerpt (≤ 80 chars, Playfair italic)
- [ ] Tapping a card opens `BrainEntryDetail` sheet
- [ ] No panel appears when no entries score ≥ 7
- [ ] No panel appears when Brain has fewer than 10 entries
- [ ] The entry just saved is never surfaced as its own thread
- [ ] Thread discovery runs in a detached task — save completes with no latency
- [ ] Panel is silently dropped if the user dismisses reflect before threads arrive
- [ ] Feature is entirely absent on non-Apple Intelligence devices — no UI stub, no error
- [ ] Candidate pool is capped at 50 entries for performance
