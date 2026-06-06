# Brain Revisit

**Tier:** Free  
**Effort:** L  
**Status:** Backlog

Once a day, the Brain surfaces one past entry to revisit. The entry is chosen using a lightweight spaced-repetition schedule — entries you haven't seen in a while surface before entries you saw recently. After reading the old entry, a compact text field lets you add a new thought. The original reflection stays intact. Both thoughts live on the same Brain entry.

---

## Why

The Brain never shrinks — but without revisiting, it becomes an archive. The compounding effect the product promises only materialises if old ideas come back into contact with new ones. This feature closes that loop.

Spaced repetition is the most research-backed memory system. Just… is not a flashcard app and should not feel like one — there are no cards to "pass" or "fail." The revisit is a suggestion, not an assignment. Declining is always available and has no consequence.

This is also the feature that makes the Brain worth re-opening on days when the queue is already empty or the streak is already safe.

---

## Experience

### Entry Point — BrainView

At the top of `BrainView`, above the BrainOrb and entry list, a single card appears when a revisit is due. It is dismissible and never blocks the rest of the view.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REVISIT

  Article title                       8 months ago
  
  "The original reflection text, shown in
   Playfair Display italic. Up to 4 lines,
   then truncated."

  [ Add a new thought ]               ×
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- **"REVISIT"** — `.label` style: DM Mono, all-caps, amber, letter-spaced.
- Article title in `.headline`, `cream`, 1 line.
- Relative date in `.label`, `subtle`.
- Original reflection in Playfair Display italic, `muted`, capped at 4 lines.
- **"Add a new thought"** — a tappable row that expands into a compact text field inline. No sheet, no navigation.
- **×** — dismisses the card for today. No snooze UI.

Tapping the article title opens the original URL in `SafariView`.

---

### Adding a New Thought

Tapping "Add a new thought" expands the card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REVISIT

  Article title                       8 months ago
  "The original reflection text…"

  ┌────────────────────────────────┐
  │ What do you think now?         │  ← placeholder, disappears on type
  └────────────────────────────────┘
                              [ Keep ]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- The text field is a single `TextEditor` constrained to 4 lines.
- **"Keep"** saves the new thought and dismisses the card. The entry's `revisitNote` is updated.
- Clearing the text field and tapping "Keep" with no input collapses the field without saving.
- Writing Tools are available in the text field automatically (iOS 18+).

### After Saving a New Thought

The card dismisses. In the entry list below, the matching `BrainEntryRow` gains a subtle "Revisited" indicator — a small amber dot next to the date. Tapping the row opens `BrainEntryDetail` which shows both the original reflection and the revisit note, chronologically labelled.

---

### Entry Selection — Revisit Schedule

The revisit engine runs once per day (evaluated on `BrainView` appear). It selects the single highest-priority entry according to:

```
priority = days_since_last_seen / (revisit_count + 1)
```

- `days_since_last_seen`: days since the entry was last shown as a revisit (or, if never shown, days since it was created).
- `revisit_count`: how many times this entry has been revisited.
- Higher priority = higher score. Older, less-revisited entries always surface first.

Minimum age to be eligible: 14 days old. Entries created in the past 14 days are excluded — they are still recent reading.

Minimum Brain size to activate: 10 entries. Below this, the card is absent.

The selected entry ID is cached in `UserDefaults` with the current date. The same entry is shown all day — no shuffle on re-open.

---

### Notification (Optional)

If the user has granted notification permission, a daily notification fires at 8AM:

> "Something worth revisiting."

No body copy. Tapping it opens Just… and scrolls `BrainView` to the revisit card. The notification does not fire on days when the Brain has fewer than 10 entries or no eligible entries exist.

No new permission prompt — reuses existing notification permission granted for streak reminders.

---

## Technical Approach

### Model Change — `BrainEntry`

Three new fields:

```swift
var revisitCount: Int = 0         // how many times this entry has been revisited
var lastRevisitedAt: Date? = nil  // nil until first revisit
var revisitNote: String? = nil    // most recent new thought (replaces on each revisit)
```

