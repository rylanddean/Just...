# Title Rewriting

**Tier:** Free (Apple Intelligence required)  
**Effort:** S  
**Status:** Backlog — Artifact-Inspired

When a link lands in the queue, on-device AI evaluates the title for sensationalism. If it detects manipulation, it silently rewrites to a calm, factual version. Shown wherever the article appears in the app. The original title is always recoverable with a tap. No flagging step. No crowdsourcing. Entirely private.

---

## Why

Just… strips images and distractions so you can think clearly. A clickbait title is framing — it tells you what to feel before you read a word. Removing that framing is as important as removing the banner ads.

Artifact proved this was their most-loved feature. Their key insight: headline manipulation is not a fact-checking problem, it is an attention problem. A title that withholds context to drive curiosity ("You Won't Believe What This Study Found") has already shaped the reader's expectations before a sentence is read. The reflect prompt "What stayed with you?" only works if you arrived at the article without that manipulation already in place.

Unlike Artifact, which required user flagging and human editorial review for a shared global feed, Just… can do this privately, on-device, automatically — every link, every time, no pipeline required.

---

## Experience

Rewriting fires in the background immediately after a link is added to the queue — the same timing as DNA extraction and quality grading. By the time the user opens their queue, the title has already been evaluated.

**Queue and reader:** If a rewrite was generated, the cleaned title is shown in `QueuedLinkRow` and the reader header. A small amber `✦` glyph appears to the right of the title — a quiet signal that the title was touched. Tapping the `✦` reveals the original as a muted subtitle and toggles back if preferred.

**Brain:** If the link is read and a reflection is saved, the `BrainEntry` stores the rewritten title as the display title. The `✦` indicator appears in `BrainEntryRow` and `BrainEntryDetail` for the same toggle behaviour.

**No rewrite found:** Nothing. No indicator, no noise, no "title looks fine" message. The title is simply the original.

**Settings:** Settings → Reading → "Rewrite clickbait titles" — default on, but the toggle is inert and labelled "Requires Apple Intelligence" on unsupported devices.

---

## Technical Approach

### Model changes

```swift
// QueuedLink.swift
var rewrittenTitle: String?       // nil = not clickbait or AI unavailable

// BrainEntry.swift
var rewrittenTitle: String?       // carried over from QueuedLink at save time
```

Both models add a computed display property:

```swift
var displayTitle: String { rewrittenTitle ?? title }
```

SwiftData migration is lightweight — new optional fields default to nil.

### IntelligenceService

```swift
@available(iOS 26, *)
@Generable
struct TitleAssessment {
    @Guide(description: """
        Assess this article headline for sensationalism, emotional manipulation,
        or information withholding designed to drive clicks.
        If it is clickbait: rewrite as a neutral, factual headline under 15 words.
        If it is not clickbait: return exactly the string "CLEAN".
        No quotation marks. No punctuation beyond what the headline requires.
        """)
    var result: String
}

@available(iOS 26, *)
static func rewriteTitle(_ title: String) async -> String? {
    let session = LanguageModelSession()
    let response = try? await session.respond(
        to: "Assess this headline: \(title)",
        generating: TitleAssessment.self
    )
    let result = response?.content.result ?? "CLEAN"
    return result == "CLEAN" ? nil : result
}
```

### Trigger points

**Manual queue add** (`QueueManager.add(url:)`): fire a detached `Task` immediately after insert. Rewritten title is applied before the next UI refresh.

**Feed articles** in `RSSFetchService`: fire in the same detached pass as quality grading — after `qualityGrade` is resolved, before save. Feed articles displayed in the Digest and Feed Detail views use `displayTitle`.

```swift
// Both trigger sites share the same guard
guard IntelligenceService.isAvailable,
      UserDefaults.standard.bool(forKey: "rewrite.enabled"),
      article.rewrittenTitle == nil else { return }

Task.detached {
    let rewrite = await IntelligenceService.rewriteTitle(article.title)
    await MainActor.run {
        article.rewrittenTitle = rewrite
        try? context.save()
    }
}
```

### UI

`TitleWithRewriteIndicator` — a new SwiftUI view used in `QueuedLinkRow`, reader header, `BrainEntryRow`, and `BrainEntryDetail`:

```swift
struct TitleWithRewriteIndicator: View {
    let displayTitle: String
    let originalTitle: String?          // nil when no rewrite exists
    @State private var showingOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(showingOriginal ? (originalTitle ?? displayTitle) : displayTitle)
                    .font(AppTheme.headline)
                    .foregroundStyle(AppTheme.Colors.cream)

                if originalTitle != nil {
                    Button { showingOriginal.toggle() } label: {
                        Text("✦")
                            .font(AppTheme.monoFont(11))
                            .foregroundStyle(showingOriginal
                                ? AppTheme.Colors.muted
                                : AppTheme.Colors.amber)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showingOriginal, let original = originalTitle {
                Text(original)
                    .font(AppTheme.monoFont(12))
                    .foregroundStyle(AppTheme.Colors.muted)
                    .lineLimit(2)
            }
        }
    }
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `Models/QueuedLink.swift` | Add `rewrittenTitle: String?`, `displayTitle` computed property |
| `Models/BrainEntry.swift` | Add `rewrittenTitle: String?`, `displayTitle` computed property |
| `Services/IntelligenceService.swift` | Add `TitleAssessment` Generable + `rewriteTitle()` |
| `Services/QueueManager.swift` | Fire rewrite task on link insert |
| `Services/RSSFetchService.swift` | Fire rewrite task in the grading pass |
| `Views/QueueView.swift` | Replace title display with `TitleWithRewriteIndicator` |
| `Views/ReaderView.swift` | Replace header title with `TitleWithRewriteIndicator` |
| `Views/BrainEntryRow.swift` | Replace title display with `TitleWithRewriteIndicator` |
| `Views/BrainEntryDetail.swift` | Replace title display with `TitleWithRewriteIndicator` |
| `Views/SettingsView.swift` | Add "Rewrite clickbait titles" toggle in Reading section |
| `Components/TitleWithRewriteIndicator.swift` | New component |

---

## Acceptance Criteria

- [ ] On link add, rewrite task fires asynchronously — UI is never blocked
- [ ] Rewritten title is shown in `QueuedLinkRow` when available
- [ ] Rewritten title is shown in the reader header when available
- [ ] `BrainEntry` carries the rewritten title from the corresponding `QueuedLink`
- [ ] Rewritten title is shown in `BrainEntryRow` and `BrainEntryDetail` when available
- [ ] `✦` indicator appears only when a rewrite exists — never on unmodified titles
- [ ] Tapping `✦` reveals the original title as a muted subtitle and inverts the indicator colour
- [ ] Tapping again hides the original and restores the rewritten view
- [ ] Original title is never deleted from the database
- [ ] No rewrite: no indicator, no empty space, no behavioural change
- [ ] "Rewrite clickbait titles" toggle in Settings → Reading, default on
- [ ] Toggle is disabled and captioned "Requires Apple Intelligence" on unsupported devices
- [ ] Rewriting also fires in `RSSFetchService` for feed articles, using `displayTitle` in Digest and Feed Detail
- [ ] All colours use `AppTheme.Colors` tokens — no hardcoded hex values
