# Article DNA

**Tier:** Free  
**Effort:** S  
**Status:** Backlog — Original Feature

After reading, on-device AI distils the article into exactly 3 concept words — its DNA. These appear as a quiet visual tag on each Brain entry row (e.g. `attention · solitude · cost`). Not a summary. Not a category label. Three words that crystallise the article's essence at a glance. Over time, the Brain list becomes a scannable map of what the user has been thinking about.

---

## Why

Brain entries today show title, domain, date, and a reflection excerpt. To understand what an article was about six months later, you have to read the reflection. Article DNA gives each entry a fingerprint at a glance — three abstract concepts that act as a memory trigger.

DNA also creates emergent pattern recognition. A user who reads a lot about "attention" starts to notice it recurring across entries. A user who keeps seeing "power · language · framing" may notice a recurring preoccupation they weren't consciously aware of. This kind of self-knowledge is exactly what the Brain is for.

The constraint of exactly three words — lowercase, abstract nouns — is deliberate. Three words is enough to be meaningful. The constraint forces the model to distil rather than describe.

---

## Experience

**Display:** Three small text labels in a `HStack`, separated by `·`, shown in `BrainEntryRow` below the domain line. Same size as the domain text (11pt), in `AppTheme.textFaint` — ambient information, not primary.

**Example entries:**
```
attention · solitude · cost
language · power · silence
grief · time · repair
certainty · risk · identity
```

**Generation:** Runs asynchronously after the reflection is saved, alongside the existing summary generation. Stored in `BrainEntry.dna` (a new optional `String?` field).

**Fallback:** If AI is unavailable or generation fails, `dna` is nil and the row renders unchanged. No empty space, no placeholder.

---

## Technical Approach

```swift
@Generable struct ArticleDNA {
    @Guide(description: """
        Exactly 3 lowercase concept words that capture the core ideas of the article.
        Abstract nouns only — no verbs, no adjectives, no proper nouns.
        Separate with " · " (space · space).
        Examples: "attention · solitude · cost", "language · power · silence"
        """)
    var concepts: String
}

// IntelligenceService
@available(iOS 26, *)
static func extractDNA(from body: String) async throws -> String {
    let session = LanguageModelSession()
    let response = try await session.respond(
        to: "Extract the Article DNA from this text:\n\(body.prefix(3000))",
        generating: ArticleDNA.self
    )
    return response.content.concepts
}
```

- Runs in the same detached `Task` as `generateSummary` in `ReaderViewModel` — no additional latency.  
- Add `var dna: String?` to `BrainEntry`. Requires a lightweight SwiftData migration.  
- `BrainEntryRow` checks `entry.dna != nil` before rendering the concept tags.

---

## Acceptance Criteria

- [ ] DNA tag appears in BrainEntryRow for entries where AI generation succeeded
- [ ] Exactly 3 words, lowercase, separated by ` · `
- [ ] Row renders unchanged when `dna` is nil — no empty space
- [ ] Generation runs asynchronously and does not delay Brain list loading
- [ ] `dna` persists in SwiftData and survives app restarts
- [ ] `BrainEntry` SwiftData migration handles nil gracefully for existing entries