Lightweight migration — existing entries default to `revisitCount = 0`, `lastRevisitedAt = nil`.

### New Service — `RevisitEngine`

```swift
struct RevisitEngine {

    // Returns the single highest-priority eligible entry, or nil if Brain < 10 entries
    static func selectEntry(
        from entries: [BrainEntry],
        now: Date = .now
    ) -> BrainEntry?

    // Records that an entry was shown today — updates lastRevisitedAt, revisitCount
    static func recordSeen(entry: BrainEntry, context: ModelContext)

    // Records a new revisit note — updates revisitNote; does NOT touch revisitCount
    // (recordSeen is called when the card appears, not when a note is saved)
    static func saveNote(_ note: String, for entry: BrainEntry, context: ModelContext)
}
```

`selectEntry` evaluates `priority = daysSinceLastSeen / (revisitCount + 1)` for each eligible entry and returns the maximum.

### `BrainView` Changes

- New `@State var revisitEntry: BrainEntry?` populated on `onAppear`.
- Conditional `BrainRevisitCard` rendered above `BrainOrb`.
- `onAppear` calls `RevisitEngine.selectEntry`, checks `UserDefaults` cache to avoid showing a different entry on re-open within the same day.
- On dismiss (×): writes today's date to `UserDefaults["revisitDismissedDate"]`; card hidden for rest of day.

### `BrainEntryDetail` Changes

When `entry.revisitNote != nil`, show a second section below the original reflection:

```
ORIGINAL · March 12, 2024
"The original reflection text."

REVISITED · January 8, 2025
"The new thought."
```

Both dated absolutely. Section headers in `.label` style, `subtle`.

---

## Brand Alignment

| Principle | Check |
|---|---|
| Celebrates accumulation | ✅ — Makes the Brain compound over time |
| Calm, no pressure | ✅ — Card is dismissible; no consequence for ignoring |
| Not a flashcard app | ✅ — No pass/fail, no due counts, no streak penalty |
| Brain never shrinks | ✅ — Original reflection preserved; revisit note is additive |
| No alarm | ✅ — Notification copy is minimal and non-urgent |
| One thing at a time | ✅ — Only one revisit per day, ever |

---

## Copy Reference

| Moment | Copy |
|---|---|
| Card header | "REVISIT" (DM Mono, all-caps, amber) |
| New thought CTA | "Add a new thought" |
| Text field placeholder | "What do you think now?" |
| Save button | "Keep" |
| Notification | "Something worth revisiting." |
| Entry detail — original section | "ORIGINAL · [absolute date]" |
| Entry detail — revisit section | "REVISITED · [absolute date]" |

---

## Acceptance Criteria

- [ ] `BrainEntry` gains `revisitCount`, `lastRevisitedAt`, and `revisitNote` fields; existing entries unaffected
- [ ] `RevisitEngine.selectEntry()` uses `priority = daysSinceLastSeen / (revisitCount + 1)` and returns the highest-priority entry
- [ ] Entries created fewer than 14 days ago are excluded from selection
- [ ] Feature is absent when Brain has fewer than 10 entries
- [ ] Same entry is shown all day — cached in `UserDefaults` by date
- [ ] `BrainRevisitCard` appears at the top of `BrainView` above BrainOrb
- [ ] × dismisses the card for the rest of the day; does not affect `revisitCount`
- [ ] `recordSeen` is called when the card appears (not when dismissed or when a note is saved)
- [ ] Tapping article title opens the URL in `SafariView`
- [ ] "Add a new thought" expands an inline text field; "Keep" saves to `entry.revisitNote`
- [ ] Saving with no text does not update `revisitNote`
- [ ] `BrainEntryDetail` shows original reflection and revisit note in dated sections when both exist
- [ ] Daily 8AM notification fires: "Something worth revisiting." — only when eligible entry exists and notification permission is granted
- [ ] No new permission prompt for the notification
- [ ] All colours use `AppTheme.Colors` tokens — no hardcoded hex
