# AI Contextual Reflect Prompt

**Tier:** Free  
**Effort:** S  
**Status:** Backlog

Use Apple Intelligence to generate a single, article-specific reflection question that appears as the placeholder in the Reflect window. Instead of a generic rotating prompt ("What stayed with you"), the user sees something like *"Does this change how you think about where your attention goes"* — written for the article they just finished.

---

## Why

The Reflect window's 60-second prompt is the most important moment in the app. A generic placeholder is still useful, but a question that speaks directly to what the user just read is qualitatively better — it removes the blank-page friction of "what do I even say about this?" and surfaces an angle the reader may not have considered. The architecture doc designs this feature in full; this ticket closes the gap between the design and a live implementation.

The constraint matters: one question, under 10 words, calm tone, no question mark. The brevity forces relevance — a long prompt is easier to ignore.

---

## Current State

The infrastructure already exists:

- `IntelligenceService.reflectPrompt(for summary: String)` — implemented as a stub that throws `unavailable`. The prompt construction and intent are correct; just needs the `LanguageModelSession` wired in when FoundationModels ships.
- `IntelligenceService.randomFallbackPrompt()` — already powers `ReflectView`'s `@State private var placeholder`.
- `ReaderViewModel.generateSummary(for body: String)` — already called after article load; pre-warms the summary. The reflect prompt should be generated in the same pass.

Missing wiring:
1. `ReaderViewModel` does not call `reflectPrompt(for:)` or store the result.
2. `ReflectView` receives no generated prompt — it always calls `randomFallbackPrompt()` on appear.
3. The generated prompt is never passed from `ReaderView` into `ReflectView`.

---

## Experience

**Generated state (iOS 26+, AI available):**  
The placeholder in the Reflect window text editor shows the generated question. Appears instantly — it was computed in the background while the user was reading. No loading state, no spinner.  
The prompt disappears the moment the user begins typing or speaking — it is never intrusive.

**Fallback state (no AI, or generation failed):**  
One of the 8 static prompts chosen randomly. Identical to the current experience. Zero degradation.

**Character budget:** Under 10 words. Never a question mark (the architecture doc specifies this; it makes the prompt feel more like an invitation than an interrogation).

**Example outputs:**
- *"Does this change how you think about attention"*
- *"What from this would you actually do"*
- *"Who in your life would disagree with this"*
- *"What assumption does this challenge for you"*

---

## Wiring Plan

**Step 1 — Store the generated prompt on `ReaderViewModel`:**
```swift
// ReaderViewModel
var generatedPrompt: String? = nil

private func generateSummary(for body: String) async {
    guard let summary = try? await IntelligenceService.summarize(body) else { return }
    // also generate the reflect prompt in the same task
    generatedPrompt = try? await IntelligenceService.reflectPrompt(for: summary)
}
```

**Step 2 — Pass it into `ReflectView` from `ReaderView`:**
```swift
// ReaderView — in openReflect()
pendingEntry = entry
// generatedPrompt already set on viewModel by the time user finishes reading

// fullScreenCover
ReflectView(
    entry: entry,
    link: link,
    prompt: viewModel.generatedPrompt,   // new parameter; nil = use fallback
    onComplete: { ... }
)
```

**Step 3 — `ReflectView` uses it instead of the fallback:**
```swift
// ReflectView
let prompt: String?   // new parameter

@State private var placeholder: String = ""

.onAppear {
    placeholder = prompt ?? IntelligenceService.randomFallbackPrompt()
}
```

**Timing:** The prompt is generated concurrently with article fetch and summary. By the time an average reader finishes an article (3–10 minutes), the on-device model has long since returned a result. No waiting, no race condition.

**FoundationModels activation:** When `LanguageModelSession` becomes available, replace the stub body in `IntelligenceService.reflectPrompt(for:)` with the session call. No other changes needed.

---

## Acceptance Criteria

- [ ] Generated prompt appears as the text editor placeholder in ReflectView on iOS 26+ / AI hardware
- [ ] Prompt is article-specific — different articles produce meaningfully different prompts
- [ ] Prompt disappears when user begins typing or speaking
- [ ] Fallback static prompt used when AI unavailable or generation fails
- [ ] No loading state or spinner — prompt is pre-generated during reading
- [ ] `generatedPrompt` is discarded after Reflect is dismissed — not persisted
- [ ] Prompt is under 10 words and has no trailing question mark
